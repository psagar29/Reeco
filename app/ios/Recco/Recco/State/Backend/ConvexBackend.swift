import Foundation

/// Live/`mockCV` backend placeholder. This is the integration seam for Person
/// B's Convex functions. Until the Convex Swift client is wired in, every call
/// delegates to a local fallback so the app stays fully demoable — exactly the
/// behavior the Person D fallback plan asks for ("If Convex Swift is slow: use
/// HTTP action calls or local JSON. Keep the app demoable.").
///
/// To go live, replace each `// TODO(convex)` body with a real call:
///   - `people:list`            -> listPeople()
///   - `voice:interpretCommand` -> interpretCommand()
///   - `drafts:createOpener`    -> createOpener()
///   - `vision:matchFace`       -> matchFace()  (mockCV returns deterministic)
final class ConvexBackend: ReccoBackend {
    let convexURL: URL?
    let mode: DemoMode
    /// Offline fallback that keeps the demo recoverable.
    private let fallback: MockBackend

    init(convexURL: URL?, mode: DemoMode, fallbackPeople: [PersonDTO]) {
        self.convexURL = convexURL
        self.mode = mode
        self.fallback = MockBackend(people: fallbackPeople)
    }

    func listPeople() async throws -> [PersonDTO] {
        // TODO(convex): query `people:list`.
        try await fallback.listPeople()
    }

    func interpretCommand(transcript: String, visiblePersonIds: [String]) async throws -> FilterCommandDTO {
        // TODO(convex): action `voice:interpretCommand`.
        try await fallback.interpretCommand(transcript: transcript, visiblePersonIds: visiblePersonIds)
    }

    func createOpener(personId: String, userGoal: String?) async throws -> DraftResultDTO {
        // TODO(convex): action `drafts:createOpener`.
        try await fallback.createOpener(personId: personId, userGoal: userGoal)
    }

    func matchFace(imageBase64: String, imageMimeType: String, trackId: String) async throws -> FaceMatchResultDTO {
        // mockCV: deterministic local match. live: TODO(convex) action `vision:matchFace`.
        try await fallback.matchFace(imageBase64: imageBase64, imageMimeType: imageMimeType, trackId: trackId)
    }
}
