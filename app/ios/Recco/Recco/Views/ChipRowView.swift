import SwiftUI

/// Manual filter chips: AI, Founder, Infra, Growth, Design + Reset. These are
/// the always-works fallback. Each chip routes through `appModel.toggleTag`,
/// which builds a `FilterCommandDTO` and applies it via the exact same path as
/// voice/typed commands.
struct ChipRowView: View {
    @Environment(AppModel.self) private var appModel

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(TagVocabulary.chipTags, id: \.self) { tag in
                    chip(tag)
                }
                resetChip
            }
            .padding(.horizontal, 2)
        }
    }

    private func chip(_ tag: String) -> some View {
        let active = appModel.isTagActive(tag)
        let color = Theme.color(forTag: tag)
        return Button {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                appModel.toggleTag(tag)
            }
        } label: {
            Text(tag)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(active ? .black : Theme.textPrimary)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(
                    Capsule().fill(active ? color : Theme.surface)
                )
                .overlay(
                    Capsule().strokeBorder(active ? .clear : Theme.stroke, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }

    private var resetChip: some View {
        Button {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                appModel.reset()
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "arrow.counterclockwise")
                Text("Reset")
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Theme.textSecondary)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Capsule().fill(Theme.surface))
            .overlay(Capsule().strokeBorder(Theme.stroke, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}
