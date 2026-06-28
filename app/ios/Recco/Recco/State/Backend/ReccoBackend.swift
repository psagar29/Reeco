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
