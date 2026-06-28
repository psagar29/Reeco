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

    // MARK: - AR overlay state

    /// Oriented preview image aspect (width ÷ height). `nil` for the simulated
    /// source (whose boxes are authored in screen space) → plain-stretch mapping.
    private(set) var previewImageAspect: CGFloat?
    /// Current scan stage while resolving an identity; `nil` when idle. Drives the
    /// hologram panel's scan timeline.
    private(set) var scanStage: ARScanStage?
    /// The track the active scan/result panel is anchored to. Survives brief
    /// detection dropouts so the panel doesn't flicker away mid-scan.
    private(set) var scanningTrackId: String?
    /// The resolved identity for the panel (mirrors `appModel.identityResult`).
    private(set) var scanResult: IdentityResolveResultDTO?
    private var stageTask: Task<Void, Never>?
    /// Bumped whenever a scan starts or the panel is dismissed, so a late identity
    /// resolution from a superseded/cancelled scan can't re-open or mis-anchor the panel.
    private var scanGeneration = 0

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
    // Lazy + observation-ignored: CameraView is re-initialized whenever RootView's
    // body re-evaluates, and `State(initialValue:)` eagerly builds (then discards)
    // a view model each time. Deferring the AVCaptureSession until it is actually
    // used (onAppear) keeps those throwaway instances cheap.
    @ObservationIgnored private lazy var session = CameraSession()
    private let tracker = FaceTracker()
    private let cropper = FaceCropper()
    private let imageCropper = ImageCropper()
    private let policy = RecognitionPolicy()
    private let mockClient: MockRecognitionClient
    private let backendClient: BackendRecognitionClient

    /// Explicitly locked identity target (set by a tap); nil = auto (center face).
    private(set) var targetTrackId: String?

    private var latestPixelBuffer: CVPixelBuffer?
    private var lastFrameReceivedAt: TimeInterval?
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

        // Let the command bar trigger "find info on him" from the live pixel
        // buffer this view model owns.
        appModel.identityCaptureHandler = { [weak self] transcript in
            await self?.resolveTargetIdentity(transcript)
        }

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
        simTask = nil
        stageTask?.cancel()
        stageTask = nil
        session.stop()
        appModel.identityCaptureHandler = nil
    }

    func flipCamera() {
        tracker.reset()
        session.flip()
    }

    private func startCamera() {
        simTask?.cancel()
        simTask = nil
        usingSimulatedSource = false
        lastFrameReceivedAt = nil
        statusLine = nil
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
        // Some devices can create a camera session but fail to deliver frames
        // (CoreDevice/Fig capture errors, stale permission daemon, continuity
        // camera weirdness). Never let that strand the UI on a black preview.
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(1400))
            if lastFrameReceivedAt == nil {
                statusLine = "Camera feed unavailable — showing demo lens."
                appModel.setStatus("Camera feed unavailable — showing demo lens.")
                startSimulated()
            }
        }
    }

    private func startSimulated() {
        guard simTask == nil else { return }
        session.stop()
        usingSimulatedSource = true
        previewImageAspect = nil
        latestPixelBuffer = nil
        // Live recognition needs real pixels; the simulated source has none, so
        // be explicit rather than silently showing no overlays in live mode.
        if appModel.demoMode == .live {
            appModel.setStatus("Live mode: Simulator has no camera — face matching is paused. Use a device, or switch to Mock CV.")
        }
        simTask = Task { @MainActor in
            while !Task.isCancelled {
                processSimulated()
                try? await Task.sleep(for: .milliseconds(250))
            }
        }
    }

    // MARK: - Frame processing (device)

    private func handle(frame: CameraFrame) {
        if usingSimulatedSource {
            simTask?.cancel()
            simTask = nil
            usingSimulatedSource = false
            statusLine = nil
            appModel.setStatus(nil)
        }
        lastFrameReceivedAt = nowSeconds()
        let now = nowSeconds()
        guard now - lastProcessTime >= minFrameInterval else { return }
        lastProcessTime = now
        latestPixelBuffer = frame.pixelBuffer

        // Oriented buffer dimensions drive the aspect-fill overlay mapping.
        let pbW = CVPixelBufferGetWidth(frame.pixelBuffer)
        let pbH = CVPixelBufferGetHeight(frame.pixelBuffer)
        if pbW > 0, pbH > 0 { previewImageAspect = CGFloat(pbW) / CGFloat(pbH) }

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

    // MARK: - Identity target ("find info on him")

    /// Explicitly lock a track as the identity target (e.g. from a tap). Pass
    /// nil to return to automatic (center-face) selection.
    func selectTarget(_ trackId: String?) {
        targetTrackId = trackId
    }

    /// Tap behavior: lock a face, or tap the already-locked face again to return
    /// to automatic (center-face) selection.
    func toggleTargetLock(_ trackId: String) {
        targetTrackId = (targetTrackId == trackId) ? nil : trackId
    }

    // MARK: - AR scan presentation (read/driven by the camera overlay)

    /// The track the AR overlay treats as the active target right now: the
    /// in-flight scan's track if still visible, otherwise the tap-locked or
    /// center-most face.
    var activeTargetTrackId: String? {
        // While a scan/result is active, stay pinned to that track even if the face
        // briefly drops out — never jump the active glow/anchor onto another person.
        // (When the pinned face is absent, `activeTargetObservation` is nil and the
        // panel falls back to a stable anchor instead of re-anchoring elsewhere.)
        if let id = scanningTrackId { return id }
        return chooseTargetObservation()?.trackId
    }

    /// The observation for `activeTargetTrackId`, if it is on screen.
    var activeTargetObservation: FaceObservation? {
        guard let id = activeTargetTrackId else { return nil }
        return observations.first { $0.trackId == id }
    }

    /// True while the hologram panel should be visible (scanning or a result).
    var isPanelVisible: Bool { scanStage != nil }

    /// Start an identity scan on the current target. The Scan button and the
    /// "find info on him" command both land here (the latter via the AppModel
    /// capture handler), so they share one visual path.
    func startIdentityScan() {
        // Debounce: ignore taps while a scan is already resolving (the panel shows
        // its progress); a fresh scan is allowed once a result has landed.
        guard !(scanStage != nil && scanResult == nil) else { return }
        Task { await appModel.runIdentityCommand("Find info on him") }
    }

    /// Re-run the scan (panel "Retry").
    func retryScan() { startIdentityScan() }

    /// Begin the visible scan sequence, anchored to `trackId`.
    func beginARScan(trackId: String) {
        scanGeneration &+= 1
        scanningTrackId = trackId
        scanResult = nil
        scanStage = .locked
        stageTask?.cancel()
        stageTask = Task { @MainActor [weak self] in
            await self?.advanceScanStages()
        }
    }

    /// Gentle, alive progression through the pre-result stages. Holds at
    /// `.verifying` until the backend lands; `finishARScan` flips to `.result`.
    private func advanceScanStages() async {
        let steps: [(stage: ARScanStage, ms: Int)] = [
            (.readingBadge, 500), (.searching, 650), (.verifying, 700)
        ]
        for step in steps {
            try? await Task.sleep(for: .milliseconds(step.ms))
            if Task.isCancelled { return }
            guard let current = scanStage, current != .result, scanResult == nil else { return }
            if step.stage > current { scanStage = step.stage }
        }
    }

    /// Land the backend result into the panel.
    func finishARScan(result: IdentityResolveResultDTO?) {
        stageTask?.cancel()
        scanResult = result
        scanStage = .result   // keep `scanningTrackId` so the panel stays anchored
    }

    /// Collapse and dismiss the hologram panel (swipe-down / close button).
    func dismissARPanel() {
        scanGeneration &+= 1   // supersede any in-flight resolve so it can't re-open the panel
        stageTask?.cancel()
        scanStage = nil
        scanningTrackId = nil
        scanResult = nil
        appModel.clearIdentity()
    }

    /// Pick the identity target: an explicitly selected track if it is still on
    /// screen, else the face nearest the screen center, tie-broken by largest
    /// area. `observations` use a normalized top-left (0...1) coordinate space.
    func chooseTargetObservation() -> FaceObservation? {
        guard !observations.isEmpty else { return nil }
        if let id = targetTrackId, let selected = observations.first(where: { $0.trackId == id }) {
            return selected
        }
        // Rank by an independent composite key so the comparison is a true total
        // order (a pairwise "within 0.04" tie-break is intransitive and would
        // make the winner depend on array order with 3+ near-center faces).
        // Bucket centeredness into 0.04 bands, then prefer the larger face.
        func key(_ o: FaceObservation) -> (Int, CGFloat) {
            (Int((distanceToCenter(o) / 0.04).rounded(.down)), -area(o))
        }
        return observations.min { a, b in
            let ka = key(a), kb = key(b)
            return ka.0 != kb.0 ? ka.0 < kb.0 : ka.1 < kb.1
        }
    }

    private func distanceToCenter(_ o: FaceObservation) -> CGFloat {
        let dx = o.center.x - 0.5
        let dy = o.center.y - 0.5
        return (dx * dx + dy * dy).squareRoot()
    }

    private func area(_ o: FaceObservation) -> CGFloat { o.rect.width * o.rect.height }

    /// A wider crop than the face box: widen around the face and extend downward
    /// to include the chest / lanyard / name-tag. Coordinates are top-left, so
    /// "down" is increasing y. Result is clamped to the unit square.
    private func contextRect(for face: FaceObservation) -> CGRect {
        let f = face.rect
        let width = min(1.0, f.width * 2.6)
        let x = max(0, f.midX - width / 2)
        let top = max(0, f.minY - f.height * 0.2)
        let bottom = min(1.0, f.maxY + f.height * 2.4)
        return CGRect(x: x, y: top, width: min(width, 1.0 - x), height: bottom - top)
    }

    /// Capture the locked target's two crops (tight face + wider badge) and run
    /// them through the backend identity lane. Invoked via the AppModel capture
    /// handler when the user says/types "find info on him". In `mockAll` (or with
    /// no pixel buffer) the crops are empty and the mock backend returns a demo
    /// identity, so the flow is always demoable.
    func resolveTargetIdentity(_ transcript: String) async {
        guard let target = chooseTargetObservation() else {
            // Nothing to anchor to — clear any stale panel from a previous scan so
            // it doesn't keep showing the old person while we report "no one here".
            if isPanelVisible { dismissARPanel() }
            appModel.setIdentityPhase("No one in frame — point the camera at someone.")
            await appModel.resolveIdentity(
                transcript: transcript, trackId: "no_target",
                faceImageBase64: "", contextImageBase64: ""
            )
            return
        }
        // Do NOT lock `targetTrackId` here: an auto-picked (center-face) target
        // must stay live so the next "find info on him" re-centers. Only an
        // explicit tap (selectTarget) should lock a track.
        beginARScan(trackId: target.trackId)
        let generation = scanGeneration
        statusLine = "Identifying…"

        var faceBase64 = ""
        var contextBase64 = ""
        if appModel.demoMode != .mockAll, let pb = latestPixelBuffer {
            appModel.setIdentityPhase("Reading the badge…")
            faceBase64 = (try? cropper.base64JPEG(from: pb, normalizedBox: target.rect)) ?? ""
            contextBase64 = (try? imageCropper.base64JPEG(
                from: pb,
                normalizedRect: contextRect(for: target),
                jpegQuality: 0.85
            )) ?? ""
        }

        await appModel.resolveIdentity(
            transcript: transcript,
            trackId: target.trackId,
            faceImageBase64: faceBase64,
            contextImageBase64: contextBase64
        )
        // Only land the result if this scan is still current — the user may have
        // dismissed it, or started another scan, while the backend was working.
        guard generation == scanGeneration else { statusLine = nil; return }
        finishARScan(result: appModel.identityResult)
        statusLine = nil
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
        // Drop a manual lock whose face has left the frame (back to auto-center).
        if let t = targetTrackId, !currentTrackIds.contains(t) { targetTrackId = nil }
    }

    private func nowSeconds() -> TimeInterval { Date().timeIntervalSince1970 }
}
