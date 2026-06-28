import Foundation

/// Abstraction over the data/AI backend. `mockAll` uses `MockBackend` (fully
/// offline). `mockCV` / `live` would use `ConvexBackend` (HTTP actions). The
/// app only ever talks to this protocol, so swapping in Person B's real Convex
/// client later is a one-line change in `AppModel.makeBackend`.
protocol ReccoBackend: Sendable {
    /// Roster (`people:list`).
    func listPeople() async throws -> [PersonDTO]

    /// Natural-language → filter command (`voice:interpretCommand`).
    func interpretCommand(transcript: String, visiblePersonIds: [String]) async throws -> FilterCommandDTO

    /// Opener / email draft (`drafts:createOpener`).
    func createOpener(personId: String, userGoal: String?) async throws -> DraftResultDTO

    /// Face recognition for a captured crop (`vision:matchFace`). Person C's
    /// camera layer calls this; included here so the seam is defined.
    func matchFace(imageBase64: String, imageMimeType: String, trackId: String) async throws -> FaceMatchResultDTO

    /// Resolve the identity of a locked target — "find info on him". Reads the
    /// badge (OpenAI Vision), finds candidates (Fiber), and face-verifies them
    /// (CV service), all server-side. `POST /api/identity/resolve` ->
    /// `identity:resolveTarget`. The two crops are: a tight face crop (for
    /// verification) and a wider person/badge crop (for OCR). Both are base64
    /// JPEG and may be empty in `mockAll`.
    func resolveIdentity(
        transcript: String,
        trackId: String,
        faceImageBase64: String,
        contextImageBase64: String
    ) async throws -> IdentityResolveResultDTO

    // MARK: - Mission ("Today's Goal")

    /// Parse a free-text event goal into a structured mission
    /// (`POST /api/mission/parse`). Stored per `clientId` server-side.
    func parseMission(clientId: String, rawText: String) async throws -> MissionProfileDTO

    /// The stored mission for a client, if any (`POST /api/mission/current`).
    func currentMission(clientId: String) async throws -> MissionProfileDTO?

    // MARK: - Brain scan memory ("event memory")

    /// All saved scan memories for a client, newest first
    /// (`GET /api/brain/memories?clientId=…`).
    func listScanMemories(clientId: String?) async throws -> [ScanMemoryDTO]

    /// Create/update a memory from an identity result, deduped per-client. Scores
    /// it against the mission when one is included (`POST /api/brain/memories/upsert`).
    func upsertScanMemory(_ input: ScanMemoryInputDTO) async throws -> ScanMemoryDTO

    /// Re-score an existing memory against a mission (`POST /api/brain/memories/score`).
    func scoreScanMemory(id: String, clientId: String?, mission: MissionProfileDTO) async throws -> ScanMemoryDTO?

    /// Save notes onto a memory (`POST /api/brain/memories/notes`).
    func updateScanMemoryNotes(id: String, notes: String?) async throws -> ScanMemoryDTO?

    /// Update the follow-up status (and optional edited outreach / sentAt) on a
    /// memory (`POST /api/brain/memories/follow-up-status`). Drives "Sent".
    func updateFollowUpStatus(
        id: String,
        status: FollowUpStatus,
        channel: FollowUpChannel?,
        editedOutreach: OutreachDraftDTO?,
        sentAt: Double?
    ) async throws -> ScanMemoryDTO?

    /// Generate (and persist) mission-aware outreach variants for a memory
    /// (`POST /api/brain/memories/outreach`).
    func generateScanMemoryOutreach(
        id: String,
        eventName: String?,
        senderName: String?,
        mission: MissionProfileDTO?
    ) async throws -> OutreachDraftDTO

    // MARK: - Lazy GTM / Scout Mode

    /// Parse a voice/text GTM request, find ~`count` prospects (Fiber, mock
    /// fallback), score + draft them, and persist a run (`POST /api/gtm/run`).
    func runGTMScout(clientId: String, transcript: String, count: Int?) async throws -> GTMRunResultDTO

    /// Past Scout runs, newest first (`GET /api/gtm/runs?clientId=…`).
    func listGTMRuns(clientId: String) async throws -> [GTMRunDTO]

    /// Prospects for a run (or all for a client) (`GET /api/gtm/prospects?…`).
    func listGTMProspects(clientId: String, runId: String?) async throws -> [GTMProspectDTO]

    /// Regenerate outreach for a prospect (`POST /api/gtm/prospects/outreach`).
    func generateGTMOutreach(id: String, eventName: String?, senderName: String?) async throws -> OutreachDraftDTO

    /// Update a prospect's channel/status/edited outreach/sentAt — drives the
    /// fake "Sent" (`POST /api/gtm/prospects/status`).
    func updateGTMProspectStatus(
        id: String,
        status: GTMProspectStatus,
        channel: FollowUpChannel?,
        editedOutreach: OutreachDraftDTO?,
        sentAt: Double?
    ) async throws -> GTMProspectDTO?
}

enum BackendError: LocalizedError {
    case notConfigured(String)
    case unknownPerson(String)

    var errorDescription: String? {
        switch self {
        case .notConfigured(let what): return "Backend not configured: \(what)"
        case .unknownPerson(let id): return "Unknown person: \(id)"
        }
    }
}
