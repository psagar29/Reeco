import SwiftUI
import UIKit

/// The camera-first hero screen. Replaces `CameraPlaceholderView` in `RootView`.
/// Renders the live preview (or the simulated backdrop), draws face boxes, and
/// anchors a reusable `FaceOverlayCard` to every **matched** face. Tapping a
/// card opens Person D's profile sheet via `appModel.selectPerson`.
struct CameraView: View {
    @Environment(AppModel.self) private var appModel
    @State private var vm: CameraViewModel

    init(appModel: AppModel) {
        _vm = State(initialValue: CameraViewModel(appModel: appModel))
    }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                // 1. Backdrop: live camera, or the simulated stage.
                if let session = vm.previewSession {
                    CameraPreviewView(session: session).ignoresSafeArea()
                } else {
                    SimulatedBackdrop().ignoresSafeArea()
                }

                // 2. Face boxes + matched overlay cards.
                ForEach(vm.observations) { obs in
                    let frame = FaceGeometry.rect(obs.rect, in: geo.size)
                    let person = vm.matchedPerson(for: obs.trackId)

                    // Box / scanning ring (cards shown only for matches).
                    FaceBoxView(
                        frame: frame,
                        matched: person != nil,
                        showOutline: vm.showAllBoxes || vm.debugEnabled || person != nil
                    )

                    if let person {
                        FaceOverlayCard(
                            person: person,
                            dimmed: appModel.state.isDimmed(person.id),
                            highlighted: appModel.state.highlightedPersonId == person.id
                        )
                        .position(cardPosition(for: frame, in: geo.size))
                        .onTapGesture { appModel.selectPerson(person.id) }
                        .transition(.opacity.combined(with: .scale))
                    }

                    if vm.debugEnabled, let r = vm.result(for: obs.trackId) {
                        DebugTrackTag(trackId: obs.trackId, result: r)
                            .position(x: frame.midX, y: max(frame.minY - 10, 12))
                    }
                }

                // 3. Permission empty-state.
                if vm.authState == .denied || vm.authState == .restricted {
                    CameraPermissionView()
                }

                // 4. Floating camera controls (trailing edge, clear of the
                //    bottom control strip Person D draws over us).
                cameraControls
            }
            .contentShape(Rectangle())
            .onLongPressGesture(minimumDuration: 0.8) {
                withAnimation { vm.debugEnabled.toggle() }
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: vm.observations.map(\.trackId))
        .overlay(alignment: .top) {
            if vm.debugEnabled { CameraDebugOverlay(vm: vm).padding(.top, 64) }
        }
        .onAppear {
            CameraSelfCheck.runOnce()
            vm.onAppear()
        }
        .onDisappear { vm.onDisappear() }
    }

    // MARK: - Controls

    private var cameraControls: some View {
        VStack(spacing: 14) {
            Spacer()
            CircleButton(system: "viewfinder.circle.fill", label: "Scan") { vm.scan() }
            if !vm.usingSimulatedSource {
                CircleButton(system: "arrow.triangle.2.circlepath.camera", label: "Flip") { vm.flipCamera() }
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
        .padding(.trailing, 14)
        .padding(.bottom, 120)   // keep clear of the control strip
    }

    /// Place the card just below the face box, clamped on-screen.
    private func cardPosition(for box: CGRect, in size: CGSize) -> CGPoint {
        let cardHalfWidth: CGFloat = 95
        let cardHalfHeight: CGFloat = 72   // card includes the LinkedIn pill row
        let x = min(max(box.midX, cardHalfWidth + 8), size.width - cardHalfWidth - 8)
        var y = box.maxY + cardHalfHeight + 10
        if y + cardHalfHeight > size.height - 100 {   // would hit the control strip
            y = box.minY - cardHalfHeight - 10        // flip above the face
        }
        return CGPoint(x: x, y: max(y, cardHalfHeight + 8))
    }
}

/// Face rectangle + scanning ring. Bright for matches, faint while scanning.
private struct FaceBoxView: View {
    let frame: CGRect
    let matched: Bool
    let showOutline: Bool

    var body: some View {
        if showOutline {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(matched ? Theme.accent : Color.white.opacity(0.35),
                              lineWidth: matched ? 2.5 : 1.5)
                .frame(width: frame.width, height: frame.height)
                .position(x: frame.midX, y: frame.midY)
                .shadow(color: matched ? Theme.accent.opacity(0.5) : .clear, radius: 8)
                .animation(.easeInOut(duration: 0.25), value: matched)
        }
    }
}

/// Small round action button used for Scan / Flip.
private struct CircleButton: View {
    let system: String
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Image(systemName: system).font(.title2.weight(.semibold))
                Text(label).font(.caption2.weight(.semibold))
            }
            .foregroundStyle(Theme.textPrimary)
            .frame(width: 60, height: 60)
            .glassCard(corner: 18)
        }
    }
}

/// Faux camera feed for the Simulator / no-device path.
private struct SimulatedBackdrop: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(red: 0.08, green: 0.10, blue: 0.16),
                         Color(red: 0.03, green: 0.04, blue: 0.07)],
                startPoint: .top, endPoint: .bottom
            )
            GeometryReader { geo in
                Path { path in
                    let step: CGFloat = 44
                    var x: CGFloat = 0
                    while x < geo.size.width { path.move(to: CGPoint(x: x, y: 0)); path.addLine(to: CGPoint(x: x, y: geo.size.height)); x += step }
                    var y: CGFloat = 0
                    while y < geo.size.height { path.move(to: CGPoint(x: 0, y: y)); path.addLine(to: CGPoint(x: geo.size.width, y: y)); y += step }
                }
                .stroke(Color.white.opacity(0.03), lineWidth: 1)
            }
            VStack(spacing: 8) {
                Image(systemName: "viewfinder")
                    .font(.system(size: 40, weight: .thin))
                    .foregroundStyle(Theme.textTertiary)
                Text("Simulated camera")
                    .font(.subheadline).foregroundStyle(Theme.textSecondary)
                Text("No device camera — running the simulated face source.")
                    .font(.caption2).foregroundStyle(Theme.textTertiary)
                    .multilineTextAlignment(.center)
            }
            .offset(y: -80)
        }
    }
}

/// Shown when camera permission is unavailable.
private struct CameraPermissionView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "camera.fill.badge.ellipsis")
                .font(.system(size: 40)).foregroundStyle(Theme.textSecondary)
            Text("Camera access needed")
                .font(.headline).foregroundStyle(Theme.textPrimary)
            Text("Enable camera access in Settings to recognize people.")
                .font(.caption).foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
            if let url = URL(string: UIApplication.openSettingsURLString) {
                Link("Open Settings", destination: url)
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 16).padding(.vertical, 10)
                    .glassCard(corner: 12)
            }
        }
        .padding(28)
        .glassCard(corner: 20)
        .padding(40)
    }
}

/// Tiny per-track debug tag (trackId + score) drawn above the box.
private struct DebugTrackTag: View {
    let trackId: String
    let result: FaceMatchResultDTO

    var body: some View {
        Text("\(trackId) · \(result.status.rawValue)\(scoreText)")
            .font(.system(size: 9, design: .monospaced))
            .foregroundStyle(.white)
            .padding(.horizontal, 6).padding(.vertical, 3)
            .background(Color.black.opacity(0.6), in: Capsule())
    }

    private var scoreText: String {
        guard let s = result.score else { return "" }
        return String(format: " %.2f", s)
    }
}
