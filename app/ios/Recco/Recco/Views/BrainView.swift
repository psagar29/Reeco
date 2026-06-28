import SwiftUI

/// The Brain — a graph-first event-memory workspace. Every resolved person is
/// saved here automatically; the default view is an interactive memory graph
/// (event hub → people → company/source/confidence clusters), with a List
/// fallback that reuses the original rows. Graphite glass, restrained accents.
/// Tapping a person node — or a list row — opens the shared detail surface
/// (info, sources, notes, outreach).
struct BrainView: View {
    @Environment(AppModel.self) private var appModel
    @Binding var isPresented: Bool

    @State private var query = ""
    @State private var filter: MemoryFilter = .all
    @State private var openMemory: MemoryRef?

    // Graph state.
    @State private var mode: BrainMode = .graph
    @State private var grouping: BrainGraphGrouping = .priority
    @State private var selectedNodeId: String?
    @State private var recenterToken = 0
    @State private var showMissionEdit = false

    var body: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()

            VStack(spacing: 11) {
                header
                missionPill
                searchField
                toolbarRow
                filterBar
                content
            }
            .padding(.horizontal, 16)
            .padding(.top, 18)
            .padding(.bottom, 6)
        }
        .task { await appModel.loadScanMemories() }
        .sheet(item: $openMemory) { ref in
            BrainMemoryDetailView(memoryId: ref.id)
                .environment(appModel)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
                .presentationBackground(.ultraThinMaterial)
        }
        .sheet(isPresented: $showMissionEdit) {
            MissionSetupView(isEditing: true, onDone: { showMissionEdit = false })
                .environment(appModel)
                .presentationDetents([.height(440)])
                .presentationDragIndicator(.visible)
                .presentationBackground(.ultraThinMaterial)
        }
    }

    // MARK: - Mission pill

    private var missionPill: some View {
        Button { showMissionEdit = true } label: {
            HStack(spacing: 6) {
                Image(systemName: appModel.missionProfile?.goalType.systemImage ?? "target")
                    .font(.caption2.weight(.bold))
                Text(appModel.missionProfile.map { "Mission · \($0.label)" } ?? "Set today's goal")
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                Image(systemName: "pencil")
                    .font(.system(size: 9, weight: .bold))
            }
            .foregroundStyle(Theme.accent)
            .padding(.horizontal, 11)
            .padding(.vertical, 6)
            .background(Theme.accentSoft, in: Capsule())
            .overlay(Capsule().strokeBorder(Theme.accent.opacity(0.4), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityLabel("Edit mission")
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Brain")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(Theme.textPrimary)
                Text("Event memory")
                    .font(.caption)
                    .foregroundStyle(Theme.textTertiary)
            }
            Spacer()
            if !appModel.scanMemories.isEmpty {
                Text("\(appModel.scanMemories.count)")
                    .font(.caption.weight(.bold).monospacedDigit())
                    .foregroundStyle(Theme.textSecondary)
                    .padding(.horizontal, 9).padding(.vertical, 4)
                    .background(Theme.surface, in: Capsule())
                    .overlay(Capsule().strokeBorder(Theme.stroke, lineWidth: 1))
            }
            Button { isPresented = false } label: {
                Image(systemName: "xmark")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.textSecondary)
                    .frame(width: 32, height: 32)
                    .background(Theme.surface, in: Circle())
                    .overlay(Circle().strokeBorder(Theme.stroke, lineWidth: 1))
            }
            .accessibilityLabel("Close Brain")
        }
    }

    // MARK: - Search

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.subheadline)
                .foregroundStyle(Theme.textTertiary)
            TextField("Search name, company, role…", text: $query)
                .textFieldStyle(.plain)
                .font(.subheadline)
                .foregroundStyle(Theme.textPrimary)
                .autocorrectionDisabled()
            if !query.isEmpty {
                Button { query = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Theme.textTertiary)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .glassCard(corner: 12)
    }

    // MARK: - Toolbar (mode toggle + graph controls)

    private var toolbarRow: some View {
        HStack(spacing: 8) {
            modeToggle
            if mode == .graph {
                groupingMenu
                Spacer(minLength: 6)
                recenterButton
            } else {
                Spacer()
            }
        }
    }

    private var modeToggle: some View {
        HStack(spacing: 2) {
            modeSegment(.graph, icon: "point.3.connected.trianglepath.dotted")
            modeSegment(.list, icon: "list.bullet")
        }
        .padding(3)
        .background(Theme.surface, in: Capsule())
        .overlay(Capsule().strokeBorder(Theme.stroke, lineWidth: 1))
    }

    private func modeSegment(_ target: BrainMode, icon: String) -> some View {
        let active = mode == target
        return Button {
            withAnimation(.easeOut(duration: 0.18)) { mode = target }
        } label: {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(active ? .black : Theme.textSecondary)
                .frame(width: 36, height: 26)
                .background(active ? AnyShapeStyle(Theme.accent) : AnyShapeStyle(.clear), in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(target == .graph ? "Graph view" : "List view")
    }

    private var groupingMenu: some View {
        Menu {
            Picker("Cluster by", selection: $grouping) {
                ForEach(BrainGraphGrouping.allCases) { g in
                    Label(g.label, systemImage: g.systemImage).tag(g)
                }
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: grouping.systemImage)
                Text(grouping.label).lineLimit(1)
                Image(systemName: "chevron.down").font(.system(size: 8, weight: .bold))
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(Theme.textSecondary)
            .padding(.horizontal, 10).padding(.vertical, 7)
            .background(Theme.surface, in: Capsule())
            .overlay(Capsule().strokeBorder(Theme.stroke, lineWidth: 1))
        }
        .accessibilityLabel("Cluster by \(grouping.label)")
    }

    private var recenterButton: some View {
        Button { recenterToken += 1 } label: {
            Image(systemName: "scope")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.textSecondary)
                .frame(width: 34, height: 34)
                .background(Theme.surface, in: Circle())
                .overlay(Circle().strokeBorder(Theme.stroke, lineWidth: 1))
        }
        .accessibilityLabel("Recenter graph")
    }

    // MARK: - Filter (shared, graph-aware: dims non-matching nodes)

    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(MemoryFilter.allCases) { f in
                    let active = filter == f
                    Button {
                        withAnimation(.easeOut(duration: 0.18)) { filter = f }
                    } label: {
                        Text(f.label)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(active ? .black : Theme.textSecondary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(
                                Capsule().fill(active ? Theme.textSecondary : Theme.surface)
                            )
                            .overlay(Capsule().strokeBorder(active ? .clear : Theme.stroke, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 1)
        }
    }

    // MARK: - Content

    @ViewBuilder private var content: some View {
        if appModel.isLoadingBrain && appModel.scanMemories.isEmpty {
            loadingState
        } else if appModel.scanMemories.isEmpty {
            emptyState
        } else if mode == .graph {
            BrainGraphView(
                memories: appModel.scanMemories,
                grouping: grouping,
                query: query,
                filterPasses: { passes($0) },
                recenterToken: recenterToken,
                selectedNodeId: $selectedNodeId,
                onOpenMemory: { openMemory = MemoryRef(id: $0) }
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if filtered.isEmpty {
            emptyState
        } else {
            listScroll
        }
    }

    private var listScroll: some View {
        ScrollView(showsIndicators: false) {
            LazyVStack(spacing: 8) {
                ForEach(filtered) { memory in
                    Button { openMemory = MemoryRef(id: memory.id) } label: {
                        MemoryRow(memory: memory)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.bottom, 24)
        }
        .refreshable { await appModel.refreshBrain() }
    }

    private var loadingState: some View {
        VStack {
            Spacer()
            ProgressView().tint(Theme.textSecondary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Spacer()
            Image(systemName: appModel.scanMemories.isEmpty ? "brain" : "magnifyingglass")
                .font(.system(size: 34, weight: .thin))
                .foregroundStyle(Theme.textTertiary)
            Text(appModel.scanMemories.isEmpty ? "No scans yet" : "No matches")
                .font(.headline)
                .foregroundStyle(Theme.textSecondary)
            if appModel.scanMemories.isEmpty {
                Text("Scan someone from the camera to build your event memory.")
                    .font(.caption)
                    .foregroundStyle(Theme.textTertiary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 260)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Filtering

    private var filtered: [ScanMemoryDTO] {
        appModel.scanMemories.filter { $0.matches(query) && passes($0) }
    }

    private func passes(_ m: ScanMemoryDTO) -> Bool {
        switch filter {
        case .all: return true
        case .hot: return m.leadPriority == .hot
        case .warm: return m.leadPriority == .warm
        case .cold: return m.leadPriority == .cold
        case .needsInfo: return m.leadPriority == .needsInfo
        case .sent: return m.isSent
        case .linkedin: return m.hasLinkedIn
        }
    }

    enum BrainMode { case graph, list }

    enum MemoryFilter: String, CaseIterable, Identifiable {
        case all, hot, warm, cold, needsInfo, sent, linkedin
        var id: String { rawValue }
        var label: String {
            switch self {
            case .all: return "All"
            case .hot: return "Hot"
            case .warm: return "Warm"
            case .cold: return "Cold"
            case .needsInfo: return "Needs info"
            case .sent: return "Sent"
            case .linkedin: return "LinkedIn"
            }
        }
    }
}

/// Lightweight Identifiable wrapper so a memory id can drive `.sheet(item:)`.
struct MemoryRef: Identifiable { let id: String }

/// One compact memory row: confidence dot, name, role · company, a confidence
/// pill, an optional LinkedIn glyph, and the last-scanned time.
private struct MemoryRow: View {
    let memory: ScanMemoryDTO

    private var dotColor: Color {
        memory.leadPriority?.color ?? memory.confidence.color
    }

    var body: some View {
        HStack(spacing: 11) {
            Circle()
                .fill(dotColor)
                .frame(width: 9, height: 9)
                .overlay(Circle().strokeBorder(.white.opacity(0.15), lineWidth: 0.5))

            VStack(alignment: .leading, spacing: 2) {
                Text(memory.displayName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                if let line = memory.roleCompanyLine {
                    Text(line)
                        .font(.caption2)
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 6)

            VStack(alignment: .trailing, spacing: 4) {
                if let priority = memory.leadPriority {
                    PriorityPill(priority: priority, sent: memory.isSent)
                } else {
                    ConfidencePill(confidence: memory.confidence)
                }
                HStack(spacing: 6) {
                    if memory.hasLinkedIn {
                        Image(systemName: "link")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(Theme.accent)
                    }
                    Text(memory.lastScannedDate, format: .relative(presentation: .numeric))
                        .font(.system(size: 10))
                        .foregroundStyle(Theme.textTertiary)
                        .lineLimit(1)
                }
            }
            .fixedSize()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 11)
        .glassCard(corner: 12)
    }
}

/// Lead priority chip used in the row and the detail header. Shows "Sent" (green)
/// when the memory has been followed up.
struct PriorityPill: View {
    let priority: LeadPriority
    var sent: Bool = false

    var body: some View {
        let color = sent ? LeadStyle.sent : priority.color
        let icon = sent ? "checkmark.circle.fill" : priority.systemImage
        let text = sent ? "Sent" : priority.label
        return HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 9, weight: .semibold))
            Text(text)
                .font(.system(size: 10, weight: .semibold))
        }
        .foregroundStyle(color)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(color.opacity(0.16), in: Capsule())
    }
}

/// A small muted confidence chip used in the row and the detail header.
struct ConfidencePill: View {
    let confidence: ScanConfidence
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: confidence.systemImage)
                .font(.system(size: 9, weight: .semibold))
            Text(confidence.label)
                .font(.system(size: 10, weight: .semibold))
        }
        .foregroundStyle(confidence.color)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(confidence.color.opacity(0.14), in: Capsule())
    }
}

extension ScanConfidence {
    /// Muted accent for each confidence bucket (restrained, never neon).
    var color: Color {
        switch self {
        case .verified: return Color(red: 0.40, green: 0.78, blue: 0.55)
        case .possible: return Color(red: 0.95, green: 0.74, blue: 0.40)
        case .needsConfirmation: return Color(red: 0.80, green: 0.72, blue: 0.52)
        case .unknown: return Theme.textTertiary
        }
    }
}
