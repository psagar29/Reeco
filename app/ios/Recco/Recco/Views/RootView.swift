import SwiftUI

/// App shell. The camera is the whole surface — a clean AR lens. The only chrome
/// is a compact top bar and a single floating command dock at the bottom.
///
/// The dock's real on-screen height is measured (its top edge in global space)
/// and handed to `CameraView`, which uses it to reserve the bottom band so the
/// scan/flip controls, face name tags, and the hologram panel never hide behind
/// the dock — no hardcoded inset. Profiles, the Brain graph, the demo picker and
/// the identity detail still present as sheets.
struct RootView: View {
    @Environment(AppModel.self) private var appModel
    @State private var showBrain = false
    @State private var showDemoPicker = false
    /// The dock's top edge in global (full-screen) coordinates; fed to CameraView
    /// so it can keep AR content above the dock. 0 until first measured.
    @State private var dockTopGlobalY: CGFloat = 0

    var body: some View {
        ZStack {
            // Hero: the full-bleed AR camera. It ignores the safe area internally,
            // so its coordinate space matches the global frame we measure below.
            CameraView(appModel: appModel, dockTopGlobalY: dockTopGlobalY)
                .ignoresSafeArea()

            // Chrome — stays inside the safe area.
            VStack(spacing: 0) {
                TopBar(showBrain: $showBrain, showDemoPicker: $showDemoPicker)
                Spacer(minLength: 0)
                CommandDockView()
                    .background(
                        GeometryReader { proxy in
                            Color.clear.preference(
                                key: DockTopKey.self,
                                value: proxy.frame(in: .global).minY
                            )
                        }
                    )
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 6)

            // First-launch mission setup, over the blurred live app.
            if !appModel.hasCompletedMissionSetup {
                MissionSetupView()
                    .environment(appModel)
                    .transition(.opacity)
                    .zIndex(10)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: appModel.hasCompletedMissionSetup)
        .background(Theme.bg)
        .onPreferenceChange(DockTopKey.self) { top in
            if top.isFinite, top > 1 { dockTopGlobalY = top }
        }
        // Profile sheet — also the exact sheet Person C opens from an overlay tap.
        .sheet(item: Binding(
            get: { appModel.selectedPerson },
            set: { appModel.selectPerson($0?.id) }
        )) { person in
            ProfileSheetView(person: person)
                .environment(appModel)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
                .presentationBackground(.ultraThinMaterial)
        }
        // Brain graph.
        .fullScreenCover(isPresented: $showBrain) {
            BrainView(isPresented: $showBrain)
                .environment(appModel)
        }
        // Demo mode picker.
        .sheet(isPresented: $showDemoPicker) {
            DemoModePicker()
                .environment(appModel)
                .presentationDetents([.height(340)])
                .presentationDragIndicator(.visible)
                .presentationBackground(.ultraThinMaterial)
        }
        // "Find info on him" — full details. The in-camera hologram panel is the
        // primary result surface; this sheet is opt-in via the panel's "Details"
        // button (sets `appModel.showIdentityDetail`).
        .sheet(isPresented: Binding(
            get: { appModel.showIdentityDetail && appModel.identityResult != nil },
            set: { presented in if !presented { appModel.showIdentityDetail = false } }
        )) {
            if let result = appModel.identityResult {
                IdentityResultSheet(result: result)
                    .environment(appModel)
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
                    .presentationBackground(.ultraThinMaterial)
            }
        }
    }
}

/// Carries the command dock's top edge (global Y) up to `RootView`.
private struct DockTopKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

/// Top bar: brand, demo-mode badge, Brain button. Built to stay on one compact
/// line — fixed glyph sizes, `lineLimit(1)`, `minimumScaleFactor`, and icon-only
/// secondary controls at accessibility text sizes — so large Dynamic Type can
/// never wrap or split it across the AR surface.
private struct TopBar: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.dynamicTypeSize) private var typeSize
    @Binding var showBrain: Bool
    @Binding var showDemoPicker: Bool

    /// At accessibility sizes, collapse the secondary controls to icons only.
    private var compact: Bool { typeSize.isAccessibilitySize }

    var body: some View {
        HStack(spacing: 10) {
            // Brand — never wraps; scales down a touch before truncating.
            HStack(spacing: 6) {
                Image(systemName: "brain.head.profile")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Theme.accent)
                Text("Recco")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .fixedSize(horizontal: true, vertical: false)
            }
            .layoutPriority(1)

            Spacer(minLength: 8)

            // Demo-mode badge.
            Button { showDemoPicker = true } label: {
                HStack(spacing: 5) {
                    Image(systemName: appModel.demoMode.systemImage)
                    if !compact {
                        Text(appModel.demoMode.title)
                            .lineLimit(1)
                            .fixedSize()
                    }
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.textSecondary)
                .padding(.horizontal, compact ? 10 : 12)
                .padding(.vertical, 8)
                .hologramSurface(corner: 11, glow: false)
            }
            .accessibilityLabel("Demo mode: \(appModel.demoMode.title)")

            // Brain button — icon-only when text is large.
            Button { showBrain = true } label: {
                HStack(spacing: 5) {
                    Image(systemName: "circle.hexagongrid.fill")
                    if !compact {
                        Text("Brain")
                            .lineLimit(1)
                            .fixedSize()
                    }
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.textPrimary)
                .padding(.horizontal, compact ? 10 : 14)
                .padding(.vertical, 8)
                .background(Theme.accentSoft, in: Capsule())
                .overlay(Capsule().strokeBorder(Theme.accent.opacity(0.5), lineWidth: 1))
            }
            .accessibilityLabel("Open Brain graph")
        }
        .padding(.top, 8)
    }
}
