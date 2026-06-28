import Foundation
import AVFoundation
import CoreGraphics
import CoreMedia
import CoreVideo

/// Camera authorization state surfaced to the UI.
enum CameraAuthState: Equatable {
    case unknown, authorized, denied, restricted
}

/// One delivered camera frame plus the metadata the pipeline needs.
struct CameraFrame {
    let pixelBuffer: CVPixelBuffer
    let orientation: CGImagePropertyOrientation
    /// True for the front camera (preview is mirrored).
    let mirrored: Bool
}

/// Thin wrapper over `AVCaptureSession`. Owns permission, the input device
/// (front/back), an `AVCaptureVideoDataOutput` for frames, and the preview
/// layer. On the Simulator (no capture device) it reports `isCameraAvailable ==
/// false` so the view falls back to the simulated source — never a black screen.
final class CameraSession: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {

    /// Set true once at least one usable capture device exists.
    private(set) var isCameraAvailable = false
    /// The current camera position.
    private(set) var position: AVCaptureDevice.Position = .back

    /// Called on the capture queue for every frame. Hop to the main actor in the
    /// consumer if you touch UI state.
    var onFrame: ((CameraFrame) -> Void)?

    let session = AVCaptureSession()
    private let videoOutput = AVCaptureVideoDataOutput()
    private let queue = DispatchQueue(label: "recco.camera.session")

    // MARK: - Authorization

    var authState: CameraAuthState {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: return .authorized
        case .denied: return .denied
        case .restricted: return .restricted
        case .notDetermined: return .unknown
        @unknown default: return .unknown
        }
    }

    func requestAccess() async -> Bool {
        await AVCaptureDevice.requestAccess(for: .video)
    }

    // MARK: - Lifecycle

    /// Configure inputs/outputs and start running. Safe to call after access is
    /// granted. No-ops (leaving `isCameraAvailable == false`) on the Simulator.
    func start(position: AVCaptureDevice.Position = .back) {
        queue.async { [weak self] in
            guard let self else { return }
            self.configure(position: position)
            if self.isCameraAvailable, !self.session.isRunning {
                self.session.startRunning()
            }
        }
    }

    func stop() {
        queue.async { [weak self] in
            guard let self, self.session.isRunning else { return }
            self.session.stopRunning()
        }
    }

    /// Flip between front and back cameras.
    func flip() {
        let next: AVCaptureDevice.Position = (position == .back) ? .front : .back
        queue.async { [weak self] in
            guard let self else { return }
            self.session.stopRunning()
            self.configure(position: next)
            if self.isCameraAvailable { self.session.startRunning() }
        }
    }

    // MARK: - Configuration

    private func configure(position: AVCaptureDevice.Position) {
        session.beginConfiguration()
        defer { session.commitConfiguration() }

        session.sessionPreset = .high
        session.inputs.forEach { session.removeInput($0) }

        guard let device = Self.device(for: position),
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input) else {
            isCameraAvailable = false
            return
        }
        session.addInput(input)
        self.position = position
        isCameraAvailable = true

        if !session.outputs.contains(videoOutput) {
            videoOutput.alwaysDiscardsLateVideoFrames = true
            videoOutput.videoSettings = [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
            ]
            videoOutput.setSampleBufferDelegate(self, queue: queue)
            if session.canAddOutput(videoOutput) { session.addOutput(videoOutput) }
        }

        if let connection = videoOutput.connection(with: .video) {
            // Upright portrait buffer (iOS 17 rotation API), no data-output
            // mirroring — Vision sees the true image; the tracker mirrors boxes.
            if connection.isVideoRotationAngleSupported(90) {
                connection.videoRotationAngle = 90
            }
            if connection.isVideoMirroringSupported {
                connection.automaticallyAdjustsVideoMirroring = false
                connection.isVideoMirrored = false
            }
        }
    }

    private static func device(for position: AVCaptureDevice.Position) -> AVCaptureDevice? {
        let discovery = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera],
            mediaType: .video,
            position: position
        )
        return discovery.devices.first ?? AVCaptureDevice.default(for: .video)
    }

    // MARK: - Frame delegate

    func captureOutput(_ output: AVCaptureOutput,
                       didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let frame = CameraFrame(
            pixelBuffer: pixelBuffer,
            orientation: .up,                 // buffer is rotated upright above
            mirrored: position == .front
        )
        onFrame?(frame)
    }
}
