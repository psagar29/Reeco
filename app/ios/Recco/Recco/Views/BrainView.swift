import SwiftUI

/// The Brain graph. A polished radial layout (Grape-free, so it always builds)
/// that shows every roster person as a node orbiting a central "you" hub.
/// The active filter brightens matches and dims the rest — the same state the
/// camera overlays use. Tapping a node opens the shared profile sheet.
struct BrainView: View {
    @Environment(AppModel.self) private var appModel
    @Binding var isPresented: Bool

    var body: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()
            radialGradient.ignoresSafeArea()

            VStack(spacing: 0) {
                header
                GeometryReader { geo in
                    graph(in: geo.size)
                }
                ChipRowView()
                    .padding(.horizontal, 16)
                    .padding(.bottom, 12)
            }
        }
        .environment(appModel)
        // Profile sheet from a node tap — same sheet as the camera overlay.
        .sheet(item: Binding(
            get: { appModel.selectedPerson },
            set: { appModel.selectPerson($0?.id) }
        )) { person in
            ProfileSheetView(person: person)
                .environment(appModel)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
                .presentationBackground(.ultraThinMaterial)
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Brain")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(Theme.textPrimary)
                Text(appModel.activeFilter.summary)
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
            }
            Spacer()
            Button { isPresented = false } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title2)
                    .foregroundStyle(Theme.textSecondary)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 20)
        .padding(.bottom, 8)
    }

    // MARK: - Graph

    private func graph(in size: CGSize) -> some View {
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let radius = min(size.width, size.height) * 0.36
        let people = appModel.people
        let positions = nodePositions(count: people.count, center: center, radius: radius)

        return ZStack {
            // Edges from hub to each node.
            ForEach(Array(people.enumerated()), id: \.element.id) { index, person in
                Path { p in
                    p.move(to: center)
                    p.addLine(to: positions[index])
                }
                .stroke(edgeColor(for: person), lineWidth: 1.5)
                .animation(.easeInOut(duration: 0.4), value: appModel.state.updatedAt)
            }

            // Central hub.
            hub.position(center)

            // Person nodes.
            ForEach(Array(people.enumerated()), id: \.element.id) { index, person in
                BrainNodeView(
                    person: person,
                    dimmed: appModel.state.isDimmed(person.id),
                    highlighted: appModel.state.highlightedPersonId == person.id
                        || appModel.selectedPersonId == person.id
                )
                .position(positions[index])
                .onTapGesture { appModel.selectPerson(person.id) }
            }
        }
    }

    private var hub: some View {
        VStack(spacing: 2) {
            Image(systemName: "brain.head.profile")
                .font(.title2.weight(.semibold))
                .foregroundStyle(.black)
            Text("You")
                .font(.caption2.weight(.bold))
                .foregroundStyle(.black)
        }
        .frame(width: 84, height: 84)
        .background(Circle().fill(Theme.accent))
        .shadow(color: Theme.accent.opacity(0.6), radius: 18)
    }

    private func nodePositions(count: Int, center: CGPoint, radius: CGFloat) -> [CGPoint] {
        guard count > 0 else { return [] }
        return (0..<count).map { i in
            let angle = (Double(i) / Double(count)) * 2 * .pi - .pi / 2
            return CGPoint(
                x: center.x + radius * cos(angle),
                y: center.y + radius * sin(angle)
            )
        }
    }

    private func edgeColor(for person: PersonDTO) -> Color {
        if appModel.state.isDimmed(person.id) { return Theme.stroke.opacity(0.5) }
        return Theme.color(forTag: person.tags.first ?? "AI").opacity(0.4)
    }

    private var radialGradient: some View {
        RadialGradient(
            colors: [Theme.accent.opacity(0.10), .clear],
            center: .center, startRadius: 10, endRadius: 360
        )
    }
}
