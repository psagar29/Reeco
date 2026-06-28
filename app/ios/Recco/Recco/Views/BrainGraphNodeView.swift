import SwiftUI

/// One node in the Brain graph. Pure presentation — position, selection and
/// dimming are decided by `BrainGraphView`. Graphite glass with a restrained
/// confidence ring; the label sits *below* the circle as a non-interactive
/// overlay so the node's tappable centre stays exactly on its physics point.
struct BrainGraphNodeView: View {
    let node: BrainGraphNode
    let diameter: CGFloat
    var selected: Bool = false
    var dimmed: Bool = false

    var body: some View {
        circle
            .frame(width: diameter, height: diameter)
            .overlay(alignment: .top) { label.offset(y: diameter + 4) }
            .opacity(dimmed ? 0.24 : 1)
            .scaleEffect(dimmed ? 0.88 : (selected ? 1.08 : 1))
            .animation(.spring(response: 0.5, dampingFraction: 0.8), value: dimmed)
            .animation(.spring(response: 0.4, dampingFraction: 0.7), value: selected)
            .animation(.spring(response: 0.4, dampingFraction: 0.8), value: diameter)
    }

    // MARK: - Circle

    @ViewBuilder private var circle: some View {
        switch node.kind {
        case .eventHub: hubCircle
        case .memory: memoryCircle
        case .group(let kind): groupCircle(kind)
        }
    }

    private var hubCircle: some View {
        ZStack {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [Theme.surfaceStrong, Color.white.opacity(0.03)],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    )
                )
            Circle().strokeBorder(Theme.accent.opacity(0.85), lineWidth: 2)
            VStack(spacing: 2) {
                Image(systemName: "point.3.filled.connected.trianglepath.dotted")
                    .font(.system(size: diameter * 0.26, weight: .semibold))
                    .foregroundStyle(Theme.accent)
                Text("Event")
                    .font(.system(size: max(9, diameter * 0.15), weight: .bold))
                    .foregroundStyle(Theme.textPrimary)
            }
        }
        .shadow(color: Theme.accent.opacity(0.35), radius: 16)
    }

    /// Priority wins for the ring color; confidence is the fallback for unscored.
    private var ringColor: Color {
        node.leadPriority?.color ?? node.confidence?.color ?? Theme.textTertiary
    }

    private var isHot: Bool { node.leadPriority == .hot }

    private var memoryCircle: some View {
        let ring = ringColor
        let glow = selected ? Theme.accent.opacity(0.55)
            : (isHot ? ring.opacity(0.5) : .black.opacity(0.35))
        return ZStack {
            Circle().fill(Theme.surfaceStrong)
            Circle().strokeBorder(selected ? Theme.accent : ring.opacity(0.9),
                                  lineWidth: selected ? 3 : (isHot ? 2.5 : 2))
            Text(initials)
                .font(.system(size: diameter * 0.34, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.textPrimary)
                .minimumScaleFactor(0.6)
                .lineLimit(1)
                .padding(diameter * 0.16)

            if node.hasLinkedIn {
                badge(systemName: "link", tint: Theme.accent)
                    .offset(x: diameter * 0.34, y: -diameter * 0.34)
            }
            if node.isSent {
                badge(systemName: "checkmark", tint: LeadStyle.sent)
                    .offset(x: -diameter * 0.34, y: -diameter * 0.34)
            }
        }
        .shadow(color: glow, radius: selected ? 16 : (isHot ? 12 : 6))
    }

    private func badge(systemName: String, tint: Color) -> some View {
        Image(systemName: systemName)
            .font(.system(size: max(8, diameter * 0.22), weight: .bold))
            .foregroundStyle(.black)
            .frame(width: diameter * 0.42, height: diameter * 0.42)
            .background(tint, in: Circle())
            .overlay(Circle().strokeBorder(Theme.bg, lineWidth: 1.5))
    }

    private func groupCircle(_ kind: BrainGroupKind) -> some View {
        let tint = node.leadPriority?.color
            ?? (node.isSent ? LeadStyle.sent : (node.confidence?.color ?? Theme.textSecondary))
        return ZStack {
            Circle().fill(Theme.surface)
            Circle().strokeBorder(selected ? Theme.accent.opacity(0.9) : tint.opacity(0.5),
                                  lineWidth: selected ? 2 : 1.2)
            Image(systemName: node.isSent ? "checkmark" : kind.systemImage)
                .font(.system(size: diameter * 0.34, weight: .semibold))
                .foregroundStyle(tint.opacity(0.95))
        }
        .opacity(0.95)
        .shadow(color: selected ? Theme.accent.opacity(0.4) : .clear, radius: 10)
    }

    // MARK: - Label

    @ViewBuilder private var label: some View {
        switch node.kind {
        case .eventHub:
            EmptyView()   // the hub carries its own inset label
        case .memory:
            VStack(spacing: 1) {
                Text(shortName)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                if selected, let sub = node.subtitle {
                    Text(sub)
                        .font(.system(size: 9))
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(1)
                }
            }
            .frame(width: max(diameter * 2.1, 104))
            .multilineTextAlignment(.center)
            .allowsHitTesting(false)
        case .group:
            VStack(spacing: 1) {
                Text(node.title)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
                if let sub = node.subtitle {
                    Text(sub)
                        .font(.system(size: 8, weight: .bold).monospacedDigit())
                        .foregroundStyle(Theme.textTertiary)
                }
            }
            .frame(width: max(diameter * 2.2, 88))
            .multilineTextAlignment(.center)
            .allowsHitTesting(false)
        }
    }

    // MARK: - Derived text

    private var shortName: String {
        node.title.split(separator: " ").first.map(String.init) ?? node.title
    }

    private var initials: String {
        let parts = node.title.split(separator: " ")
        let letters = parts.prefix(2).compactMap { $0.first }
        let s = String(letters).uppercased()
        return s.isEmpty ? "?" : s
    }
}
