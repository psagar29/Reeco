import SwiftUI

/// Debug HUD (toggled by a long-press on the camera). Surfaces everything the
/// contract asks for: live demo mode, request count, last latency, all-boxes
/// toggle, simulated face count, and the **force-match picker** that pins every
/// face to a chosen demo person.
struct CameraDebugOverlay: View {
    @Bindable var vm: CameraViewModel
    @Environment(AppModel.self) private var appModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Camera debug", systemImage: "ladybug.fill")
                    .font(.caption.weight(.bold)).foregroundStyle(Theme.accent)
                Spacer()
                Text(appModel.demoMode.title)
                    .font(.caption2.weight(.semibold)).foregroundStyle(Theme.textSecondary)
            }

            HStack(spacing: 16) {
                stat("requests", "\(vm.requestCount)")
                stat("faces", "\(vm.observations.count)")
                stat("latency", vm.lastLatencyMs.map { String(format: "%.0fms", $0) } ?? "—")
            }

            Toggle("Show all boxes", isOn: $vm.showAllBoxes)
                .font(.caption).tint(Theme.accent)

            if vm.usingSimulatedSource {
                Stepper("Simulated faces: \(vm.simulatedFaceCount)",
                        value: $vm.simulatedFaceCount, in: 0...3)
                    .font(.caption)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("FORCE MATCH").font(.caption2.weight(.bold)).foregroundStyle(Theme.textTertiary)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        forceChip(title: "Off", id: nil)
                        ForEach(appModel.people) { p in
                            forceChip(title: p.firstName, id: p.id)
                        }
                    }
                }
            }

            if let status = vm.statusLine {
                Text(status).font(.caption2).foregroundStyle(Theme.textTertiary).lineLimit(2)
            }
        }
        .padding(12)
        .frame(maxWidth: 280, alignment: .leading)
        .glassCard(corner: 16)
        .padding(.horizontal, 16)
    }

    private func stat(_ label: String, _ value: String) -> some View {
        VStack(spacing: 1) {
            Text(value).font(.caption.weight(.bold)).foregroundStyle(Theme.textPrimary)
            Text(label).font(.system(size: 9)).foregroundStyle(Theme.textTertiary)
        }
    }

    private func forceChip(title: String, id: String?) -> some View {
        let active = vm.forceMatchPersonId == id
        return Button {
            vm.forceMatchPersonId = id
        } label: {
            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(active ? .black : Theme.textSecondary)
                .padding(.horizontal, 10).padding(.vertical, 6)
                .background(active ? Theme.accent : Color.white.opacity(0.06),
                            in: Capsule())
        }
    }
}
