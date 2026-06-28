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
    /// Drives the optional full-detail identity sheet, opened from the hologram
    /// panel's "Details" button. The in-camera AR panel is the primary result
    /// surface, so the sheet is opt-in rather than auto-presented.
    var showIdentityDetail = false
    /// Installed by `CameraViewModel.onAppear` so the command bar can trigger a
    /// capture from the live pixel buffer the camera owns. Cleared on disappear.
    @ObservationIgnored var identityCaptureHandler: ((String) async -> Void)?

    // MARK: - Backend

    private var backend: ReccoBackend
    /// Backend base URL (`RECCO_API_BASE_URL`, else `CONVEX_URL`). `nil` means
    /// no live backend — the app runs on the local fallback.
    private let apiBaseURL: URL?

    /// Deepgram streaming-token endpoint (`<base>/api/voice/deepgram-token`), or
    /// `nil` when voice can't run: no backend URL, or fully-offline `mockAll`.
    /// The Deepgram key never lives on-device; this only mints a short-lived
    /// token from Person B's backend.
    var deepgramTokenEndpoint: URL? {
        guard demoMode != .mockAll, let base = apiBaseURL else { return nil }
        return base.appendingPathComponent("api/voice/deepgram-token")
    }

    /// Whether press-to-talk voice can run in the current mode/config.
    var isVoiceAvailable: Bool { deepgramTokenEndpoint != nil }

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
        // Anonymous per-install id (no auth) so each device's Brain stays its own.
        self.clientId = AppModel.loadOrCreateClientId()
        // Restore the saved mission ("Today's Goal") from a previous launch.
        self.missionProfile = AppModel.loadStoredMission()
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
        // Load the Brain event memory in the background; never blocks the roster.
        Task { await loadScanMemories() }
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
    /// Matched as case-insensitive substrings, so each entry also covers its
    /// longer variants (e.g. "find me info" covers "find me information about
    /// this person", "who is this" covers "who is this person").
    private static let identityPhrases = [
        // "find info(rmation)" family
        "find info", "find me info", "find some info", "find information",
        "find out who", "find out about",
        // "who is …" family
        "who is he", "who is she", "who is this", "who is that",
        "who's this", "who's that", "who am i looking at",
        // look-up family
        "look him up", "look her up", "look them up",
        "look this person up", "look up this", "look up who",
        // anyone asking for a LinkedIn is asking us to identify the person
        "linkedin",
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
            // Auto-save into Brain event memory in the background — never blocks
            // the camera UI or the result sheet.
            Task { await saveIdentityResultToBrain(result, transcript: transcript) }
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
        showIdentityDetail = false
        // A dismissed scan should also stop the ribbon's "Finding info…" spinner,
        // even if an in-flight resolve is still settling in the background.
        isResolvingIdentity = false
    }

    // MARK: - Voice (Deepgram press-to-talk)

    /// True while the mic is actively streaming to Deepgram.
    private(set) var isListening = false
    /// Live transcript shown while listening (accumulated finals + current
    /// partial). Updated on every result; commands never run off this.
    private(set) var partialTranscript = ""
    /// The committed transcript captured at stop; shown briefly as "Processing…"
    /// while `runCommand` handles it, then cleared.
    private(set) var finalTranscript = ""
    /// Non-fatal voice error (e.g. Deepgram not configured). Cleared on next start.
    private(set) var voiceError: String?

    /// Active speech client + accumulated segments. Observation-ignored: these
    /// are plumbing, not rendered state.
    @ObservationIgnored private var speechClient: DeepgramSpeechClient?
    @ObservationIgnored private var finalSegments: [String] = []
    @ObservationIgnored private var currentPartial = ""

    /// The full transcript so far: finalized segments plus the in-flight partial.
    private var combinedTranscript: String {
        (finalSegments + (currentPartial.isEmpty ? [] : [currentPartial]))
            .joined(separator: " ")
    }

    /// Begin streaming mic audio to Deepgram. Live results update
    /// `partialTranscript`; nothing runs until `stopListening()`. If voice is
    /// unavailable (offline mode / no backend / stub token) this surfaces a
    /// non-fatal `voiceError` and the typed bar remains the fallback.
    func startListening() {
        guard !isListening else { return }
        voiceError = nil
        finalTranscript = ""
        partialTranscript = ""
        finalSegments = []
        currentPartial = ""

        guard let endpoint = deepgramTokenEndpoint else {
            voiceError = "Voice unavailable — set RECCO_API_BASE_URL and use Live or Mock CV."
            return
        }

        let client = DeepgramSpeechClient(tokenEndpoint: endpoint)
        speechClient = client
        isListening = true

        // Callbacks are delivered on the main queue by the client, so it is safe
        // to assume main-actor isolation and update state synchronously in order.
        Task {
            await client.start(
                onTranscript: { [weak self] text, isFinal in
                    MainActor.assumeIsolated { self?.ingestTranscript(text, isFinal: isFinal) }
                },
                onError: { [weak self] error in
                    MainActor.assumeIsolated { self?.handleVoiceError(error) }
                }
            )
        }
    }

    /// Stop streaming. When `run` is true and we captured anything, run the final
    /// transcript through the shared command pipeline exactly once.
    func stopListening(run: Bool = true) {
        let wasActive = isListening || speechClient != nil
        isListening = false
        speechClient?.stop()
        speechClient = nil
        guard wasActive else { return }

        let captured = combinedTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
        partialTranscript = ""
        finalSegments = []
        currentPartial = ""

        guard run, !captured.isEmpty else { finalTranscript = ""; return }
        finalTranscript = captured
        Task {
            await runCommand(captured)
            // Drop the "Processing…" line once handled (unless a new capture began).
            if finalTranscript == captured { finalTranscript = "" }
        }
    }

    private func ingestTranscript(_ text: String, isFinal: Bool) {
        guard isListening else { return }
        if isFinal {
            finalSegments.append(text)
            currentPartial = ""
        } else {
            currentPartial = text
        }
        partialTranscript = combinedTranscript
    }

    private func handleVoiceError(_ error: Error) {
        if let dg = error as? DeepgramSpeechClient.DeepgramError {
            voiceError = dg.errorDescription ?? "Voice unavailable."
        } else {
            voiceError = error.localizedDescription
        }
        // Non-fatal: drop the mic and keep the typed fallback. Don't auto-run.
        stopListening(run: false)
    }

    // MARK: - Mission ("Today's Goal")

    /// Anonymous per-install id. Scopes Brain memories + mission server-side.
    let clientId: String
    /// The current mission, persisted across launches. nil until set up.
    private(set) var missionProfile: MissionProfileDTO?
    /// True while a mission is being parsed (drives the setup loading state).
    private(set) var isParsingMission = false

    /// First launch shows mission setup until a mission exists.
    var hasCompletedMissionSetup: Bool { missionProfile != nil }

    private static let clientIdKey = "recco.clientId"
    private static let missionKey = "recco.mission.v1"

    static func loadOrCreateClientId() -> String {
        let d = UserDefaults.standard
        if let id = d.string(forKey: clientIdKey), !id.isEmpty { return id }
        let id = "client_" + UUID().uuidString.lowercased()
        d.set(id, forKey: clientIdKey)
        return id
    }

    static func loadStoredMission() -> MissionProfileDTO? {
        guard let data = UserDefaults.standard.data(forKey: missionKey) else { return nil }
        return try? JSONDecoder().decode(MissionProfileDTO.self, from: data)
    }

    private func persistMission(_ mission: MissionProfileDTO?) {
        if let mission, let data = try? JSONEncoder().encode(mission) {
            UserDefaults.standard.set(data, forKey: Self.missionKey)
        } else {
            UserDefaults.standard.removeObject(forKey: Self.missionKey)
        }
    }

    /// Parse free text into a structured mission (backend, with on-device
    /// fallback), persist it, and re-score the Brain.
    func parseMission(rawText: String) async {
        isParsingMission = true
        let text = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            let parsed = try await backend.parseMission(clientId: clientId, rawText: text)
            setMission(parsed)
        } catch {
            setMission(MissionParser.parse(text))
        }
        isParsingMission = false
    }

    /// Skip setup → a sensible default mission so scoring still works.
    func skipMissionSetup() {
        setMission(MissionParser.parse("General networking"))
    }

    /// Replace the mission directly (edit flow).
    func updateMission(_ mission: MissionProfileDTO) { setMission(mission) }

    /// Debug helper: clear the mission so setup shows again next launch.
    func clearMissionForTesting() {
        missionProfile = nil
        persistMission(nil)
    }

    private func setMission(_ mission: MissionProfileDTO) {
        var m = mission
        if m.clientId == nil { m.clientId = clientId }
        missionProfile = m
        persistMission(m)
        // Re-score every memory against the new mission so the graph updates.
        scanMemories = scanMemories.map(scoreForDisplay)
    }

    /// Score a memory against the active mission for display, preserving any
    /// follow-up state (status/sentAt/edited outreach). No mission → unchanged.
    private func scoreForDisplay(_ memory: ScanMemoryDTO) -> ScanMemoryDTO {
        guard let mission = missionProfile else { return memory }
        let r = LeadScorer.score(memory, mission: mission)
        return memory.replacingLead(
            priority: r.priority,
            score: r.score,
            reasons: r.reasons,
            nextAction: r.nextAction.rawValue,
            missionSnapshot: MissionProfileDTO(rawText: mission.rawText, goalType: mission.goalType)
        )
    }

    // MARK: - Brain (event memory)

    /// All saved scan memories, newest first.
    private(set) var scanMemories: [ScanMemoryDTO] = []
    /// True while (re)loading the memory list.
    private(set) var isLoadingBrain = false
    /// Non-fatal Brain error (list/notes/outreach).
    private(set) var brainError: String?
    /// True while outreach is being generated for the open memory.
    private(set) var isGeneratingOutreach = false
    /// The memory currently open in the Brain detail surface.
    var selectedMemoryId: String?

    /// Event/sender context woven into generated outreach. Overridable via env
    /// for a specific demo (e.g. `RECCO_EVENT_NAME=Orange Slice`).
    private static let eventName: String =
        ProcessInfo.processInfo.environment["RECCO_EVENT_NAME"] ?? "the event"
    private static let senderName: String =
        ProcessInfo.processInfo.environment["RECCO_SENDER_NAME"] ?? "Pranav"

    /// The memory open in the detail surface, looked up live so edits/outreach
    /// re-render it.
    var selectedMemory: ScanMemoryDTO? {
        guard let id = selectedMemoryId else { return nil }
        return scanMemories.first { $0.id == id }
    }

    func memory(id: String) -> ScanMemoryDTO? {
        scanMemories.first { $0.id == id }
    }

    /// Load the saved scan memories for this client, scored against the mission.
    func loadScanMemories() async {
        isLoadingBrain = true
        brainError = nil
        do {
            let loaded = try await backend.listScanMemories(clientId: clientId)
            scanMemories = loaded.map(scoreForDisplay)
        } catch {
            brainError = error.localizedDescription
        }
        isLoadingBrain = false
    }

    /// Pull-to-refresh / refresh button entry point.
    func refreshBrain() async { await loadScanMemories() }

    /// Persist an identity result into Brain memory (deduped server-side). Best
    /// effort: a failure never affects the camera/result UI. Skips info-less
    /// results so the Brain doesn't fill with noise.
    func saveIdentityResultToBrain(_ result: IdentityResolveResultDTO, transcript: String?) async {
        let best = result.bestCandidate
        let clue = result.clue
        let name = best?.fullName ?? clue?.fullName
        let hasName = !(name?.trimmingCharacters(in: .whitespaces).isEmpty ?? true)
        let hasCandidate = best != nil
        // Skip pure errors / empty needs-clarification with nothing to remember.
        if !hasName && !hasCandidate { return }
        if result.status == .error && !hasCandidate { return }

        let badge = (clue?.rawText.isEmpty == false) ? clue?.rawText : nil
        let input = ScanMemoryInputDTO(
            scanId: result.trackId,
            status: result.status.rawValue,
            clientId: clientId,
            mission: missionProfile,
            name: name,
            headline: best?.headline,
            role: best?.role ?? clue?.role,
            company: best?.company ?? clue?.company,
            school: best?.school ?? clue?.school,
            linkedinUrl: best?.linkedinUrl,
            email: best?.email,
            confidenceScore: result.verification?.score ?? clue?.confidence,
            personId: nil,
            transcript: transcript,
            badgeText: badge,
            hadFaceVerification: result.verification?.faceDetected ?? false,
            candidateCount: result.candidates.count
        )
        do {
            let saved = try await backend.upsertScanMemory(input)
            let scored = scoreForDisplay(saved)
            mergeMemoryIntoList(saved)
            // A subtle nudge when a strong lead lands — never blocks the camera.
            if scored.leadPriority == .hot {
                statusMessage = "🔥 Hot lead saved to Brain"
            }
        } catch {
            // Best-effort: Brain save never interrupts the scan flow.
        }
    }

    /// Save (or clear) notes on a memory.
    func updateMemoryNotes(id: String, notes: String?) async {
        do {
            if let updated = try await backend.updateScanMemoryNotes(id: id, notes: notes) {
                mergeMemoryIntoList(updated)
            }
        } catch {
            brainError = "Couldn't save notes: \(error.localizedDescription)"
        }
    }

    /// Generate (and persist) outreach variants for a memory.
    func generateOutreach(memoryId: String) async {
        isGeneratingOutreach = true
        brainError = nil
        do {
            let draft = try await backend.generateScanMemoryOutreach(
                id: memoryId,
                eventName: AppModel.eventName,
                senderName: AppModel.senderName,
                mission: missionProfile
            )
            if let i = scanMemories.firstIndex(where: { $0.id == memoryId }) {
                scanMemories[i] = scanMemories[i].replacingOutreach(draft)
            }
        } catch {
            brainError = "Couldn't generate outreach: \(error.localizedDescription)"
        }
        isGeneratingOutreach = false
    }

    /// Replace an existing memory in place, or insert it at the front. Scores it
    /// against the active mission so the graph reflects priority immediately.
    private func mergeMemoryIntoList(_ memory: ScanMemoryDTO) {
        let scored = scoreForDisplay(memory)
        if let i = scanMemories.firstIndex(where: { $0.id == scored.id }) {
            scanMemories[i] = scored
        } else {
            scanMemories.insert(scored, at: 0)
        }
    }

    /// Fake "Send" (and any follow-up status change). Updates locally for a snappy
    /// UI, then persists. We never actually send email/LinkedIn — status only.
    func updateFollowUpStatus(
        id: String,
        status: FollowUpStatus,
        channel: FollowUpChannel? = nil,
        editedOutreach: OutreachDraftDTO? = nil
    ) async {
        let sentAt: Double? = status == .sent ? now() : memory(id: id)?.sentAt
        // Optimistic local update.
        if let i = scanMemories.firstIndex(where: { $0.id == id }) {
            scanMemories[i] = scanMemories[i].replacingFollowUp(
                status: status,
                channel: channel ?? scanMemories[i].followUpChannel,
                editedOutreach: editedOutreach ?? scanMemories[i].editedOutreach,
                sentAt: sentAt
            )
        }
        do {
            if let updated = try await backend.updateFollowUpStatus(
                id: id, status: status, channel: channel, editedOutreach: editedOutreach, sentAt: sentAt
            ) {
                mergeMemoryIntoList(updated)
            }
        } catch {
            brainError = "Couldn't update follow-up: \(error.localizedDescription)"
        }
    }

    // MARK: - Lazy GTM / Scout Mode

    /// Past Scout runs (newest first).
    private(set) var gtmRuns: [GTMRunDTO] = []
    /// Prospects for the active run.
    private(set) var gtmProspects: [GTMProspectDTO] = []
    /// The run currently shown in the Scout view.
    private(set) var activeGtmRun: GTMRunDTO?
    /// True while a Scout search is in flight (drives the premium loading state).
    private(set) var isRunningGTM = false
    /// Phase line shown while searching ("Searching profiles…").
    private(set) var gtmStatusMessage: String?
    /// Non-fatal Scout error.
    private(set) var gtmError: String?
    /// Drives presentation of the Scout results view.
    var showScout = false

    func gtmProspect(id: String) -> GTMProspectDTO? { gtmProspects.first { $0.id == id } }

    /// Run a voice/text GTM request → a scored set of AI-found prospects. Never
    /// mixes into `scanMemories` (Scout prospects are not real people met).
    func runGTMScout(transcript: String, count: Int? = nil) async {
        let text = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        isRunningGTM = true
        gtmError = nil
        gtmStatusMessage = "Understanding your request…"

        // Premium phase ticker (cosmetic; the real work is the backend call).
        let phases = ["Searching profiles…", "Ranking leads…", "Drafting outreach…"]
        let ticker = Task { [weak self] in
            for phase in phases {
                try? await Task.sleep(for: .milliseconds(500))
                guard let self, self.isRunningGTM else { return }
                self.gtmStatusMessage = phase
            }
        }

        do {
            let result = try await backend.runGTMScout(clientId: clientId, transcript: text, count: count)
            activeGtmRun = result.run
            gtmProspects = result.prospects
            gtmRuns.insert(result.run, at: 0)
            showScout = true
        } catch {
            gtmError = error.localizedDescription
        }
        ticker.cancel()
        isRunningGTM = false
        gtmStatusMessage = nil
    }

    func loadGTMRuns() async {
        do { gtmRuns = try await backend.listGTMRuns(clientId: clientId) }
        catch { gtmError = error.localizedDescription }
    }

    func loadGTMProspects(runId: String?) async {
        do { gtmProspects = try await backend.listGTMProspects(clientId: clientId, runId: runId) }
        catch { gtmError = error.localizedDescription }
    }

    func generateGTMOutreach(prospectId id: String) async {
        do {
            let draft = try await backend.generateGTMOutreach(
                id: id, eventName: AppModel.eventName, senderName: AppModel.senderName
            )
            if let i = gtmProspects.firstIndex(where: { $0.id == id }) {
                gtmProspects[i] = gtmProspects[i].replacingOutreach(draft)
            }
        } catch {
            gtmError = "Couldn't draft outreach: \(error.localizedDescription)"
        }
    }

    /// Fake "Sent" (and other status changes) for a Scout prospect. No real
    /// message is ever sent — status only.
    func updateGTMProspectStatus(
        id: String,
        status: GTMProspectStatus,
        channel: FollowUpChannel? = nil,
        editedOutreach: OutreachDraftDTO? = nil
    ) async {
        let sentAt: Double? = status == .sent ? now() : gtmProspect(id: id)?.sentAt
        if let i = gtmProspects.firstIndex(where: { $0.id == id }) {
            gtmProspects[i] = gtmProspects[i].replacingStatus(
                status: status,
                channel: channel ?? gtmProspects[i].selectedChannel,
                outreach: editedOutreach,
                sentAt: sentAt
            )
        }
        do {
            if let updated = try await backend.updateGTMProspectStatus(
                id: id, status: status, channel: channel, editedOutreach: editedOutreach, sentAt: sentAt
            ), let i = gtmProspects.firstIndex(where: { $0.id == updated.id }) {
                gtmProspects[i] = updated
            }
        } catch {
            gtmError = "Couldn't update prospect: \(error.localizedDescription)"
        }
    }

    // MARK: - Helpers

    private func now() -> Double { Date().timeIntervalSince1970 * 1000 }
}
