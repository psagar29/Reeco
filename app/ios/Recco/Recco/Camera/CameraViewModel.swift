import SwiftUI
import AVFoundation
import Observation
import CoreVideo

/// Orchestrates the camera lane: capture -> Vision tracking -> throttle/cache
/// policy -> face crop -> recognition client -> shared `AppModel`. Owns all the
/// pipeline pieces and publishes the per-frame overlays the view renders.
///
/// Everything runs on the main actor (frames are throttled to keep it light);
/// the heavy detection/crop primitives are pure enough that this stays smooth
/// for a 2-3 face demo. On the Simulator it drives a deterministic simulated
/// source so the full overlay/filter/tap/scan/debug experience is demoable with
/// no device.
@MainActor
@Observable
final class CameraViewModel {

    // MARK: - Published (rendered) state
    private(set) var observations: [FaceObservation] = []
    /// trackId -> latest recognition result (drives which faces show a card).
    private(set) var matches: [String: FaceMatchResultDTO] = [:]
    private(set) var authState: CameraAuthState = .unknown
    private(set) var usingSimulatedSource = false
    var statusLine: String?

    // MARK: - Debug state
    var debugEnabled = false
    var showAllBoxes = false
    private(set) var requestCount = 0
    private(set) var lastLatencyMs: Double?
    var simulatedFaceCount = 3
    var forceMatchPersonId: String? {
        didSet { mockClient.forcedPersonId = forceMatchPersonId }
    }

    // MARK: - Dependencies
    private let appModel: AppModel
    private let session = CameraSession()
    private let tracker = FaceTracker()
    private let cropper = FaceCropper()
    private let policy = RecognitionPolicy()
    private let mockClient: MockRecognitionClient
    private let backendClient: BackendRecognitionClient

    private var latestPixelBuffer: CVPixelBuffer?
    private var lastProcessTime: TimeInterval = 0
    private let minFrameInterval: TimeInterval = 0.08   // ~12 fps detection
    private var simTask: Task<Void, Never>?

    init(appModel: AppModel) {
        self.appModel = appModel
        self.mockClient = MockRecognitionClient(people: appModel.people)
        self.backendClient = BackendRecognitionClient(appModel: appModel)
    }

    private var activeClient: RecognitionClient {
        switch appModel.demoMode {
        case .mockAll: return mockClient
        case .mockCV, .live: return backendClient
        }
    }

    // MARK: - Lifecycle

    func onAppear() {
        mockClient.people = appModel.people    // roster may have loaded after init
        authState = session.authState

        #if targetEnvironment(simulator)
        startSimulated()
        #else
        switch authState {
        case .authorized:
            startCamera()
        case .unknown:
            Task {
                let granted = await session.requestAccess()
                authState = granted ? .authorized : .denied
                if granted { startCamera() }
            }
        case .denied, .restricted:
            statusLine = "Camera access is off. Enable it in Settings."
        }
        #endif
    }

    func onDisappear() {
        simTask?.cancel()
        session.stop()
    }

    func flipCamera() {
        tracker.reset()
        session.flip()
    }

    private func startCamera() {
        session.onFrame = { [weak self] frame in
            // Delivered on the capture queue; hop to the main actor.
            Task { @MainActor in self?.handle(frame: frame) }
        }
        session.start(position: .back)
        // Belt-and-braces: if no device materialized, fall back to simulated.
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(600))
            if !session.isCameraAvailable { startSimulated() }
        }
    }

    private func startSimulated() {
        guard simTask == nil else { return }
        usingSimulatedSource = true
        simTask = Task { @MainActor in
            while !Task.isCancelled {
                processSimulated()
                try? await Task.sleep(for: .milliseconds(250))
            }
        }
    }

    // MARK: - Frame processing (device)

    private func handle(frame: CameraFrame) {
        let now = nowSeconds()
        guard now - lastProcessTime >= minFrameInterval else { return }
        lastProcessTime = now
        latestPixelBuffer = frame.pixelBuffer

        let obs = tracker.process(pixelBuffer: frame.pixelBuffer,
                                  orientation: frame.orientation,
                                  mirrored: frame.mirrored)
        observations = obs
        pruneMatches(currentTrackIds: Set(obs.map(\.trackId)))

        for o in obs where policy.shouldRequest(trackId: o.trackId, boxCenter: o.center, now: now) {
            requestRecognition(for: o, pixelBuffer: frame.pixelBuffer)
        }
    }

    // MARK: - Frame processing (simulated / Simulator)

    private func processSimulated() {
        let now = nowSeconds()
        let obs = SimulatedFaceSource.observations(count: simulatedFaceCount)
        observations = obs
        pruneMatches(currentTrackIds: Set(obs.map(\.trackId)))
        for o in obs where policy.shouldRequest(trackId: o.trackId, boxCenter: o.center, now: now) {
            requestRecognition(for: o, pixelBuffer: nil)   // no pixels -> mock path
        }
    }

    // MARK: - Recognition

    /// Build a request for one face and fire it (non-blocking). Crops real
    /// pixels only when the backend actually needs them.
    private func requestRecognition(for obs: FaceObservation, pixelBuffer: CVPixelBuffer?) {
        var base64 = ""
        if appModel.demoMode != .mockAll, let pb = pixelBuffer {
            do {
                base64 = try cropper.base64JPEG(from: pb, normalizedBox: obs.rect)
            } catch {
                return   // too small / encode failed -> don't send this round
            }
        }
        fire(RecognitionRequest(trackId: obs.trackId, imageBase64: base64, faceRank: obs.faceRank))
    }

    private func fire(_ request: RecognitionRequest) {
        requestCount += 1
        let client = activeClient
        Task { @MainActor in
            do {
                let result = try await client.recognize(request)
                matches[request.trackId] = result
                lastLatencyMs = result.latencyMs
                policy.record(trackId: request.trackId,
                              personId: result.personId,
                              score: result.score,
                              isStrongMatch: result.status == .matched,
                              now: nowSeconds())
                if result.shouldShowOverlay { appModel.applyMatch(result) }
            } catch {
                statusLine = "Recognition error: \(error.localizedDescription)"
            }
        }
    }

    /// Stage parachute: recognize the single largest face on demand, ignoring
    /// the throttle/cache. Works even if live tracking is flaky.
    func scan() {
        guard let primary = observations.first else {
            statusLine = "No face to scan"
            return
        }
        requestRecognition(for: primary, pixelBuffer: latestPixelBuffer)
    }

    // MARK: - Overlay helpers (read by the view)

    /// The person to show a card for on this track, or nil (unknown/scanning).
    func matchedPerson(for trackId: String) -> PersonDTO? {
        guard let m = matches[trackId], m.shouldShowOverlay, let id = m.personId else { return nil }
        return appModel.peopleById[id]
    }

    func result(for trackId: String) -> FaceMatchResultDTO? { matches[trackId] }

    /// The live preview layer's session (nil while simulated).
    var previewSession: AVCaptureSession? { usingSimulatedSource ? nil : session.session }

    // MARK: - Plumbing

    private func pruneMatches(currentTrackIds: Set<String>) {
        for id in matches.keys where !currentTrackIds.contains(id) {
            matches[id] = nil
            policy.forget(trackId: id)
        }
    }

    private func nowSeconds() -> TimeInterval { Date().timeIntervalSince1970 }
}
