import SwiftUI

/// One AI-found prospect node in the Scout graph. Priority ring + glow, a Sent
/// badge once followed up, and a LinkedIn badge when a profile exists. Label sits
/// below the circle so the tappable centre stays on the physics point.
struct GTMProspectNodeView: View {
    let prospect: GTMProspectDTO
    let diameter: CGFloat
    var selected: Bool = false
    var dimmed: Bool = false

    private var ring: Color { prospect.priority.color }
    private var isHot: Bool { prospect.priority == .hot }

    var body: some View {
        circle
            .frame(width: diameter, height: diameter)
            .overlay(alignment: .top) { label.offset(y: diameter + 4) }
            .opacity(dimmed ? 0.26 : 1)
            .scaleEffect(dimmed ? 0.9 : (selected ? 1.08 : 1))
            .animation(.spring(response: 0.45, dampingFraction: 0.8), value: selected)
            .animation(.spring(response: 0.45, dampingFraction: 0.8), value: dimmed)
            .animation(.spring(response: 0.4, dampingFraction: 0.8), value: diameter)
    }

    private var circle: some View {
        let glow = selected ? Theme.accent.opacity(0.55) : (isHot ? ring.opacity(0.5) : .black.opacity(0.35))
        return ZStack {
            Circle().fill(Theme.surfaceStrong)
            Circle().strokeBorder(selected ? Theme.accent : ring.opacity(0.9),
                                  lineWidth: selected ? 3 : (isHot ? 2.5 : 2))
            Text(prospect.initials)
                .font(.system(size: diameter * 0.34, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.textPrimary)
                .minimumScaleFactor(0.6).lineLimit(1).padding(diameter * 0.16)

            if prospect.hasLinkedIn {
                badge("link", tint: Theme.accent).offset(x: diameter * 0.34, y: -diameter * 0.34)
            }
            if prospect.isSent {
                badge("checkmark", tint: LeadStyle.sent).offset(x: -diameter * 0.34, y: -diameter * 0.34)
            }
        }
        .shadow(color: glow, radius: selected ? 16 : (isHot ? 12 : 6))
    }

    private func badge(_ systemName: String, tint: Color) -> some View {
        Image(systemName: systemName)
            .font(.system(size: max(8, diameter * 0.22), weight: .bold))
            .foregroundStyle(.black)
            .frame(width: diameter * 0.42, height: diameter * 0.42)
            .background(tint, in: Circle())
            .overlay(Circle().strokeBorder(Theme.bg, lineWidth: 1.5))
    }

    private var label: some View {
        VStack(spacing: 1) {
            Text(prospect.displayName.split(separator: " ").first.map(String.init) ?? prospect.displayName)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)
            if selected, let line = prospect.roleCompanyLine {
                Text(line).font(.system(size: 9)).foregroundStyle(Theme.textSecondary).lineLimit(1)
            }
        }
        .frame(width: max(diameter * 2.1, 104))
        .multilineTextAlignment(.center)
        .allowsHitTesting(false)
    }
}
