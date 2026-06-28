import Foundation
import Observation

/// The shared app model. Single source of truth for the whole experience:
/// roster, the reactive `BrainState`, the current demo mode, the active draft,
/// and the command pipeline that voice, typed commands, and manual chips all
/// funnel through.
///
/// Person C's camera layer integrates via the small public surface:
///   - `appModel.peopleById[id]`
///   - `appModel.state.visiblePersonIds` / `appModel.state.dimmedPersonIds`
///   - `appModel.selectPerson(_:)`
///   - `appModel.applyMatch(_:)`
@MainActor
@Observable
final class AppModel {

    // MARK: - Owned state

    /// Full roster.
    private(set) var people: [PersonDTO] = []
    /// Fast lookup by id (used heavily by camera overlays + Brain nodes).
    private(set) var peopleById: [String: PersonDTO] = [:]

    /// The single reactive state shared by camera overlays and the Brain graph.
    private(set) var state = BrainStateDTO()

    /// Current demo fallback level.
    private(set) var demoMode: DemoMode

    /// Draft of the typed command bar (separate from the committed transcript).
    var commandDraft: String = ""

    /// Latest generated opener (drives the draft sheet).
    private(set) var draft: DraftResultDTO?
    /// True while an opener is being generated.
    private(set) var isDrafting = false

    /// Non-fatal status line for the transcript ribbon.
    private(set) var statusMessage: String?

    // MARK: - Identity resolution ("find info on him")

    /// Latest identity result (drives the identity sheet). nil until resolved.
    private(set) var identityResult: IdentityResolveResultDTO?
    /// True while an identity resolution is in flight (drives the ribbon).
    private(set) var isResolvingIdentity = false
    /// Phase line shown in the ribbon during resolution.
    private(set) var identityStatusMessage: String?
    /// Installed by `CameraViewModel.onAppear` so the command bar can trigger a
    /// capture from the live pixel buffer the camera owns. Cleared on disappear.
    @ObservationIgnored var identityCaptureHandler: ((String) async -> Void)?

    // MARK: - Backend

    private var backend: ReccoBackend
    /// Backend base URL (`RECCO_API_BASE_URL`, else `CONVEX_URL`). `nil` means
    /// no live backend — the app runs on the local fallback.
    private let apiBaseURL: URL?

    // MARK: - Convenience accessors (mirror the BrainState fields)

    var activeFilter: FilterCommandDTO { state.activeFilter }
    var visiblePersonIds: [String] { state.visiblePersonIds }
    var dimmedPersonIds: [String] { state.dimmedPersonIds }
    var selectedPersonId: String? { state.selectedPersonId }
    var lastTranscript: String? { state.lastTranscript }
    var isThinking: Bool { state.isThinking }

    /// Roster in display order with visible people first (used by the Brain grid).
    var peopleSortedByVisibility: [PersonDTO] {
        people.sorted { lhs, rhs in
            let lv = state.isVisible(lhs.id)
            let rv = state.isVisible(rhs.id)
            if lv != rv { return lv && !rv }
            return false
        }
    }

    var selectedPerson: PersonDTO? {
        guard let id = state.selectedPersonId else { return nil }
        return peopleById[id]
    }

    // MARK: - Init

    init(demoMode: DemoMode = .default, apiBaseURL: URL? = nil) {
        self.demoMode = demoMode
        self.apiBaseURL = apiBaseURL
        // Seed with bundled roster immediately so the UI is never empty, even
        // before `bootstrap()` runs.
        let seed = RosterStore.loadBundledPeople()
        self.backend = AppModel.makeBackend(mode: demoMode, people: seed, apiBaseURL: apiBaseURL)
        ingest(people: seed)
    }

    private static func makeBackend(mode: DemoMode, people: [PersonDTO], apiBaseURL: URL?) -> ReccoBackend {
        switch mode {
        case .mockAll:
            return MockBackend(people: people)
        case .mockCV, .live:
            return ConvexBackend(baseURL: apiBaseURL, mode: mode, fallbackPeople: people)
        }
    }

    // MARK: - Lifecycle

    /// Load the roster from the active backend. Safe to call repeatedly.
    func bootstrap() async {
        // Make a backend mode with no URL obvious instead of silently mock-y.
        if demoMode.usesBackend && apiBaseURL == nil {
            statusMessage = "\(demoMode.title): no backend URL — running local fallback. Set RECCO_API_BASE_URL."
        }
        do {
            let loaded = try await backend.listPeople()
            ingest(people: loaded)
        } catch {
            // Keep the already-seeded roster; just say why it's local.
            statusMessage = "Using local roster (\(error.localizedDescription))"
        }
    }

    private func ingest(people: [PersonDTO]) {
        self.people = people
        self.peopleById = Dictionary(uniqueKeysWithValues: people.map { ($0.id, $0) })
        // Everyone visible until a filter narrows the set.
        if state.visiblePersonIds.isEmpty {
            state.visiblePersonIds = people.map(\.id)
            state.dimmedPersonIds = []
            state.updatedAt = now()
        }
    }

    // MARK: - Demo mode switching

    func setDemoMode(_ mode: DemoMode) {
        guard mode != demoMode else { return }
        demoMode = mode
        backend = AppModel.makeBackend(mode: mode, people: people, apiBaseURL: apiBaseURL)
        statusMessage = "Demo mode: \(mode.title)"
        Task { await bootstrap() }
    }

    // MARK: - Command pipeline (the one path everything funnels through)

    /// Apply a fully-formed command directly. Manual chips use this (no
    /// network), and the async command runner also ends here after parsing.
    func apply(_ command: FilterCommandDTO) {
        switch command.action {
        case .draft:
            // Drafting keeps the current visible/dimmed partition; just record
            // intent and kick off generation if we have a target.
            state.activeFilter = command
            state.lastTranscript = command.rawText ?? "Draft opener"
            state.updatedAt = now()
            if let target = command.targetPersonId {
                selectPerson(target)
                Task { await draftOpener(for: target) }
            } else {
                statusMessage = "Pick a person to draft an opener."
            }

        case .reset:
            let partition = FilterEngine.partition(people: people, command: command)
            state.activeFilter = .reset
            state.visiblePersonIds = partition.visible
            state.dimmedPersonIds = partition.dimmed
            state.highlightedPersonId = nil
            state.lastTranscript = command.rawText ?? "Reset"
            state.updatedAt = now()

        case .filter, .rank:
            let partition = FilterEngine.partition(people: people, command: command)
            state.activeFilter = command
            state.visiblePersonIds = partition.visible
            state.dimmedPersonIds = partition.dimmed
            state.lastTranscript = command.rawText ?? command.summary
            state.updatedAt = now()
        }
    }

    /// Run a free-text transcript through the (mock or live) interpreter, with
    /// visible partial transcript + thinking state, then apply the result.
    /// This is the shared voice/typed entry point.
    func runCommand(_ transcript: String) async {
        let text = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        // 0. Identity lane intercepts before the filter parser.
        if isIdentityCommand(text) {
            await runIdentityCommand(text)
            return
        }

        // 1. Partial transcript immediately.
        state.lastTranscript = text
        state.isThinking = true
        state.updatedAt = now()

        do {
            // 2 + 3. Interpret (mock = on-device, live = backend action).
            let command = try await backend.interpretCommand(
                transcript: text,
                visiblePersonIds: state.visiblePersonIds
            )
            // 4. Apply through the same path as chips.
            apply(command)
        } catch {
            // Safe fallback: interpret on-device so voice/typed commands keep
            // working even if the backend is down. (Filtering is non-destructive.)
            apply(CommandInterpreter.interpret(text, people: people))
            statusMessage = "Backend unavailable — interpreted locally."
        }

        // 5. Done thinking.
        state.isThinking = false
        state.updatedAt = now()
    }

    /// Convenience for the typed command bar: runs the current draft text.
    func submitTypedCommand() {
        let text = commandDraft
        commandDraft = ""
        Task { await runCommand(text) }
    }

    // MARK: - Manual chips

    /// Toggle a single tag chip. Multiple active chips OR together (matching the
    /// backend filter semantics). Routes through the exact same `apply` path as
    /// voice/typed commands.
    func toggleTag(_ tag: String) {
        var include = Set(state.activeFilter.action == .reset ? [] : state.activeFilter.includeTags)
        if include.contains(tag) {
            include.remove(tag)
        } else {
            include.insert(tag)
        }
        if include.isEmpty {
            apply(.reset)
        } else {
            let ordered = TagVocabulary.all.filter { include.contains($0) }
            apply(FilterCommandDTO(
                action: .filter,
                includeTags: ordered,
                rankBy: .relevance,
                rawText: "Show me \(ordered.joined(separator: " + ")) people"
            ))
        }
    }

    /// Is a chip currently active?
    func isTagActive(_ tag: String) -> Bool {
        state.activeFilter.action != .reset && state.activeFilter.includeTags.contains(tag)
    }

    func reset() {
        draft = nil
        apply(.reset)
    }

    // MARK: - Selection (Person C calls this from overlays)

    func selectPerson(_ personId: String?) {
        state.selectedPersonId = personId
        state.updatedAt = now()
    }

    func deselect() {
        state.selectedPersonId = nil
        state.updatedAt = now()
    }

    /// Set the user-visible status line. Used by the camera lane to explain
    /// degraded states (e.g. live mode on the Simulator, where there are no real
    /// pixels to recognize) without faking a match.
    func setStatus(_ message: String?) {
        statusMessage = message
    }

    // MARK: - Face match ingestion (Person C feeds camera results here)

    /// Apply a recognition result: record the match and highlight the person so
    /// the Brain graph and any overlays light up consistently.
    func applyMatch(_ match: FaceMatchResultDTO) {
        state.lastMatch = match
        if match.shouldShowOverlay, let id = match.personId {
            state.highlightedPersonId = id
        }
        state.updatedAt = now()
    }

    /// Recognize a face crop through the demo-mode-aware backend (Person C's
    /// camera seam). `mockAll`/`mockCV` return deterministic matches; `live`
    /// calls Person B's `vision:matchFace` Convex action. The camera never
    /// reaches the CV service directly and holds no secrets — it goes through
    /// here so demo-mode switching stays centralized.
    func recognizeFace(imageBase64: String, trackId: String) async throws -> FaceMatchResultDTO {
        try await backend.matchFace(imageBase64: imageBase64, imageMimeType: "image/jpeg", trackId: trackId)
    }

    // MARK: - Drafting

    func draftOpener(for personId: String, userGoal: String? = nil) async {
        guard let person = peopleById[personId] else { return }
        isDrafting = true
        draft = nil
        do {
            let result = try await backend.createOpener(personId: personId, userGoal: userGoal)
            draft = result
        } catch {
            // Safe fallback: generate the opener on-device so the demo never
            // ends on an empty draft sheet.
            draft = OpenerGenerator.draft(for: person, userGoal: userGoal)
            statusMessage = "Backend unavailable — drafted locally."
        }
        isDrafting = false
    }

    func clearDraft() {
        draft = nil
    }

    // MARK: - Identity resolution ("find info on him")

    /// Phrases that route to the identity lane instead of the filter parser.
    private static let identityPhrases = [
        "find info", "who is he", "who is she", "who is this",
        "find info on this person", "who's that", "who is that",
        "get his linkedin", "get her linkedin", "his linkedin", "her linkedin",
        "look him up", "look her up", "find out who",
    ]

    /// True when a transcript should trigger "find info on him".
    func isIdentityCommand(_ text: String) -> Bool {
        let lower = text.lowercased()
        return AppModel.identityPhrases.contains { lower.contains($0) }
    }

    /// Entry point for the identity lane. Delegates the capture to the camera
    /// (which owns the live pixel buffer); falls back to a handler-less resolve
    /// with empty crops when no camera is mounted (so typed commands still work).
    func runIdentityCommand(_ transcript: String) async {
        let text = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        state.lastTranscript = text
        state.updatedAt = now()
        isResolvingIdentity = true
        identityResult = nil
        identityStatusMessage = "Locking target…"

        if let handler = identityCaptureHandler {
            await handler(text)
        } else {
            await resolveIdentity(
                transcript: text, trackId: "manual",
                faceImageBase64: "", contextImageBase64: ""
            )
        }
    }

    /// Update the phase line the ribbon shows while the camera does its work.
    func setIdentityPhase(_ message: String) {
        identityStatusMessage = message
    }

    /// Run the captured crops through the backend identity lane and publish the
    /// result. Called by CameraViewModel (with real crops) or directly.
    func resolveIdentity(
        transcript: String,
        trackId: String,
        faceImageBase64: String,
        contextImageBase64: String
    ) async {
        isResolvingIdentity = true
        if identityStatusMessage == nil || identityStatusMessage == "Locking target…" {
            identityStatusMessage = "Reading badge · searching · verifying…"
        }
        do {
            let result = try await backend.resolveIdentity(
                transcript: transcript, trackId: trackId,
                faceImageBase64: faceImageBase64, contextImageBase64: contextImageBase64
            )
            identityResult = result
            identityStatusMessage = result.message ?? result.confidenceLabel
        } catch {
            identityResult = IdentityResolveResultDTO(
                trackId: trackId, status: .error,
                message: error.localizedDescription
            )
            identityStatusMessage = "Couldn't resolve: \(error.localizedDescription)"
        }
        isResolvingIdentity = false
        state.updatedAt = now()
    }

    /// Dismiss the identity result sheet.
    func clearIdentity() {
        identityResult = nil
        identityStatusMessage = nil
    }

    // MARK: - Helpers

    private func now() -> Double { Date().timeIntervalSince1970 * 1000 }
}
