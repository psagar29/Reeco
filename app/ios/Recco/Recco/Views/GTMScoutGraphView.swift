import SwiftUI

/// The Scout prospect graph: a central run hub with prospect nodes orbiting it.
/// Reuses `BrainGraphLayoutEngine` for physics. Pan, pinch-zoom, per-node drag,
/// tap-to-open; double-tap background recenters. Hot nodes pull strongest.
struct GTMScoutGraphView: View {
    let prospects: [GTMProspectDTO]
    @Binding var selectedId: String?
    let onOpen: (String) -> Void

    @State private var engine = BrainGraphLayoutEngine()
    @State private var nodes: [BrainGraphNode] = []
    @State private var edges: [BrainGraphEdge] = []

    @State private var zoom: CGFloat = 1
    @State private var committedZoom: CGFloat = 1
    @State private var pan: CGSize = .zero
    @State private var committedPan: CGSize = .zero
    @State private var dragNode: String?
    @State private var dragMoved = false

    private let hubId = "gtm_run"
    private let space = "gtmGraph"

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            let positions = engine.positions

            ZStack {
                RadialGradient(colors: [Theme.accent.opacity(0.08), .clear], center: .center, startRadius: 8, endRadius: 420)
                    .allowsHitTesting(false)

                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture(count: 2) { recenter() }
                    .onTapGesture { select(nil) }

                edgeCanvas(positions: positions)

                // Hub.
                hubView
                    .position(positions[hubId] ?? center(size))

                ForEach(prospects) { p in
                    GTMProspectNodeView(
                        prospect: p,
                        diameter: engine.radius(p.id) * 2,
                        selected: selectedId == p.id,
                        dimmed: selectedId != nil && selectedId != p.id
                    )
                    .position(positions[p.id] ?? center(size))
                    .highPriorityGesture(nodeDrag(p))
                }
            }
            .frame(width: size.width, height: size.height)
            .scaleEffect(zoom)
            .offset(pan)
            .coordinateSpace(name: space)
            .contentShape(Rectangle())
            .gesture(panGesture)
            .simultaneousGesture(zoomGesture)
            .clipped()
            .onAppear { rebuild(size: size) }
            .onChange(of: prospects) { _, _ in rebuild(size: size) }
            .onChange(of: size) { _, s in engine.update(nodes: nodes, edges: edges, size: s) }
            .onDisappear { engine.stop() }
        }
    }

    private var hubView: some View {
        VStack(spacing: 2) {
            Image(systemName: "binoculars.fill")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Theme.accent)
            Text("Scout").font(.system(size: 10, weight: .bold)).foregroundStyle(Theme.textPrimary)
        }
        .frame(width: 72, height: 72)
        .background(
            LinearGradient(colors: [Theme.surfaceStrong, .white.opacity(0.03)], startPoint: .topLeading, endPoint: .bottomTrailing),
            in: Circle()
        )
        .overlay(Circle().strokeBorder(Theme.accent.opacity(0.85), lineWidth: 2))
        .shadow(color: Theme.accent.opacity(0.35), radius: 16)
    }

    private func edgeCanvas(positions: [String: CGPoint]) -> some View {
        let sel = selectedId
        return Canvas { ctx, _ in
            for edge in edges {
                guard let p1 = positions[edge.source], let p2 = positions[edge.target] else { continue }
                let hot = sel != nil && (edge.source == sel || edge.target == sel)
                let dim = sel != nil && !hot
                var path = Path(); path.move(to: p1); path.addLine(to: p2)
                let opacity: Double = hot ? 0.85 : (dim ? 0.06 : 0.10 + 0.24 * edge.strength)
                ctx.stroke(path, with: .color((hot ? Theme.accent : .white).opacity(opacity)), lineWidth: hot ? 2 : 1)
            }
        }
        .allowsHitTesting(false)
    }

    private var panGesture: some Gesture {
        DragGesture()
            .onChanged { v in pan = CGSize(width: committedPan.width + v.translation.width, height: committedPan.height + v.translation.height) }
            .onEnded { _ in committedPan = pan }
    }

    private var zoomGesture: some Gesture {
        MagnificationGesture()
            .onChanged { value in zoom = min(max(committedZoom * value, 0.55), 2.6) }
            .onEnded { _ in committedZoom = zoom }
    }

    private func nodeDrag(_ p: GTMProspectDTO) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named(space))
            .onChanged { value in
                if dragNode == nil { dragNode = p.id; dragMoved = false; engine.beginDrag(p.id) }
                if abs(value.translation.width) + abs(value.translation.height) > 6 { dragMoved = true }
                if dragMoved { engine.drag(p.id, to: value.location) }
            }
            .onEnded { _ in
                if dragMoved { engine.endDrag(p.id) } else { select(p.id); onOpen(p.id) }
                dragNode = nil; dragMoved = false
            }
    }

    private func select(_ id: String?) {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { selectedId = id }
    }

    private func recenter() {
        withAnimation(.spring(response: 0.5, dampingFraction: 0.85)) {
            zoom = 1; committedZoom = 1; pan = .zero; committedPan = .zero
        }
        engine.recenter()
    }

    private func rebuild(size: CGSize) {
        var n: [BrainGraphNode] = [
            BrainGraphNode(id: hubId, kind: .eventHub, title: "Scout", subtitle: "\(prospects.count)",
                           memoryId: nil, confidence: nil, hasLinkedIn: false, memberCount: prospects.count, weight: 1),
        ]
        var e: [BrainGraphEdge] = []
        for p in prospects {
            let w = BrainGraphBuilder.weight(for: p.priority)
            n.append(BrainGraphNode(id: p.id, kind: .memory, title: p.displayName, subtitle: p.roleCompanyLine,
                                    memoryId: p.id, confidence: nil, hasLinkedIn: p.hasLinkedIn, memberCount: 1,
                                    weight: w, leadPriority: p.priority, isSent: p.isSent))
            e.append(BrainGraphEdge(source: hubId, target: p.id, strength: w))
        }
        nodes = n
        edges = e
        if let sel = selectedId, !prospects.contains(where: { $0.id == sel }) { selectedId = nil }
        engine.update(nodes: n, edges: e, size: size)
    }

    private func center(_ size: CGSize) -> CGPoint { CGPoint(x: size.width / 2, y: size.height / 2) }
}
