import SwiftUI

/// Avatar circle: tries the remote avatar URL, falls back to colored initials.
/// The sample roster uses example.com URLs, so the initials path is the norm
/// in the demo — and it looks intentional.
struct AvatarView: View {
    let person: PersonDTO
    var size: CGFloat = 56

    private var accent: Color { Theme.color(forTag: person.tags.first ?? "AI") }

    var body: some View {
        ZStack {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [accent.opacity(0.9), accent.opacity(0.45)],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    )
                )
            Text(person.initials)
                .font(.system(size: size * 0.36, weight: .bold, design: .rounded))
                .foregroundStyle(.white)

            if let urlString = person.avatarUrl,
               let url = URL(string: urlString),
               !urlString.contains("example.com") {
                AsyncImage(url: url) { phase in
                    if case .success(let image) = phase {
                        image.resizable().scaledToFill()
                    }
                }
                .clipShape(Circle())
            }
        }
        .frame(width: size, height: size)
        .overlay(Circle().strokeBorder(.white.opacity(0.25), lineWidth: 1))
    }
}

/// Small rounded tag pill.
struct TagPill: View {
    let tag: String
    var active: Bool = true

    var body: some View {
        let color = Theme.color(forTag: tag)
        Text(tag)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(active ? color : Theme.textTertiary)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(
                Capsule().fill(active ? color.opacity(0.16) : Color.white.opacity(0.05))
            )
            .overlay(
                Capsule().strokeBorder(active ? color.opacity(0.5) : Theme.stroke, lineWidth: 1)
            )
    }
}

/// Wrapping horizontal layout for tag pills (simple flow layout).
struct FlowTags: View {
    let tags: [String]
    var limit: Int? = nil

    var body: some View {
        let shown = limit.map { Array(tags.prefix($0)) } ?? tags
        FlowLayout(spacing: 6, lineSpacing: 6) {
            ForEach(shown, id: \.self) { TagPill(tag: $0) }
            if let limit, tags.count > limit {
                TagPill(tag: "+\(tags.count - limit)", active: false)
            }
        }
    }
}

/// Minimal flow layout that wraps subviews onto new lines.
struct FlowLayout: Layout {
    var spacing: CGFloat = 6
    var lineSpacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var lineHeight: CGFloat = 0
        for sub in subviews {
            let size = sub.sizeThatFits(.unspecified)
            if x + size.width > maxWidth, x > 0 {
                x = 0
                y += lineHeight + lineSpacing
                lineHeight = 0
            }
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
        return CGSize(width: maxWidth == .infinity ? x : maxWidth, height: y + lineHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) {
        let maxWidth = bounds.width
        var x: CGFloat = bounds.minX
        var y: CGFloat = bounds.minY
        var lineHeight: CGFloat = 0
        for sub in subviews {
            let size = sub.sizeThatFits(.unspecified)
            if x + size.width > bounds.minX + maxWidth, x > bounds.minX {
                x = bounds.minX
                y += lineHeight + lineSpacing
                lineHeight = 0
            }
            sub.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
    }
}
