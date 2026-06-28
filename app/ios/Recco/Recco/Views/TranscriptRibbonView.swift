import SwiftUI

/// Command status area. Shows the last transcript/command, a thinking spinner
/// while interpreting, and the resulting filter summary. This is the visible
/// proof that voice/typed/chips all drive the same state.
struct TranscriptRibbonView: View {
    @Environment(AppModel.self) private var appModel

    var body: some View {
        HStack(spacing: 10) {
            icon
            VStack(alignment: .leading, spacing: 2) {
                Text(primaryLine)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                Text(secondaryLine)
                    .font(.caption2)
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
            }
            Spacer()
            Text("\(appModel.visiblePersonIds.count)/\(appModel.people.count)")
                .font(.caption.weight(.bold).monospacedDigit())
                .foregroundStyle(Theme.accent)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Theme.accentSoft, in: Capsule())
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .glassCard(corner: 14)
    }

    @ViewBuilder private var icon: some View {
        if appModel.isThinking || appModel.isResolvingIdentity {
            ProgressView()
                .controlSize(.small)
                .tint(Theme.accent)
                .frame(width: 22)
        } else {
            Image(systemName: appModel.lastTranscript == nil ? "waveform" : "checkmark.circle.fill")
                .font(.subheadline)
                .foregroundStyle(appModel.lastTranscript == nil ? Theme.textTertiary : Theme.accent)
                .frame(width: 22)
        }
    }

    private var primaryLine: String {
        // Identity lane phases: Listening -> Reading badge -> Searching ->
        // Verifying -> Result (the camera/AppModel set identityStatusMessage).
        if appModel.isResolvingIdentity {
            return appModel.identityStatusMessage ?? "Identifying…"
        }
        if appModel.isThinking { return "Thinking…" }
        if let t = appModel.lastTranscript, !t.isEmpty { return "“\(t)”" }
        return "Say or type a command"
    }

    private var secondaryLine: String {
        if appModel.isResolvingIdentity { return "Finding info on the person in frame…" }
        if let msg = appModel.statusMessage { return msg }
        return appModel.activeFilter.summary
    }
}
