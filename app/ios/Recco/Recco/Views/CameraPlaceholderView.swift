import SwiftUI

/// Camera-first hero screen — **placeholder**.
///
/// Person C owns the real AVFoundation camera + Vision face tracking under
/// `app/ios/Recco/Camera/`. This view stands in for it so the demo shell is
/// fully usable today, and it demonstrates the exact contract Person C plugs
/// into:
///
///   1. Read the roster:        `appModel.peopleById`
///   2. Read filter state:      `appModel.state.visiblePersonIds` / `.dimmedPersonIds`
///   3. Feed recognition in:    `appModel.applyMatch(_:)`
///   4. On overlay tap:         `appModel.selectPerson(personId)`
///
/// To integrate the real camera, replace `CameraBackdrop` with the live
/// preview and drive `MockFaceOverlay`s from real face boxes + match results.
/// The overlay card itself (`FaceOverlayCard`) is reusable as-is.
struct CameraPlaceholderView: View {
    @Environment(AppModel.self) private var appModel

    /// Which roster people are "in frame" for the demo. Deterministic subset so
    /// the stage view is stable. Person C replaces this with live tracks.
    private var inFrame: [PersonDTO] {
        Array(appModel.people.prefix(3))
    }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                CameraBackdrop()

                // Simulated face overlays, positioned across the frame.
                ForEach(Array(inFrame.enumerated()), id: \.element.id) { index, person in
                    let pos = position(for: index, in: geo.size)
                    FaceOverlayCard(
                        person: person,
                        dimmed: appModel.state.isDimmed(person.id),
                        highlighted: appModel.state.highlightedPersonId == person.id
                    )
                    .position(pos)
                    .onTapGesture { appModel.selectPerson(person.id) } // Person C seam
                }
            }
        }
    }

    /// Spread the in-frame overlays out so they don't overlap.
    private func position(for index: Int, in size: CGSize) -> CGPoint {
        let columns: [CGFloat] = [0.27, 0.72, 0.5]
        let rows: [CGFloat] = [0.34, 0.40, 0.6]
        let cx = columns[index % columns.count]
        let cy = rows[index % rows.count]
        return CGPoint(x: size.width * cx, y: size.height * cy)
    }
}

/// The faux "camera feed" background. Dark gradient + scan grid + hint text so
/// the placeholder reads as intentional, not broken.
private struct CameraBackdrop: View {
    @Environment(AppModel.self) private var appModel

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(red: 0.08, green: 0.10, blue: 0.16), Color(red: 0.03, green: 0.04, blue: 0.07)],
                startPoint: .top, endPoint: .bottom
            )

            // Subtle scan grid.
            GeometryReader { geo in
                Path { path in
                    let step: CGFloat = 44
                    var x: CGFloat = 0
                    while x < geo.size.width { path.move(to: CGPoint(x: x, y: 0)); path.addLine(to: CGPoint(x: x, y: geo.size.height)); x += step }
                    var y: CGFloat = 0
                    while y < geo.size.height { path.move(to: CGPoint(x: 0, y: y)); path.addLine(to: CGPoint(x: geo.size.width, y: y)); y += step }
                }
                .stroke(Color.white.opacity(0.03), lineWidth: 1)
            }

            VStack(spacing: 10) {
                Image(systemName: "viewfinder")
                    .font(.system(size: 44, weight: .thin))
                    .foregroundStyle(Theme.textTertiary)
                Text("Camera preview")
                    .font(.headline)
                    .foregroundStyle(Theme.textSecondary)
                Text("Person C's live camera mounts here.\nTap a card to open a profile.")
                    .font(.caption)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(Theme.textTertiary)
            }
            .offset(y: -40)
        }
    }
}

/// Overlay card anchored to a (mock) face. Reusable by Person C for real boxes.
/// Shows name, role/company, a couple of tags, and the why-talk line. Dims when
/// the active filter excludes the person.
struct FaceOverlayCard: View {
    let person: PersonDTO
    var dimmed: Bool = false
    var highlighted: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                AvatarView(person: person, size: 34)
                VStack(alignment: .leading, spacing: 1) {
                    Text(person.name)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(Theme.textPrimary)
                    Text("\(person.role) · \(person.company)")
                        .font(.caption2)
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            FlowTags(tags: person.tags, limit: 3)
            Text(person.whyTalk)
                .font(.caption2)
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(2)
        }
        .padding(10)
        .frame(width: 190, alignment: .leading)
        .glassCard(corner: 16)
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(highlighted ? Theme.accent : .clear, lineWidth: 2)
        )
        .opacity(dimmed ? 0.32 : 1)
        .scaleEffect(dimmed ? 0.94 : 1)
        .shadow(color: .black.opacity(0.4), radius: 12, y: 6)
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: dimmed)
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: highlighted)
    }
}
