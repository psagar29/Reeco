import SwiftUI

/// A single person node in the Brain graph. Brightens when it matches the
/// active filter, dims otherwise. Tapping selects the person (opens profile).
struct BrainNodeView: View {
    let person: PersonDTO
    let dimmed: Bool
    let highlighted: Bool
    var diameter: CGFloat = 78

    var body: some View {
        VStack(spacing: 5) {
            ZStack {
                Circle()
                    .fill(Theme.surfaceStrong)
                    .overlay(Circle().strokeBorder(ringColor, lineWidth: highlighted ? 3 : 1.5))
                AvatarView(person: person, size: diameter - 14)
            }
            .frame(width: diameter, height: diameter)
            .shadow(color: highlighted ? Theme.accent.opacity(0.5) : .black.opacity(0.3),
                    radius: highlighted ? 14 : 6)

            Text(person.firstName)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(Theme.textPrimary)
            Text(person.tags.first ?? "")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(Theme.color(forTag: person.tags.first ?? "AI"))
        }
        .opacity(dimmed ? 0.3 : 1)
        .scaleEffect(dimmed ? 0.85 : (highlighted ? 1.08 : 1))
        .animation(.spring(response: 0.45, dampingFraction: 0.75), value: dimmed)
        .animation(.spring(response: 0.45, dampingFraction: 0.75), value: highlighted)
    }

    private var ringColor: Color {
        if highlighted { return Theme.accent }
        if dimmed { return Theme.stroke }
        return Theme.color(forTag: person.tags.first ?? "AI").opacity(0.7)
    }
}
