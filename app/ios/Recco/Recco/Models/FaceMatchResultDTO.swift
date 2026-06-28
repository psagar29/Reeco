import Foundation

/// Face crop quality metadata. Mirrors `FaceQuality` from API contracts.
struct FaceQualityDTO: Codable, Equatable, Hashable {
    let faceDetected: Bool
    let detectionScore: Double?
    let cropWidth: Double?
    let cropHeight: Double?
    let model: String?

    init(
        faceDetected: Bool,
        detectionScore: Double? = nil,
        cropWidth: Double? = nil,
        cropHeight: Double? = nil,
        model: String? = nil
    ) {
        self.faceDetected = faceDetected
        self.detectionScore = detectionScore
        self.cropWidth = cropWidth
        self.cropHeight = cropHeight
        self.model = model
    }
}

/// Result of a face-recognition attempt. Mirrors `FaceMatchResult` from
/// `docs/API_CONTRACTS.md`. Person C's camera layer produces these (via the
/// backend); Person D consumes `personId` to drive overlays/selection.
struct FaceMatchResultDTO: Codable, Equatable, Hashable {
    enum Status: String, Codable {
        case matched
        case tentative
        case unknown
        case noFace = "no_face"
        case error
    }

    let trackId: String
    let status: Status
    let personId: String?
    let score: Double?
    let quality: FaceQualityDTO?
    let message: String?
    let latencyMs: Double?

    init(
        trackId: String,
        status: Status,
        personId: String? = nil,
        score: Double? = nil,
        quality: FaceQualityDTO? = nil,
        message: String? = nil,
        latencyMs: Double? = nil
    ) {
        self.trackId = trackId
        self.status = status
        self.personId = personId
        self.score = score
        self.quality = quality
        self.message = message
        self.latencyMs = latencyMs
    }

    /// Overlays should only be shown for confident matches (per contract).
    var shouldShowOverlay: Bool { status == .matched }
}
