import SwiftUI

/// Centralized look-and-feel. Dark, camera-first, hackathon-polished. Kept in
/// one place so the whole app stays visually consistent.
enum Theme {
    static let accent = Color(red: 0.33, green: 0.74, blue: 0.95)
    static let accentSoft = Color(red: 0.33, green: 0.74, blue: 0.95).opacity(0.18)

    static let bg = Color(red: 0.05, green: 0.06, blue: 0.09)
    static let surface = Color.white.opacity(0.07)
    static let surfaceStrong = Color.white.opacity(0.12)
    static let stroke = Color.white.opacity(0.12)

    static let textPrimary = Color.white
    static let textSecondary = Color.white.opacity(0.65)
    static let textTertiary = Color.white.opacity(0.4)

    static let cardCorner: CGFloat = 20
    static let chipCorner: CGFloat = 14

    /// Stable color for a tag so the same tag always reads the same on chips,
    /// nodes, and profile cards.
    static func color(forTag tag: String) -> Color {
        let palette: [Color] = [
            Color(red: 0.36, green: 0.78, blue: 0.96), // AI / blue
            Color(red: 0.98, green: 0.62, blue: 0.36), // Founder / orange
            Color(red: 0.55, green: 0.85, blue: 0.55), // Infra / green
            Color(red: 0.84, green: 0.55, blue: 0.96), // Growth / purple
            Color(red: 0.98, green: 0.49, blue: 0.62), // Design / pink
            Color(red: 0.96, green: 0.82, blue: 0.42)  // misc / yellow
        ]
        let known: [String: Int] = [
            "AI": 0, "ML": 0, "Search": 0,
            "Founder": 1, "Seed": 1,
            "Infra": 2, "Backend": 2, "Rust": 2, "DevTools": 2,
            "Growth": 3, "GoToMarket": 3,
            "Design": 4, "Frontend": 4, "Product": 4
        ]
        if let i = known[tag] { return palette[i] }
        return palette[abs(tag.hashValue) % palette.count]
    }
}

/// Frosted glass card background used across sheets and overlays.
struct GlassCard: ViewModifier {
    var corner: CGFloat = Theme.cardCorner
    func body(content: Content) -> some View {
        content
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: corner, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: corner, style: .continuous)
                    .strokeBorder(Theme.stroke, lineWidth: 1)
            )
    }
}

extension View {
    func glassCard(corner: CGFloat = Theme.cardCorner) -> some View {
        modifier(GlassCard(corner: corner))
    }
}
