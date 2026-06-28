import CoreGraphics
import Foundation

/// Lightweight runtime self-check for the camera lane's contract-critical pure
/// logic. There is no XCTest target in the project, so these invariants
/// (coordinate conversion, crop-size guards, throttle/cache/retry timing) are
/// verified here and logged at launch in DEBUG builds. They are the same
/// invariants exercised by the standalone `swiftc` harness used off-device.
enum CameraSelfCheck {

    private static var didRun = false

    /// Run once per process (DEBUG only). Logs PASS/FAIL per invariant.
    static func runOnce() {
        guard !didRun else { return }
        didRun = true
        #if DEBUG
        var results: [(String, Bool)] = []
        func check(_ name: String, _ pass: Bool) { results.append((name, pass)) }

        // 1. Vision bottom-left -> SwiftUI top-left (y flips).
        let conv = FaceGeometry.visionToNormalizedTopLeft(CGRect(x: 0, y: 0, width: 0.2, height: 0.2), mirrored: false)
        check("coord: y-flip", approx(conv.origin.y, 0.8) && approx(conv.origin.x, 0.0))

        // 2. Front-camera mirroring flips x.
        let mir = FaceGeometry.visionToNormalizedTopLeft(CGRect(x: 0, y: 0, width: 0.2, height: 0.2), mirrored: true)
        check("coord: mirror-x", approx(mir.origin.x, 0.8))

        // 3. Normalized -> view rect scaling.
        let scaled = FaceGeometry.rect(CGRect(x: 0, y: 0, width: 0.5, height: 0.5), in: CGSize(width: 100, height: 200))
        check("coord: scale", approx(scaled.width, 50) && approx(scaled.height, 100))

        // 4. Crop-size guards (96 floor, 160 preferred).
        check("crop: <96 rejected", !FaceGeometry.meetsMinimumCropSize(CGSize(width: 95, height: 95)))
        check("crop: 96 accepted", FaceGeometry.meetsMinimumCropSize(CGSize(width: 96, height: 96)))
        check("crop: 160 preferred", FaceGeometry.meetsPreferredCropSize(CGSize(width: 160, height: 160)))

        // 5. Crop rect padding + clamp.
        let crop = FaceGeometry.cropRect(forNormalizedBox: CGRect(x: 0.4, y: 0.4, width: 0.2, height: 0.2),
                                         imageSize: CGSize(width: 1000, height: 1000), padding: 0.25)
        check("crop: padded size", approx(crop.width, 300) && approx(crop.height, 300))

        // 6. Throttle / cache / retry (deterministic clock).
        let p = RecognitionPolicy(minRequestInterval: 1.0, cacheTTL: 10.0, moveThreshold: 0.12)
        let c = CGPoint(x: 0.5, y: 0.5)
        let firstSend = p.shouldRequest(trackId: "a", boxCenter: c, now: 100)
        p.record(trackId: "a", personId: "id", score: 0.5, isStrongMatch: true, now: 100)
        let rateLimited = p.shouldRequest(trackId: "a", boxCenter: c, now: 100.5)   // < 1.0s
        let cacheHold = p.shouldRequest(trackId: "a", boxCenter: c, now: 101.0)      // cached, no move
        let cacheExpired = p.shouldRequest(trackId: "a", boxCenter: c, now: 111.5)   // > 10s
        check("policy: first send", firstSend)
        check("policy: rate-limited <1.0s", !rateLimited)
        check("policy: cache holds <10s", !cacheHold)
        check("policy: cache expires >10s", cacheExpired)

        let p2 = RecognitionPolicy(minRequestInterval: 1.0, cacheTTL: 10.0, moveThreshold: 0.12)
        _ = p2.shouldRequest(trackId: "b", boxCenter: c, now: 0)
        p2.record(trackId: "b", personId: "id", score: 0.5, isStrongMatch: true, now: 0)
        let movedRetry = p2.shouldRequest(trackId: "b", boxCenter: CGPoint(x: 0.8, y: 0.8), now: 2.0)
        check("policy: retry on move", movedRetry)

        let passed = results.filter { $0.1 }.count
        print("🧪 CameraSelfCheck: \(passed)/\(results.count) passed")
        for (name, ok) in results { print("   \(ok ? "✅" : "❌") \(name)") }
        #endif
    }

    private static func approx(_ a: CGFloat, _ b: CGFloat, _ eps: CGFloat = 0.0001) -> Bool {
        abs(a - b) < eps
    }
}
