import SwiftUI

/// Detail sheet for a saved scan: lead priority + reasons, contact links, scan
/// context, notes, and editable, mission-aware outreach with a (fake) Send.
/// Reads the memory from `AppModel` by id so scoring / status / outreach updates
/// re-render without dismissing — and so the graph behind keeps its layout.
struct BrainMemoryDetailView: View {
    @Environment(AppModel.self) private var appModel
    let memoryId: String

    @State private var notesDraft = ""
    @State private var didSeedNotes = false
    @State private var copiedLabel: String?

    // Outreach editing / sending.
    @State private var editing = false
    @State private var draft = OutreachDraftDTO(
        linkedinDm: "", coldEmailSubject: "", coldEmail: "", inPersonOpener: ""
    )
    @State private var sending = false

    private var memory: ScanMemoryDTO? { appModel.memory(id: memoryId) }

    var body: some View {
        ScrollView {
            if let memory {
                VStack(alignment: .leading, spacing: 18) {
                    detailHeader(memory)
                    leadSection(memory)
                    reasonsSection(memory)
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
                    Image(systemName: "exclamationmark.circle").font(.title2)
                    Text("Memory not found").font(.headline)
                }
                .foregroundStyle(Theme.textSecondary)
                .frame(maxWidth: .infinity, minHeight: 260)
            }
        }
        .background(Theme.bg.opacity(0.45))
    }

    // MARK: - Header

    private func detailHeader(_ memory: ScanMemoryDTO) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(memory.displayName)
                        .font(.title2.weight(.bold))
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(2)
                    if let line = memory.roleCompanyLine {
                        Text(line).font(.subheadline).foregroundStyle(Theme.textSecondary)
                    }
                    if let school = clean(memory.school) {
                        Label(school, systemImage: "graduationcap")
                            .font(.caption).foregroundStyle(Theme.textTertiary)
                    }
                    if let headline = clean(memory.headline), headline != memory.roleCompanyLine {
                        Text(headline).font(.caption).foregroundStyle(Theme.textTertiary).lineLimit(2)
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

    // MARK: - Lead

    private func leadSection(_ memory: ScanMemoryDTO) -> some View {
        section("This lead") {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    if let priority = memory.leadPriority {
                        PriorityPill(priority: priority, sent: memory.isSent)
                    } else {
                        Text("Unscored").font(.caption.weight(.semibold)).foregroundStyle(Theme.textTertiary)
                    }
                    if let score = memory.leadScore {
                        Text("\(Int(score))")
                            .font(.subheadline.weight(.bold).monospacedDigit())
                            .foregroundStyle(Theme.textPrimary)
                        + Text(" / 100").font(.caption2).foregroundStyle(Theme.textTertiary)
                    }
                    Spacer()
                    statusChip(memory.followUpStatus)
                }
                HStack(spacing: 10) {
                    if let action = nextActionLabel(memory) {
                        Label("Suggested: \(action)", systemImage: "arrow.turn.down.right")
                            .font(.caption).foregroundStyle(Theme.textSecondary)
                    }
                    if let mission = memory.missionSnapshot {
                        Label(mission.label, systemImage: "target")
                            .font(.caption2.weight(.semibold)).foregroundStyle(Theme.accent)
                    }
                }
            }
        }
    }

    @ViewBuilder private func reasonsSection(_ memory: ScanMemoryDTO) -> some View {
        if !memory.leadReasons.isEmpty {
            section("Why this lead") {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(memory.leadReasons, id: \.self) { reason in
                        Label {
                            Text(reason).font(.caption).foregroundStyle(Theme.textSecondary)
                        } icon: {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.caption2)
                                .foregroundStyle((memory.leadPriority ?? .cold).color)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Contact / context

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
                                    .padding(.horizontal, 12).padding(.vertical, 8)
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
                                .padding(.horizontal, 8).padding(.vertical, 5)
                                .background(Theme.surface, in: Capsule())
                                .overlay(Capsule().strokeBorder(Theme.stroke, lineWidth: 1))
                        }
                    }
                }
                if let badge = clean(memory.badgeText) {
                    Text(badge).font(.caption).foregroundStyle(Theme.textSecondary).lineLimit(4)
                }
                if let score = memory.confidenceScore {
                    Text("Match confidence \(Int((score * 100).rounded()))%")
                        .font(.caption2.weight(.semibold)).foregroundStyle(Theme.textTertiary)
                }
            }
        }
    }

    private func notesSection(_ memory: ScanMemoryDTO) -> some View {
        section("Notes") {
            VStack(spacing: 10) {
                TextEditor(text: $notesDraft)
                    .frame(minHeight: 80)
                    .scrollContentBackground(.hidden)
                    .foregroundStyle(Theme.textPrimary)
                    .font(.subheadline)
                    .padding(10)
                    .background(Theme.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Theme.stroke, lineWidth: 1))
                Button {
                    Task { await appModel.updateMemoryNotes(id: memory.id, notes: notesDraft) }
                } label: {
                    Label("Save notes", systemImage: "checkmark")
                        .font(.caption.weight(.bold)).foregroundStyle(.black)
                        .frame(maxWidth: .infinity).padding(.vertical, 11)
                        .background(Theme.textSecondary, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
            }
        }
    }

    // MARK: - Outreach (editable + fake send)

    private func outreachSection(_ memory: ScanMemoryDTO) -> some View {
        section("Follow-up") {
            VStack(alignment: .leading, spacing: 10) {
                if let current = memory.effectiveOutreach {
                    let shown = editing ? draft : current
                    outreachControls(memory)
                    editableField("LinkedIn DM", text: shown.linkedinDm, binding: $draft.linkedinDm, multiline: true)
                    editableField("Cold email subject", text: shown.coldEmailSubject, binding: $draft.coldEmailSubject, multiline: false)
                    editableField("Cold email", text: shown.coldEmail, binding: $draft.coldEmail, multiline: true)
                    editableField("In-person opener", text: shown.inPersonOpener, binding: $draft.inPersonOpener, multiline: true)
                } else {
                    generateButton(memory)
                    Text("Generate a mission-aware LinkedIn DM, cold email, and in-person opener.")
                        .font(.caption).foregroundStyle(Theme.textTertiary)
                }
            }
        }
    }

    private func outreachControls(_ memory: ScanMemoryDTO) -> some View {
        HStack(spacing: 8) {
            Button {
                if editing {
                    saveEdits(memory)
                } else {
                    draft = memory.effectiveOutreach ?? draft
                    editing = true
                }
            } label: {
                Label(editing ? "Done" : "Edit", systemImage: editing ? "checkmark" : "pencil")
                    .font(.caption.weight(.bold)).foregroundStyle(Theme.textPrimary)
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .background(Theme.surfaceStrong, in: Capsule())
            }
            .buttonStyle(.plain)

            Button { Task { await appModel.generateOutreach(memoryId: memory.id) } } label: {
                Image(systemName: appModel.isGeneratingOutreach ? "arrow.triangle.2.circlepath" : "sparkles")
                    .font(.caption.weight(.bold)).foregroundStyle(Theme.textSecondary)
                    .frame(width: 34, height: 34)
                    .background(Theme.surface, in: Circle())
            }
            .buttonStyle(.plain)
            .disabled(appModel.isGeneratingOutreach || editing)
            .accessibilityLabel("Regenerate outreach")

            Spacer()
            sendButton(memory)
        }
    }

    private func sendButton(_ memory: ScanMemoryDTO) -> some View {
        Group {
            if memory.isSent {
                Label("Sent", systemImage: "checkmark.circle.fill")
                    .font(.caption.weight(.bold)).foregroundStyle(.black)
                    .padding(.horizontal, 14).padding(.vertical, 9)
                    .background(LeadStyle.sent, in: Capsule())
                    .transition(.scale.combined(with: .opacity))
            } else {
                Button { send(memory) } label: {
                    HStack(spacing: 6) {
                        if sending { ProgressView().tint(.black) }
                        else { Image(systemName: "paperplane.fill") }
                        Text(sending ? "Sending…" : "Send")
                    }
                    .font(.caption.weight(.bold)).foregroundStyle(.black)
                    .padding(.horizontal, 14).padding(.vertical, 9)
                    .background(Theme.accent, in: Capsule())
                }
                .buttonStyle(.plain)
                .disabled(sending)
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.7), value: memory.isSent)
    }

    private func editableField(_ title: String, text: String, binding: Binding<String>, multiline: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title.uppercased()).font(.caption2.weight(.bold)).foregroundStyle(Theme.textTertiary)
                Spacer()
                Button {
                    UIPasteboard.general.string = text
                    withAnimation(.easeOut(duration: 0.15)) { copiedLabel = title }
                } label: {
                    Image(systemName: copiedLabel == title ? "checkmark" : "doc.on.doc")
                        .font(.caption.weight(.bold)).foregroundStyle(Theme.textSecondary)
                        .frame(width: 28, height: 28).background(Theme.surface, in: Circle())
                }
                .accessibilityLabel("Copy \(title)")
            }
            if editing {
                Group {
                    if multiline {
                        TextEditor(text: binding)
                            .frame(minHeight: 64)
                            .scrollContentBackground(.hidden)
                    } else {
                        TextField("", text: binding, axis: .vertical)
                    }
                }
                .font(.caption).foregroundStyle(Theme.textPrimary)
                .padding(8)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Theme.accent.opacity(0.4), lineWidth: 1))
            } else {
                Text(text)
                    .font(.caption).foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(12)
        .glassCard(corner: 12)
    }

    private func generateButton(_ memory: ScanMemoryDTO) -> some View {
        Button { Task { await appModel.generateOutreach(memoryId: memory.id) } } label: {
            HStack {
                if appModel.isGeneratingOutreach { ProgressView().tint(.black) }
                else { Image(systemName: "sparkles") }
                Text("Generate follow-up")
            }
            .font(.caption.weight(.bold)).foregroundStyle(.black)
            .frame(maxWidth: .infinity).padding(.vertical, 12)
            .background(Theme.accent, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .disabled(appModel.isGeneratingOutreach)
    }

    private func statusChip(_ status: FollowUpStatus) -> some View {
        let sent = status == .sent
        return Label(status.label, systemImage: sent ? "checkmark.seal.fill" : "circle.dashed")
            .font(.caption2.weight(.bold))
            .foregroundStyle(sent ? LeadStyle.sent : Theme.textTertiary)
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background((sent ? LeadStyle.sent : Theme.textTertiary).opacity(0.14), in: Capsule())
    }

    // MARK: - Actions

    private func saveEdits(_ memory: ScanMemoryDTO) {
        editing = false
        Task { await appModel.updateFollowUpStatus(id: memory.id, status: .edited, editedOutreach: draft) }
    }

    /// Fake send: a short animated delay, then mark the memory sent. No email or
    /// LinkedIn message is ever actually sent.
    private func send(_ memory: ScanMemoryDTO) {
        let edited = editing ? draft : nil
        sending = true
        Task {
            try? await Task.sleep(for: .milliseconds(850))
            await appModel.updateFollowUpStatus(id: memory.id, status: .sent, editedOutreach: edited)
            editing = false
            sending = false
        }
    }

    // MARK: - Helpers

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .font(.caption2.weight(.bold)).foregroundStyle(Theme.textTertiary)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func nextActionLabel(_ memory: ScanMemoryDTO) -> String? {
        guard let raw = memory.nextAction else { return nil }
        return PreferredAction(rawValue: raw)?.label ?? raw
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
