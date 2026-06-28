import Foundation

/// A single recognition request for one tracked face.
struct RecognitionRequest {
    /// Stable temporary id for the tracked face.
    let trackId: String
    /// Base64 JPEG of the cropped face. Empty when running off the simulated
    /// source (no real pixels) — the mock client ignores it.
    let imageBase64: String
    /// Rank of this face by on-screen size, 0 = largest/closest. The mock uses
    /// this to deterministically map the biggest face to a demo person.
    let faceRank: Int
}

/// Abstraction over "turn a face crop into a `FaceMatchResultDTO`". The camera
/// pipeline depends only on this protocol, so swapping mock <-> live is a single
/// assignment driven by `appModel.demoMode`.
protocol RecognitionClient: AnyObject {
    func recognize(_ request: RecognitionRequest) async throws -> FaceMatchResultDTO
}

/// Deterministic, **no-backend** recognition. Proves the whole overlay pipeline
/// works with zero network (the `mockAll` stage-safe default). Maps the largest
/// faces in frame to the first roster people, in order, unless a specific person
/// is forced from the debug picker.
final class MockRecognitionClient: RecognitionClient {
    /// Roster used for the deterministic mapping (display order).
    var people: [PersonDTO]
    /// Debug force-match: when set, every face resolves to this person.
    var forcedPersonId: String?
    /// Simulated round-trip latency (ms) reported back for the debug HUD.
    private let fakeLatencyMs: Double

    init(people: [PersonDTO], forcedPersonId: String? = nil, fakeLatencyMs: Double = 40) {
        self.people = people
        self.forcedPersonId = forcedPersonId
        self.fakeLatencyMs = fakeLatencyMs
    }

    func recognize(_ request: RecognitionRequest) async throws -> FaceMatchResultDTO {
        // Forced match (debug picker) always wins.
        if let forced = forcedPersonId, people.contains(where: { $0.id == forced }) {
            return matched(forced, trackId: request.trackId)
        }
        // Map the Nth-largest face to the Nth roster person. Faces beyond the
        // roster size read as "unknown" so we never invent a wrong card.
        guard request.faceRank >= 0, request.faceRank < people.count else {
            return FaceMatchResultDTO(
                trackId: request.trackId, status: .unknown, personId: nil,
                score: 0.12, message: "No confident match", latencyMs: fakeLatencyMs
            )
        }
        return matched(people[request.faceRank].id, trackId: request.trackId)
    }

    private func matched(_ personId: String, trackId: String) -> FaceMatchResultDTO {
        FaceMatchResultDTO(
            trackId: trackId,
            status: .matched,
            personId: personId,
            score: 0.46,                       // > strongMatchScore (0.38)
            quality: FaceQualityDTO(faceDetected: true, detectionScore: 0.9,
                                    cropWidth: 180, cropHeight: 180, model: "mock"),
            message: nil,
            latencyMs: fakeLatencyMs
        )
    }
}

/// Live / `mockCV` recognition. Routes the crop through Person D's
/// demo-mode-aware backend via the `AppModel.recognizeFace` passthrough, which
/// in turn calls Person B's `vision:matchFace` Convex action (or the
/// deterministic Convex fallback in `mockCV`). Keeps the camera in its lane: it
/// never talks to OpenAI / Deepgram / the CV service directly, and holds no keys.
///
/// Not actor-isolated itself (so it conforms cleanly to the non-isolated
/// `RecognitionClient` protocol); it simply `await`s into the main-actor
/// `AppModel`, which is the correct hop for a `@MainActor` model.
final class BackendRecognitionClient: RecognitionClient {
    private unowned let appModel: AppModel

    init(appModel: AppModel) {
        self.appModel = appModel
    }

    func recognize(_ request: RecognitionRequest) async throws -> FaceMatchResultDTO {
        // No pixels (e.g. simulated source) -> nothing to send.
        guard !request.imageBase64.isEmpty else {
            return FaceMatchResultDTO(trackId: request.trackId, status: .noFace,
                                      message: "No frame")
        }
        return try await appModel.recognizeFace(
            imageBase64: request.imageBase64,
            trackId: request.trackId
        )
    }
}
