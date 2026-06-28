import Foundation
import CoreImage
import UIKit
import CoreGraphics
import CoreVideo

/// Extracts a face crop from a camera frame and encodes it for the backend,
/// enforcing the frozen rules in `docs/API_CONTRACTS.md`:
///   - reject crops smaller than 96x96,
///   - upscale toward >= 160x160,
///   - JPEG quality ~= 0.75.
final class FaceCropper {

    private let context = CIContext(options: [.useSoftwareRenderer: false])
    private let jpegQuality: CGFloat = 0.75

    enum CropError: Error { case tooSmall, encodeFailed }

    /// Crop the face described by `normalizedBox` (top-left, 0...1) out of
    /// `pixelBuffer`, returning a base64 JPEG ready for `vision:matchFace`.
    /// Throws `.tooSmall` if the source crop would be < 96x96.
    func base64JPEG(from pixelBuffer: CVPixelBuffer,
                    normalizedBox: CGRect,
                    padding: CGFloat = 0.25) throws -> String {
        let imageWidth = CGFloat(CVPixelBufferGetWidth(pixelBuffer))
        let imageHeight = CGFloat(CVPixelBufferGetHeight(pixelBuffer))
        let imageSize = CGSize(width: imageWidth, height: imageHeight)

        let cropRect = FaceGeometry.cropRect(forNormalizedBox: normalizedBox,
                                             imageSize: imageSize,
                                             padding: padding)

        guard FaceGeometry.meetsMinimumCropSize(cropRect.size) else {
            throw CropError.tooSmall
        }

        // CoreImage uses a bottom-left origin; flip the top-left crop rect.
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        let flippedY = imageHeight - cropRect.origin.y - cropRect.height
        let ciCrop = CGRect(x: cropRect.origin.x, y: flippedY,
                            width: cropRect.width, height: cropRect.height)
        let cropped = ciImage.cropped(to: ciCrop)

        // Upscale toward the preferred edge if the crop is small.
        let targetScale = max(1.0, FaceGeometry.preferredCropEdge / min(cropRect.width, cropRect.height))
        let scaled = cropped.transformed(by: CGAffineTransform(scaleX: targetScale, y: targetScale))

        guard let cg = context.createCGImage(scaled, from: scaled.extent) else {
            throw CropError.encodeFailed
        }
        let uiImage = UIImage(cgImage: cg)
        guard let data = uiImage.jpegData(compressionQuality: jpegQuality) else {
            throw CropError.encodeFailed
        }
        return data.base64EncodedString()
    }
}
