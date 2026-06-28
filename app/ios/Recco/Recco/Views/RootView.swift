import SwiftUI

/// App shell. Camera is the hero screen; a control strip floats at the bottom
/// with chips, the command bar, and the transcript ribbon. The Brain graph is a
/// secondary full-screen surface. Profiles and drafts present as sheets.
struct RootView: View {
    @Environment(AppModel.self) private var appModel
    @State private var showBrain = false
    @State private var showDemoPicker = false

    var body: some View {
        @Bindable var model = appModel

        ZStack {
            // Hero: Person C's real AVFoundation + Vision camera. Falls back to a
            // simulated face source automatically on the Simulator (no device).
            CameraView(appModel: appModel)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                TopBar(showBrain: $showBrain, showDemoPicker: $showDemoPicker)
                Spacer()
                ControlStripView()
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
        }
        .background(Theme.bg)
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
    }
}

/// Top bar: brand, demo-mode badge, Brain button.
private struct TopBar: View {
    @Environment(AppModel.self) private var appModel
    @Binding var showBrain: Bool
    @Binding var showDemoPicker: Bool

    var body: some View {
        HStack(spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "brain.head.profile")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Theme.accent)
                Text("Recco")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(Theme.textPrimary)
            }

            Spacer()

            Button { showDemoPicker = true } label: {
                HStack(spacing: 6) {
                    Image(systemName: appModel.demoMode.systemImage)
                    Text(appModel.demoMode.title)
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.textSecondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .glassCard(corner: 12)
            }

            Button { showBrain = true } label: {
                HStack(spacing: 6) {
                    Image(systemName: "circle.hexagongrid.fill")
                    Text("Brain")
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.textPrimary)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Theme.accentSoft, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Theme.accent.opacity(0.5), lineWidth: 1))
            }
        }
        .padding(.top, 8)
    }
}
