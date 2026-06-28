import SwiftUI

/// Demo fallback mode switcher. Lets the operator drop from `live` to `mockCV`
/// to `mockAll` if anything breaks on stage — the recovery hatch the brief
/// requires.
struct DemoModePicker: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Demo Mode")
                .font(.title3.weight(.bold))
                .foregroundStyle(Theme.textPrimary)
            Text("Drop to a safer level if voice, camera, or backend misbehaves.")
                .font(.caption)
                .foregroundStyle(Theme.textSecondary)

            ForEach(DemoMode.allCases) { mode in
                Button {
                    appModel.setDemoMode(mode)
                    dismiss()
                } label: {
                    row(mode)
                }
                .buttonStyle(.plain)
            }
            Spacer(minLength: 0)
        }
        .padding(20)
    }

    private func row(_ mode: DemoMode) -> some View {
        let selected = appModel.demoMode == mode
        return HStack(spacing: 12) {
            Image(systemName: mode.systemImage)
                .font(.headline)
                .foregroundStyle(selected ? .black : Theme.accent)
                .frame(width: 40, height: 40)
                .background(Circle().fill(selected ? Theme.accent : Theme.accentSoft))
            VStack(alignment: .leading, spacing: 2) {
                Text(mode.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)
                Text(mode.subtitle)
                    .font(.caption2)
                    .foregroundStyle(Theme.textSecondary)
            }
            Spacer()
            if selected {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.accent)
            }
        }
        .padding(12)
        .glassCard(corner: 14)
    }
}
