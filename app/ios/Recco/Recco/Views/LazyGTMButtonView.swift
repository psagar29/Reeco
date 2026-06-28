import SwiftUI

/// Minimal graphite-glass "Scout" button that floats under the top camera chrome.
/// Tapping it opens the Lazy GTM voice panel. Kept small so it never crowds the
/// top bar or the AR target brackets.
struct LazyGTMButtonView: View {
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: "binoculars.fill")
                    .font(.system(size: 12, weight: .semibold))
                Text("Scout")
                    .font(.caption.weight(.semibold))
                    .fixedSize()
            }
            .foregroundStyle(Theme.textPrimary)
            .padding(.horizontal, 11)
            .padding(.vertical, 7)
            .background(.ultraThinMaterial, in: Capsule())
            .overlay(Capsule().strokeBorder(Theme.stroke, lineWidth: 1))
            .shadow(color: .black.opacity(0.25), radius: 8, y: 3)
        }
        .accessibilityLabel("Lazy GTM Scout")
    }
}
