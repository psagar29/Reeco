import Foundation
import Vision
import CoreGraphics
import CoreVideo

/// A single tracked face for one frame, expressed in **normalized top-left**
/// coordinates (0...1) ready for SwiftUI. `faceRank` is 0 for the largest face.
struct FaceObservation: Identifiable {
    let trackId: String
    /// Smoothed, normalized, top-left rect (0...1) in the preview's space.
    let rect: CGRect
    /// Vision's raw detection confidence (0...1), surfaced in debug.
    let detectionConfidence: Float
    /// 0 = largest face in frame.
    let faceRank: Int

    var id: String { trackId }
    var center: CGPoint { CGPoint(x: rect.midX, y: rect.midY) }
}

/// Detects faces per-frame with Vision and assigns each a **stable temporary
/// `trackId`** by associating detections across frames via IoU. Boxes are
/// EMA-smoothed so 2-3 faces don't flicker.
///
/// Design note: per-frame `VNDetectFaceRectanglesRequest` + IoU association is
/// used instead of `VNTrackObjectRequest` sequence tracking — it is simpler and
/// more robust for short-lived event faces, while still yielding stable ids and
/// smooth boxes (the property the demo needs). Not thread-safe; call from a
/// single (capture) queue.
final class FaceTracker {

    private struct Track {
        let id: String
        var smoothedRect: CGRect
        var lastSeenFrame: Int
        var detectionConfidence: Float
    }

    private var tracks: [Track] = []
    private var frameIndex = 0

    /// IoU above which a new detection is considered the same face as a track.
    private let associationIoU: CGFloat = 0.25
    /// Drop a track after it has been missing this many frames.
    private let maxMissedFrames = 8

    /// Run detection on a frame and return the current set of tracked faces.
    /// - Parameters:
    ///   - pixelBuffer: the camera frame.
    ///   - orientation: image orientation to feed Vision.
    ///   - mirrored: true for the front camera (preview is mirrored).
    func process(pixelBuffer: CVPixelBuffer,
                 orientation: CGImagePropertyOrientation,
                 mirrored: Bool) -> [FaceObservation] {
        frameIndex += 1

        let request = VNDetectFaceRectanglesRequest()
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer,
                                            orientation: orientation,
                                            options: [:])
        do {
            try handler.perform([request])
        } catch {
            return currentObservations()
        }

        let detections: [(rect: CGRect, conf: Float)] = (request.results ?? []).map { face in
            let normalized = FaceGeometry.visionToNormalizedTopLeft(face.boundingBox, mirrored: mirrored)
            return (normalized, face.confidence)
        }

        associate(detections: detections)
        prune()
        return currentObservations()
    }

    /// Reset all tracks (e.g. camera flip / app foreground).
    func reset() {
        tracks.removeAll()
    }

    // MARK: - Association

    private func associate(detections: [(rect: CGRect, conf: Float)]) {
        var unmatched = Array(detections.indices)

        // Greedily match each existing track to its best-overlapping detection.
        for i in tracks.indices {
            var bestJ: Int?
            var bestIoU: CGFloat = associationIoU
            for j in unmatched {
                let iou = FaceGeometry.iou(tracks[i].smoothedRect, detections[j].rect)
                if iou >= bestIoU { bestIoU = iou; bestJ = j }
            }
            if let j = bestJ {
                tracks[i].smoothedRect = FaceGeometry.smooth(previous: tracks[i].smoothedRect,
                                                             next: detections[j].rect)
                tracks[i].detectionConfidence = detections[j].conf
                tracks[i].lastSeenFrame = frameIndex
                unmatched.removeAll { $0 == j }
            }
        }

        // Remaining detections become new tracks.
        for j in unmatched {
            tracks.append(Track(
                id: "trk_" + UUID().uuidString.prefix(8).lowercased(),
                smoothedRect: detections[j].rect,
                lastSeenFrame: frameIndex,
                detectionConfidence: detections[j].conf
            ))
        }
    }

    private func prune() {
        tracks.removeAll { frameIndex - $0.lastSeenFrame > maxMissedFrames }
    }

    private func currentObservations() -> [FaceObservation] {
        // Only faces seen this frame are reported; rank by area (largest first).
        let visible = tracks.filter { $0.lastSeenFrame == frameIndex }
        let ranked = visible.sorted { ($0.smoothedRect.width * $0.smoothedRect.height) >
                                      ($1.smoothedRect.width * $1.smoothedRect.height) }
        return ranked.enumerated().map { rank, t in
            FaceObservation(trackId: t.id, rect: t.smoothedRect,
                            detectionConfidence: t.detectionConfidence, faceRank: rank)
        }
    }
}
