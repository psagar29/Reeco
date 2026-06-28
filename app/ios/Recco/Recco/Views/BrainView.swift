import SwiftUI

/// The Brain — a quiet event-memory workspace. Every resolved person is saved
/// here automatically; this is the searchable, filterable list of that memory.
/// Minimal graphite glass, restrained accents. Tapping a row opens the detail
/// surface (info, sources, notes, outreach).
struct BrainView: View {
    @Environment(AppModel.self) private var appModel
    @Binding var isPresented: Bool

    @State private var query = ""
    @State private var filter: MemoryFilter = .all
    @State private var openMemory: MemoryRef?

    var body: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()

            VStack(spacing: 12) {
                header
                searchField
                filterBar
                content
            }
            .padding(.horizontal, 16)
            .padding(.top, 18)
        }
        .task { await appModel.loadScanMemories() }
        .sheet(item: $openMemory) { ref in
            BrainMemoryDetailView(memoryId: ref.id)
                .environment(appModel)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
                .presentationBackground(.ultraThinMaterial)
        }
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

    // MARK: - Filter

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
            Spacer()
            ProgressView().tint(Theme.textSecondary)
            Spacer()
        } else if filtered.isEmpty {
            emptyState
        } else {
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
        .frame(maxWidth: .infinity)
    }

    // MARK: - Filtering

    private var filtered: [ScanMemoryDTO] {
        appModel.scanMemories.filter { $0.matches(query) && passes($0) }
    }

    private func passes(_ m: ScanMemoryDTO) -> Bool {
        switch filter {
        case .all: return true
        case .verified: return m.confidence == .verified
        case .possible: return m.confidence == .possible
        case .needs: return m.confidence == .needsConfirmation
        case .linkedin: return m.hasLinkedIn
        }
    }

    enum MemoryFilter: String, CaseIterable, Identifiable {
        case all, verified, possible, needs, linkedin
        var id: String { rawValue }
        var label: String {
            switch self {
            case .all: return "All"
            case .verified: return "Verified"
            case .possible: return "Possible"
            case .needs: return "Needs confirm"
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

    var body: some View {
        HStack(spacing: 11) {
            Circle()
                .fill(memory.confidence.color)
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
                ConfidencePill(confidence: memory.confidence)
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

/// Detail sheet for a saved scan: contact links, context, notes, and generated
/// outreach. It reads the memory from AppModel by id so notes/outreach updates
/// re-render without needing to dismiss the sheet.
private struct BrainMemoryDetailView: View {
    @Environment(AppModel.self) private var appModel
    let memoryId: String

    @State private var notesDraft = ""
    @State private var didSeedNotes = false
    @State private var copiedLabel: String?

    private var memory: ScanMemoryDTO? { appModel.memory(id: memoryId) }

    var body: some View {
        ScrollView {
            if let memory {
                VStack(alignment: .leading, spacing: 18) {
                    detailHeader(memory)
                    contactSection(memory)
                    sourceSection(memory)
                    notesSection(memory)
                    outreachSection(memory)
                    if let error = appModel.brainError {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(Color.red.opacity(0.85))
                    }
                }
                .padding(20)
                .onAppear { seedNotes(memory) }
            } else {
                VStack(spacing: 10) {
                    Image(systemName: "exclamationmark.circle")
                        .font(.title2)
                    Text("Memory not found")
                        .font(.headline)
                }
                .foregroundStyle(Theme.textSecondary)
                .frame(maxWidth: .infinity, minHeight: 260)
            }
        }
        .background(Theme.bg.opacity(0.45))
    }

    private func detailHeader(_ memory: ScanMemoryDTO) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(memory.displayName)
                        .font(.title2.weight(.bold))
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(2)
                    if let line = memory.roleCompanyLine {
                        Text(line)
                            .font(.subheadline)
                            .foregroundStyle(Theme.textSecondary)
                    }
                    if let school = clean(memory.school) {
                        Label(school, systemImage: "graduationcap")
                            .font(.caption)
                            .foregroundStyle(Theme.textTertiary)
                    }
                    if let headline = clean(memory.headline), headline != memory.roleCompanyLine {
                        Text(headline)
                            .font(.caption)
                            .foregroundStyle(Theme.textTertiary)
                            .lineLimit(2)
                    }
                }
                Spacer(minLength: 8)
                ConfidencePill(confidence: memory.confidence)
            }

            HStack(spacing: 8) {
                Label("\(memory.scanCount)x", systemImage: "viewfinder")
                Text(memory.lastScannedDate, format: .dateTime.month(.abbreviated).day().hour().minute())
            }
            .font(.caption2.weight(.semibold))
            .foregroundStyle(Theme.textTertiary)
        }
        .padding(16)
        .glassCard(corner: 16)
    }

    @ViewBuilder private func contactSection(_ memory: ScanMemoryDTO) -> some View {
        let links = contactLinks(memory)
        if !links.isEmpty {
            section("Links") {
                FlowLayout(spacing: 8, lineSpacing: 8) {
                    ForEach(links, id: \.label) { item in
                        if let url = URL(string: item.url) {
                            Link(destination: url) {
                                Label(item.label, systemImage: item.icon)
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(Theme.textPrimary)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                    .glassCard(corner: 12)
                            }
                        }
                    }
                }
            }
        }
    }

    private func sourceSection(_ memory: ScanMemoryDTO) -> some View {
        section("Scan context") {
            VStack(alignment: .leading, spacing: 10) {
                if !memory.sources.isEmpty {
                    FlowLayout(spacing: 6, lineSpacing: 6) {
                        ForEach(memory.sources, id: \.self) { source in
                            Text(source.uppercased())
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(Theme.textSecondary)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 5)
                                .background(Theme.surface, in: Capsule())
                                .overlay(Capsule().strokeBorder(Theme.stroke, lineWidth: 1))
                        }
                    }
                }
                if let badge = clean(memory.badgeText) {
                    Text(badge)
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(4)
                }
                if let score = memory.confidenceScore {
                    Text("Confidence \(Int((score * 100).rounded()))%")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(Theme.textTertiary)
                }
            }
        }
    }

    private func notesSection(_ memory: ScanMemoryDTO) -> some View {
        section("Notes") {
            VStack(spacing: 10) {
                TextEditor(text: $notesDraft)
                    .frame(minHeight: 92)
                    .scrollContentBackground(.hidden)
                    .foregroundStyle(Theme.textPrimary)
                    .font(.subheadline)
                    .padding(10)
                    .background(Theme.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(Theme.stroke, lineWidth: 1)
                    )

                Button {
                    Task { await appModel.updateMemoryNotes(id: memory.id, notes: notesDraft) }
                } label: {
                    Label("Save notes", systemImage: "checkmark")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 11)
                        .background(Theme.textSecondary, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
            }
        }
    }

    private func outreachSection(_ memory: ScanMemoryDTO) -> some View {
        section("Outreach") {
            VStack(alignment: .leading, spacing: 10) {
                Button {
                    Task { await appModel.generateOutreach(memoryId: memory.id) }
                } label: {
                    HStack {
                        if appModel.isGeneratingOutreach {
                            ProgressView().tint(.black)
                        } else {
                            Image(systemName: "sparkles")
                        }
                        Text(memory.outreach == nil ? "Generate outreach" : "Regenerate outreach")
                    }
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Theme.accent, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .disabled(appModel.isGeneratingOutreach)

                if let draft = memory.outreach {
                    outreachCard("LinkedIn DM", text: draft.linkedinDm)
                    outreachCard("Cold email", subtitle: draft.coldEmailSubject, text: draft.coldEmail)
                    outreachCard("In-person opener", text: draft.inPersonOpener)
                } else {
                    Text("Generate a short LinkedIn DM, cold email, and in-person opener from this scan.")
                        .font(.caption)
                        .foregroundStyle(Theme.textTertiary)
                }
            }
        }
    }

    private func outreachCard(_ title: String, subtitle: String? = nil, text: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title.uppercased())
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(Theme.textTertiary)
                    if let subtitle {
                        Text(subtitle)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Theme.textSecondary)
                            .lineLimit(1)
                    }
                }
                Spacer()
                Button {
                    UIPasteboard.general.string = [subtitle, text].compactMap { $0 }.joined(separator: "\n\n")
                    withAnimation(.easeOut(duration: 0.15)) { copiedLabel = title }
                } label: {
                    Image(systemName: copiedLabel == title ? "checkmark" : "doc.on.doc")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Theme.textSecondary)
                        .frame(width: 30, height: 30)
                        .background(Theme.surface, in: Circle())
                }
                .accessibilityLabel("Copy \(title)")
            }
            Text(text)
                .font(.caption)
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .glassCard(corner: 12)
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .font(.caption2.weight(.bold))
                .foregroundStyle(Theme.textTertiary)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func contactLinks(_ memory: ScanMemoryDTO) -> [(label: String, icon: String, url: String)] {
        var links: [(String, String, String)] = []
        if let linkedin = clean(memory.linkedinUrl) {
            links.append(("LinkedIn", "person.crop.square", linkedin))
        }
        if let email = clean(memory.email) {
            links.append(("Email", "envelope", "mailto:\(email)"))
        }
        return links
    }

    private func seedNotes(_ memory: ScanMemoryDTO) {
        guard !didSeedNotes else { return }
        notesDraft = memory.notes ?? ""
        didSeedNotes = true
    }

    private func clean(_ s: String?) -> String? {
        guard let t = s?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty else { return nil }
        return t
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
