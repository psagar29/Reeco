import SwiftUI
import CoreGraphics

/// Drives the pipeline when no real camera exists (the iOS Simulator) so the
/// whole overlay / filter / tap / scan / debug experience is fully demoable
/// without a device. Emits a deterministic set of synthetic face tracks at fixed
/// positions; the view model maps them to roster people via the mock client.
///
/// This is the **UI verification path** described in the Person C agent prompt
/// (§9.2): Vision can't detect anything in the Simulator, so we inject stable
/// tracks instead, while the real `FaceTracker` runs on device.
struct SimulatedFaceSource {

    /// Fixed normalized (top-left) face boxes — three faces spread across frame,
    /// echoing the layout of Person D's `CameraPlaceholderView`.
    static let boxes: [CGRect] = [
        CGRect(x: 0.14, y: 0.26, width: 0.26, height: 0.20),
        CGRect(x: 0.58, y: 0.30, width: 0.26, height: 0.20),
        CGRect(x: 0.36, y: 0.52, width: 0.26, height: 0.20)
    ]

    /// Stable synthetic observations, ranked largest-first (all equal here, so
    /// order = declaration order). `count` lets the debug HUD vary face count.
    static func observations(count: Int = 3) -> [FaceObservation] {
        let n = max(0, min(count, boxes.count))
        return (0..<n).map { i in
            FaceObservation(
                trackId: "sim_\(i)",
                rect: boxes[i],
                detectionConfidence: 0.95,
                faceRank: i
            )
        }
    }
}
