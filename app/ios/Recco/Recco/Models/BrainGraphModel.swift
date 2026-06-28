import CoreGraphics
import Foundation

/// Intermediate view model for the Brain graph. Pure data — no SwiftUI, no
/// layout math — so the rendering layer (`BrainGraphView`) and the physics
/// layer (`BrainGraphLayoutEngine`) can stay small and testable. Built from the
/// app's `[ScanMemoryDTO]` by `BrainGraphBuilder`.

// MARK: - Node / edge kinds

/// What a node represents. Drives its visual treatment.
enum BrainNodeKind: Equatable, Hashable {
    /// The central "Event" hub — everything hangs off it.
    case eventHub
    /// One resolved person / scan memory.
    case memory
    /// A cluster node (priority / status / company / school / source / confidence).
    case group(BrainGroupKind)
}

/// The dimension a group node clusters on.
enum BrainGroupKind: String, Equatable, Hashable {
    case priority, status, company, school, source, confidence

    var systemImage: String {
        switch self {
        case .priority: return "flame"
        case .status: return "paperplane"
        case .company: return "building.2"
        case .school: return "graduationcap"
        case .source: return "dot.radiowaves.left.and.right"
        case .confidence: return "seal"
        }
    }
}

// MARK: - Grouping dimension (user-selectable lens)

/// The active clustering lens. `priority` is the mission-driven default; the
/// others surface different structure. Company/school clusters only form when
/// ≥2 memories share a value, so distinct singletons stay attached to the hub.
enum BrainGraphGrouping: String, CaseIterable, Identifiable {
    case priority, status, none, company, source, confidence, school

    var id: String { rawValue }

    var label: String {
        switch self {
        case .priority: return "Priority"
        case .status: return "Status"
        case .none: return "Hub"
        case .company: return "Company"
        case .source: return "Source"
        case .confidence: return "Confidence"
        case .school: return "School"
        }
    }

    var systemImage: String {
        switch self {
        case .priority: return "flame"
        case .status: return "paperplane"
        case .none: return "circle.hexagongrid"
        case .company: return "building.2"
        case .source: return "dot.radiowaves.left.and.right"
        case .confidence: return "seal"
        case .school: return "graduationcap"
        }
    }
}

// MARK: - Graph primitives

/// A single node. `memoryId` is set only for `.memory` nodes and is the bridge
/// back to `appModel.memory(id:)` when the node is tapped.
struct BrainGraphNode: Identifiable, Equatable {
    let id: String
    let kind: BrainNodeKind
    let title: String
    let subtitle: String?
    let memoryId: String?
    let confidence: ScanConfidence?
    let hasLinkedIn: Bool
    let memberCount: Int
    let weight: Double
    /// Lead priority (memory nodes, and priority group nodes for tinting).
    let leadPriority: LeadPriority?
    /// Whether this memory (or the "Sent" group) is sent.
    let isSent: Bool

    init(
        id: String,
        kind: BrainNodeKind,
        title: String,
        subtitle: String?,
        memoryId: String?,
        confidence: ScanConfidence?,
        hasLinkedIn: Bool,
        memberCount: Int,
        weight: Double,
        leadPriority: LeadPriority? = nil,
        isSent: Bool = false
    ) {
        self.id = id
        self.kind = kind
        self.title = title
        self.subtitle = subtitle
        self.memoryId = memoryId
        self.confidence = confidence
        self.hasLinkedIn = hasLinkedIn
        self.memberCount = memberCount
        self.weight = weight
        self.leadPriority = leadPriority
        self.isSent = isSent
    }

    var isMemory: Bool { if case .memory = kind { return true }; return false }
    var isHub: Bool { kind == .eventHub }
}

/// A connection. `strength` (0…1) drives both spring stiffness in the physics
/// layer and stroke opacity in the renderer — hot/verified links read stronger.
struct BrainGraphEdge: Identifiable, Equatable {
    let source: String
    let target: String
    let strength: Double
    var id: String { "\(source)→\(target)" }
}

/// The built graph plus cheap adjacency lookups for selection/highlighting.
struct BrainGraphModel: Equatable {
    var nodes: [BrainGraphNode]
    var edges: [BrainGraphEdge]

    static let empty = BrainGraphModel(nodes: [], edges: [])

    func neighbors(of id: String) -> Set<String> {
        var result = Set<String>()
        for e in edges {
            if e.source == id { result.insert(e.target) }
            else if e.target == id { result.insert(e.source) }
        }
        return result
    }

    func memoryMembers(of id: String) -> Set<String> {
        let memoryIds = Set(nodes.filter { $0.isMemory }.map(\.id))
        return neighbors(of: id).filter { memoryIds.contains($0) }
    }
}

// MARK: - Builder

enum BrainGraphBuilder {
    static let hubId = "event_hub"

    static func weight(for confidence: ScanConfidence) -> Double {
        switch confidence {
        case .verified: return 1.0
        case .possible: return 0.72
        case .needsConfirmation: return 0.52
        case .unknown: return 0.4
        }
    }

    /// Edge/size weight for a priority. Hot leads pull strongest.
    static func weight(for priority: LeadPriority?) -> Double {
        switch priority {
        case .hot: return 1.0
        case .warm: return 0.8
        case .cold: return 0.58
        case .needsInfo: return 0.45
        case .none: return 0.5
        }
    }

    static func build(memories: [ScanMemoryDTO], grouping: BrainGraphGrouping) -> BrainGraphModel {
        guard !memories.isEmpty else { return .empty }

        var nodes: [BrainGraphNode] = []
        var edges: [BrainGraphEdge] = []

        nodes.append(BrainGraphNode(
            id: hubId, kind: .eventHub, title: "Event",
            subtitle: "\(memories.count) memor\(memories.count == 1 ? "y" : "ies")",
            memoryId: nil, confidence: nil, hasLinkedIn: false,
            memberCount: memories.count, weight: 1
        ))

        for m in memories {
            let w = m.leadPriority != nil ? weight(for: m.leadPriority) : weight(for: m.confidence)
            nodes.append(BrainGraphNode(
                id: m.id, kind: .memory, title: m.displayName,
                subtitle: m.roleCompanyLine, memoryId: m.id,
                confidence: m.confidence, hasLinkedIn: m.hasLinkedIn,
                memberCount: m.scanCount, weight: w,
                leadPriority: m.leadPriority, isSent: m.isSent
            ))
        }

        switch grouping {
        case .none:
            for m in memories { edges.append(hubEdge(to: m)) }
        case .priority:
            attachByPriority(memories, nodes: &nodes, edges: &edges)
        case .status:
            attachByStatus(memories, nodes: &nodes, edges: &edges)
        case .company:
            attachByField(memories, field: { $0.company }, kind: .company, minCluster: 2, nodes: &nodes, edges: &edges)
        case .school:
            attachByField(memories, field: { $0.school }, kind: .school, minCluster: 2, nodes: &nodes, edges: &edges)
        case .confidence:
            attachByConfidence(memories, nodes: &nodes, edges: &edges)
        case .source:
            attachBySource(memories, nodes: &nodes, edges: &edges)
        }

        return BrainGraphModel(nodes: nodes, edges: edges)
    }

    // MARK: - Edge helpers

    private static func memoryStrength(_ m: ScanMemoryDTO) -> Double {
        m.leadPriority != nil ? weight(for: m.leadPriority) : weight(for: m.confidence)
    }

    private static func hubEdge(to m: ScanMemoryDTO) -> BrainGraphEdge {
        BrainGraphEdge(source: hubId, target: m.id, strength: memoryStrength(m))
    }

    private static func clean(_ s: String?) -> String? {
        guard let t = s?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty else { return nil }
        return t
    }

    /// Priority lens (the mission default): Hot / Warm / Cold / Needs info, plus a
    /// Sent cluster for memories already followed up. Unscored memories hang off
    /// the hub. Hot edges are strongest.
    private static func attachByPriority(
        _ memories: [ScanMemoryDTO],
        nodes: inout [BrainGraphNode],
        edges: inout [BrainGraphEdge]
    ) {
        let order: [LeadPriority] = [.hot, .warm, .cold, .needsInfo]

        // Sent cluster first (overrides priority bucket).
        let sent = memories.filter { $0.isSent }
        if !sent.isEmpty {
            let gid = "grp_status_sent"
            nodes.append(BrainGraphNode(
                id: gid, kind: .group(.status), title: "Sent", subtitle: "\(sent.count)",
                memoryId: nil, confidence: nil, hasLinkedIn: false,
                memberCount: sent.count, weight: 0.6, leadPriority: nil, isSent: true
            ))
            edges.append(BrainGraphEdge(source: hubId, target: gid, strength: 0.7))
            for m in sent { edges.append(BrainGraphEdge(source: gid, target: m.id, strength: 0.6)) }
        }

        for level in order {
            let members = memories.filter { !$0.isSent && $0.leadPriority == level }
            guard !members.isEmpty else { continue }
            let gid = "grp_priority_\(level.rawValue)"
            nodes.append(BrainGraphNode(
                id: gid, kind: .group(.priority), title: level.label, subtitle: "\(members.count)",
                memoryId: nil, confidence: nil, hasLinkedIn: false,
                memberCount: members.count, weight: 0.6, leadPriority: level, isSent: false
            ))
            edges.append(BrainGraphEdge(source: hubId, target: gid, strength: weight(for: level)))
            for m in members {
                edges.append(BrainGraphEdge(source: gid, target: m.id, strength: weight(for: level)))
            }
        }

        // Unscored memories attach to the hub directly.
        for m in memories where !m.isSent && m.leadPriority == nil {
            edges.append(hubEdge(to: m))
        }
    }

    /// Follow-up status lens.
    private static func attachByStatus(
        _ memories: [ScanMemoryDTO],
        nodes: inout [BrainGraphNode],
        edges: inout [BrainGraphEdge]
    ) {
        let order: [FollowUpStatus] = [.new, .drafted, .edited, .sent, .archived]
        for status in order {
            let members = memories.filter { $0.followUpStatus == status }
            guard !members.isEmpty else { continue }
            let gid = "grp_status_\(status.rawValue)"
            nodes.append(BrainGraphNode(
                id: gid, kind: .group(.status), title: status.label, subtitle: "\(members.count)",
                memoryId: nil, confidence: nil, hasLinkedIn: false,
                memberCount: members.count, weight: 0.58, leadPriority: nil, isSent: status == .sent
            ))
            edges.append(BrainGraphEdge(source: hubId, target: gid, strength: 0.65))
            for m in members {
                edges.append(BrainGraphEdge(source: gid, target: m.id, strength: memoryStrength(m)))
            }
        }
    }

    private static func attachByField(
        _ memories: [ScanMemoryDTO],
        field: (ScanMemoryDTO) -> String?,
        kind: BrainGroupKind,
        minCluster: Int,
        nodes: inout [BrainGraphNode],
        edges: inout [BrainGraphEdge]
    ) {
        var buckets: [String: (display: String, members: [ScanMemoryDTO])] = [:]
        var order: [String] = []
        for m in memories {
            guard let value = clean(field(m)) else { continue }
            let key = value.lowercased()
            if buckets[key] == nil { buckets[key] = (value, []); order.append(key) }
            buckets[key]?.members.append(m)
        }

        var clustered = Set<String>()
        for key in order {
            guard let bucket = buckets[key], bucket.members.count >= minCluster else { continue }
            let groupId = "grp_\(kind.rawValue)_\(key)"
            let avg = bucket.members.map { memoryStrength($0) }.reduce(0, +) / Double(bucket.members.count)
            nodes.append(groupNode(id: groupId, kind: kind, title: bucket.display, count: bucket.members.count))
            edges.append(BrainGraphEdge(source: hubId, target: groupId, strength: max(0.6, avg)))
            for m in bucket.members {
                edges.append(BrainGraphEdge(source: groupId, target: m.id, strength: memoryStrength(m)))
                clustered.insert(m.id)
            }
        }

        for m in memories where !clustered.contains(m.id) {
            edges.append(hubEdge(to: m))
        }
    }

    private static func attachByConfidence(
        _ memories: [ScanMemoryDTO],
        nodes: inout [BrainGraphNode],
        edges: inout [BrainGraphEdge]
    ) {
        let order: [ScanConfidence] = [.verified, .possible, .needsConfirmation, .unknown]
        for level in order {
            let members = memories.filter { $0.confidence == level }
            guard !members.isEmpty else { continue }
            let groupId = "grp_confidence_\(level.rawValue)"
            nodes.append(BrainGraphNode(
                id: groupId, kind: .group(.confidence), title: level.label, subtitle: "\(members.count)",
                memoryId: nil, confidence: level, hasLinkedIn: false,
                memberCount: members.count, weight: 0.55
            ))
            edges.append(BrainGraphEdge(source: hubId, target: groupId, strength: weight(for: level)))
            for m in members {
                edges.append(BrainGraphEdge(source: groupId, target: m.id, strength: weight(for: level)))
            }
        }
    }

    private static func attachBySource(
        _ memories: [ScanMemoryDTO],
        nodes: inout [BrainGraphNode],
        edges: inout [BrainGraphEdge]
    ) {
        var buckets: [String: Int] = [:]
        var order: [String] = []
        for m in memories {
            for s in m.sources where !s.isEmpty {
                if buckets[s] == nil { buckets[s] = 0; order.append(s) }
                buckets[s]? += 1
            }
        }
        for source in order {
            let groupId = "grp_source_\(source)"
            nodes.append(groupNode(id: groupId, kind: .source, title: source.capitalized, count: buckets[source] ?? 0))
            edges.append(BrainGraphEdge(source: hubId, target: groupId, strength: 0.7))
        }
        for m in memories {
            let sources = m.sources.filter { !$0.isEmpty }
            if sources.isEmpty {
                edges.append(hubEdge(to: m))
            } else {
                for s in sources {
                    edges.append(BrainGraphEdge(source: "grp_source_\(s)", target: m.id, strength: memoryStrength(m)))
                }
            }
        }
    }

    private static func groupNode(id: String, kind: BrainGroupKind, title: String, count: Int) -> BrainGraphNode {
        BrainGraphNode(
            id: id, kind: .group(kind), title: title,
            subtitle: "\(count)", memoryId: nil, confidence: nil,
            hasLinkedIn: false, memberCount: count, weight: 0.55
        )
    }
}
