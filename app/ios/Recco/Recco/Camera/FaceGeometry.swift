import CoreGraphics
import Foundation

/// Pure, dependency-free geometry helpers for the camera pipeline.
///
/// Everything here is deliberately free of UIKit / Vision / AVFoundation so it
/// can be reasoned about and unit-tested in isolation (see `CameraSelfCheck`).
/// Vision reports faces as normalized rectangles in a **bottom-left** origin
/// coordinate space; SwiftUI draws in a **top-left** origin space. These helpers
/// bridge the two and implement the crop-size guards from
/// `docs/API_CONTRACTS.md` ("Camera recognition rules").
enum FaceGeometry {

    // MARK: - Coordinate conversion

    /// Convert a Vision bounding box (normalized, bottom-left origin) into a
    /// normalized **top-left** rect suitable for SwiftUI. Optionally mirrors on
    /// the x-axis for the front (selfie) camera, whose preview is mirrored.
    static func visionToNormalizedTopLeft(_ box: CGRect, mirrored: Bool) -> CGRect {
        let x = mirrored ? (1.0 - box.origin.x - box.width) : box.origin.x
        let y = 1.0 - box.origin.y - box.height   // flip bottom-left -> top-left
        return CGRect(x: x, y: y, width: box.width, height: box.height)
    }

    /// Scale a normalized (0...1, top-left) rect into a concrete view rect.
    static func rect(_ normalized: CGRect, in size: CGSize) -> CGRect {
        CGRect(
            x: normalized.origin.x * size.width,
            y: normalized.origin.y * size.height,
            width: normalized.width * size.width,
            height: normalized.height * size.height
        )
    }

    // MARK: - Smoothing (anti-flicker)

    /// Exponential moving average between the previous and incoming rect. A
    /// `factor` near 1 snaps to the new value; near 0 it is very smooth. Used so
    /// 2-3 faces in frame don't jitter. Returns `next` when there is no history.
    static func smooth(previous: CGRect?, next: CGRect, factor: CGFloat = 0.35) -> CGRect {
        guard let p = previous else { return next }
        let f = min(max(factor, 0), 1)
        return CGRect(
            x: p.origin.x + (next.origin.x - p.origin.x) * f,
            y: p.origin.y + (next.origin.y - p.origin.y) * f,
            width: p.width + (next.width - p.width) * f,
            height: p.height + (next.height - p.height) * f
        )
    }

    // MARK: - Track association

    /// Intersection-over-union of two rects (0...1). Used to associate a fresh
    /// detection with an existing track across frames.
    static func iou(_ a: CGRect, _ b: CGRect) -> CGFloat {
        let inter = a.intersection(b)
        if inter.isNull || inter.isEmpty { return 0 }
        let interArea = inter.width * inter.height
        let union = a.width * a.height + b.width * b.height - interArea
        return union > 0 ? interArea / union : 0
    }

    /// Distance between rect centers (in normalized units). Used to decide when a
    /// face "moved significantly" and recognition should be retried.
    static func centerDistance(_ a: CGRect, _ b: CGRect) -> CGFloat {
        let dx = a.midX - b.midX
        let dy = a.midY - b.midY
        return (dx * dx + dy * dy).squareRoot()
    }

    // MARK: - Crop rect + size guards (API_CONTRACTS "Camera recognition rules")

    /// Minimum acceptable crop edge in pixels. Crops smaller than this are
    /// rejected (face too far / too small to recognize reliably).
    static let minCropEdge: CGFloat = 96
    /// Preferred crop edge in pixels; we upscale toward this for the backend.
    static let preferredCropEdge: CGFloat = 160

    /// Expand a normalized face box by `padding` (fraction of the box) and clamp
    /// to the unit square, then map onto a pixel-sized image. Returns the pixel
    /// crop rect to extract from the source frame.
    static func cropRect(forNormalizedBox box: CGRect,
                         imageSize: CGSize,
                         padding: CGFloat = 0.25) -> CGRect {
        let padX = box.width * padding
        let padY = box.height * padding
        var padded = CGRect(
            x: box.origin.x - padX,
            y: box.origin.y - padY,
            width: box.width + padX * 2,
            height: box.height + padY * 2
        )
        padded = padded.intersection(CGRect(x: 0, y: 0, width: 1, height: 1))
        return CGRect(
            x: padded.origin.x * imageSize.width,
            y: padded.origin.y * imageSize.height,
            width: padded.width * imageSize.width,
            height: padded.height * imageSize.height
        )
    }

    /// True when a pixel crop is large enough to send (>= 96x96).
    static func meetsMinimumCropSize(_ size: CGSize) -> Bool {
        size.width >= minCropEdge && size.height >= minCropEdge
    }

    /// True when a crop already meets the preferred size (>= 160x160).
    static func meetsPreferredCropSize(_ size: CGSize) -> Bool {
        size.width >= preferredCropEdge && size.height >= preferredCropEdge
    }
}
