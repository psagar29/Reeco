import SwiftUI

/// Detail sheet for one Scout prospect: priority + score + reasons, contact
/// links, and an editable, single-channel follow-up with a fake "Mark sent".
/// Reads the prospect from `AppModel` by id so status/outreach updates re-render.
struct GTMProspectDetailView: View {
    @Environment(AppModel.self) private var appModel
    let prospectId: String

    @State private var channel: FollowUpChannel = .linkedinDm
    @State private var didSeed = false
    @State private var editing = false
    @State private var draft = OutreachDraftDTO(linkedinDm: "", coldEmailSubject: "", coldEmail: "", inPersonOpener: "")
    @State private var sending = false
    @State private var generating = false
    @State private var copied = false

    private var prospect: GTMProspectDTO? { appModel.gtmProspect(id: prospectId) }

    var body: some View {
        ScrollView {
            if let p = prospect {
                VStack(alignment: .leading, spacing: 18) {
                    header(p)
                    reasonsSection(p)
                    contactSection(p)
                    followUpSection(p)
                    if let error = appModel.gtmError {
                        Text(error).font(.caption).foregroundStyle(Color.red.opacity(0.85))
                    }
                }
                .padding(20)
                .onAppear { seed(p) }
            } else {
                VStack(spacing: 10) {
                    Image(systemName: "person.fill.questionmark").font(.title2)
                    Text("Prospect not found").font(.headline)
                }
                .foregroundStyle(Theme.textSecondary).frame(maxWidth: .infinity, minHeight: 240)
            }
        }
        .background(Theme.bg.opacity(0.45))
    }

    // MARK: - Header

    private func header(_ p: GTMProspectDTO) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                ZStack {
                    Circle().fill(Theme.surfaceStrong).frame(width: 54, height: 54)
                    Circle().strokeBorder(p.priority.color.opacity(0.9), lineWidth: 2).frame(width: 54, height: 54)
                    Text(p.initials).font(.system(size: 18, weight: .bold, design: .rounded)).foregroundStyle(Theme.textPrimary)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(p.displayName).font(.title3.weight(.bold)).foregroundStyle(Theme.textPrimary).lineLimit(2)
                    if let line = p.roleCompanyLine {
                        Text(line).font(.subheadline).foregroundStyle(Theme.textSecondary).lineLimit(2)
                    }
                    if let loc = p.location {
                        Label(loc, systemImage: "mappin.and.ellipse").font(.caption2).foregroundStyle(Theme.textTertiary)
                    }
                }
                Spacer(minLength: 6)
            }
            HStack(spacing: 8) {
                PriorityPill(priority: p.priority, sent: p.isSent)
                Text("\(Int(p.matchScore * 100))")
                    .font(.subheadline.weight(.bold).monospacedDigit()).foregroundStyle(Theme.textPrimary)
                + Text(" match").font(.caption2).foregroundStyle(Theme.textTertiary)
                Spacer()
                Text(p.source.uppercased())
                    .font(.system(size: 9, weight: .bold)).foregroundStyle(Theme.textTertiary)
                    .padding(.horizontal, 7).padding(.vertical, 3)
                    .background(Theme.surface, in: Capsule())
            }
        }
        .padding(16)
        .glassCard(corner: 16)
    }

    @ViewBuilder private func reasonsSection(_ p: GTMProspectDTO) -> some View {
        if !p.reasons.isEmpty {
            section("Why they match") {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(p.reasons, id: \.self) { r in
                        Label {
                            Text(r).font(.caption).foregroundStyle(Theme.textSecondary)
                        } icon: {
                            Image(systemName: "checkmark.circle.fill").font(.caption2).foregroundStyle(p.priority.color)
                        }
                    }
                    if !p.missingInfo.isEmpty {
                        ForEach(p.missingInfo, id: \.self) { m in
                            Label {
                                Text(m).font(.caption).foregroundStyle(Theme.textTertiary)
                            } icon: {
                                Image(systemName: "exclamationmark.circle").font(.caption2).foregroundStyle(Theme.textTertiary)
                            }
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder private func contactSection(_ p: GTMProspectDTO) -> some View {
        let links = contactLinks(p)
        if !links.isEmpty {
            section("Contact") {
                FlowLayout(spacing: 8, lineSpacing: 8) {
                    ForEach(links, id: \.label) { item in
                        if let url = URL(string: item.url) {
                            Link(destination: url) {
                                Label(item.label, systemImage: item.icon)
                                    .font(.caption.weight(.semibold)).foregroundStyle(Theme.textPrimary)
                                    .padding(.horizontal, 12).padding(.vertical, 8).glassCard(corner: 12)
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Follow-up

    private func followUpSection(_ p: GTMProspectDTO) -> some View {
        section("Follow-up") {
            VStack(alignment: .leading, spacing: 10) {
                if p.outreach != nil {
                    channelSelector
                    draftCard(p)
                    controls(p)
                } else {
                    generateButton(p)
                    Text("Draft a LinkedIn DM, cold email, and in-person opener — then pick a channel.")
                        .font(.caption).foregroundStyle(Theme.textTertiary)
                }
            }
        }
    }

    private var channelSelector: some View {
        HStack(spacing: 4) {
            ForEach(FollowUpChannel.allCases) { ch in
                let active = channel == ch
                Button { withAnimation(.easeOut(duration: 0.18)) { channel = ch; editing = false } } label: {
                    HStack(spacing: 5) {
                        Image(systemName: ch.systemImage).font(.system(size: 11, weight: .semibold))
                        Text(ch.tabLabel).font(.caption.weight(.semibold)).lineLimit(1).minimumScaleFactor(0.8)
                    }
                    .foregroundStyle(active ? .black : Theme.textSecondary)
                    .frame(maxWidth: .infinity).padding(.vertical, 8)
                    .background(active ? AnyShapeStyle(Theme.accent) : AnyShapeStyle(.clear), in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4).background(Theme.surface, in: Capsule())
        .overlay(Capsule().strokeBorder(Theme.stroke, lineWidth: 1))
    }

    private func draftCard(_ p: GTMProspectDTO) -> some View {
        let current = p.outreach ?? draft
        let shown = editing ? draft : current
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(channel.tabLabel, systemImage: channel.systemImage)
                    .font(.caption2.weight(.bold)).foregroundStyle(Theme.textTertiary)
                Spacer()
                Button {
                    UIPasteboard.general.string = copyText(shown)
                    withAnimation(.easeOut(duration: 0.15)) { copied = true }
                } label: {
                    Image(systemName: copied ? "checkmark" : "doc.on.doc")
                        .font(.caption.weight(.bold)).foregroundStyle(Theme.textSecondary)
                        .frame(width: 28, height: 28).background(Theme.surface, in: Circle())
                }
                .accessibilityLabel("Copy")
            }
            if channel == .coldEmail {
                field("Subject", text: shown.coldEmailSubject, binding: $draft.coldEmailSubject, minHeight: 0, single: true)
                field("Body", text: shown.coldEmail, binding: $draft.coldEmail, minHeight: 110, single: false)
            } else {
                field(nil, text: bodyText(shown), binding: channelBinding, minHeight: 84, single: false)
            }
        }
        .padding(12).glassCard(corner: 12)
    }

    private var channelBinding: Binding<String> {
        switch channel {
        case .linkedinDm: return $draft.linkedinDm
        case .coldEmail: return $draft.coldEmail
        case .inPerson: return $draft.inPersonOpener
        }
    }

    @ViewBuilder private func field(_ label: String?, text: String, binding: Binding<String>, minHeight: CGFloat, single: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            if let label { Text(label.uppercased()).font(.system(size: 9, weight: .bold)).foregroundStyle(Theme.textTertiary) }
            if editing {
                Group {
                    if single { TextField("", text: binding, axis: .vertical) }
                    else { TextEditor(text: binding).frame(minHeight: minHeight).scrollContentBackground(.hidden) }
                }
                .font(.caption).foregroundStyle(Theme.textPrimary).padding(8)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Theme.accent.opacity(0.4), lineWidth: 1))
            } else {
                Text(text).font(.caption).foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true).frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func controls(_ p: GTMProspectDTO) -> some View {
        HStack(spacing: 8) {
            Button {
                if editing { saveEdits(p) } else { draft = p.outreach ?? draft; editing = true }
            } label: {
                Label(editing ? "Done" : "Edit", systemImage: editing ? "checkmark" : "pencil")
                    .font(.caption.weight(.bold)).foregroundStyle(Theme.textPrimary)
                    .padding(.horizontal, 12).padding(.vertical, 8).background(Theme.surfaceStrong, in: Capsule())
            }
            .buttonStyle(.plain)

            Button { regenerate(p) } label: {
                Image(systemName: generating ? "arrow.triangle.2.circlepath" : "sparkles")
                    .font(.caption.weight(.bold)).foregroundStyle(Theme.textSecondary)
                    .frame(width: 34, height: 34).background(Theme.surface, in: Circle())
            }
            .buttonStyle(.plain).disabled(generating || editing).accessibilityLabel("Regenerate")

            Spacer()
            sendButton(p)
        }
    }

    private func sendButton(_ p: GTMProspectDTO) -> some View {
        Group {
            if p.isSent {
                Label("Sent", systemImage: "checkmark.circle.fill")
                    .font(.caption.weight(.bold)).foregroundStyle(.black)
                    .padding(.horizontal, 13).padding(.vertical, 9)
                    .background(LeadStyle.sent, in: Capsule())
                    .transition(.scale.combined(with: .opacity))
            } else {
                Button { send(p) } label: {
                    HStack(spacing: 6) {
                        if sending { ProgressView().tint(.black) }
                        else { Image(systemName: channel == .inPerson ? "checkmark.circle.fill" : "paperplane.fill") }
                        Text(sending ? "Sending…" : sendLabel(channel))
                    }
                    .font(.caption.weight(.bold)).foregroundStyle(.black)
                    .padding(.horizontal, 13).padding(.vertical, 9).background(Theme.accent, in: Capsule())
                }
                .buttonStyle(.plain).disabled(sending)
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.7), value: p.isSent)
    }

    private func generateButton(_ p: GTMProspectDTO) -> some View {
        Button { regenerate(p) } label: {
            HStack {
                if generating { ProgressView().tint(.black) } else { Image(systemName: "sparkles") }
                Text("Draft follow-up")
            }
            .font(.caption.weight(.bold)).foregroundStyle(.black)
            .frame(maxWidth: .infinity).padding(.vertical, 12)
            .background(Theme.accent, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .disabled(generating)
    }

    // MARK: - Actions

    private func sendLabel(_ ch: FollowUpChannel) -> String {
        switch ch {
        case .linkedinDm: return "Mark LinkedIn sent"
        case .coldEmail: return "Mark email sent"
        case .inPerson: return "Mark opener used"
        }
    }

    private func saveEdits(_ p: GTMProspectDTO) {
        editing = false
        Task { await appModel.updateGTMProspectStatus(id: p.id, status: .drafted, channel: channel, editedOutreach: draft) }
    }

    private func regenerate(_ p: GTMProspectDTO) {
        generating = true
        Task {
            await appModel.generateGTMOutreach(prospectId: p.id)
            if let fresh = appModel.gtmProspect(id: p.id)?.outreach { draft = fresh }
            generating = false
        }
    }

    /// Fake send — short animation, then mark sent via the chosen channel. No
    /// real message is sent.
    private func send(_ p: GTMProspectDTO) {
        let finalText = editing ? draft : p.outreach
        sending = true
        Task {
            try? await Task.sleep(for: .milliseconds(850))
            await appModel.updateGTMProspectStatus(id: p.id, status: .sent, channel: channel, editedOutreach: finalText)
            editing = false
            sending = false
        }
    }

    // MARK: - Helpers

    private func seed(_ p: GTMProspectDTO) {
        guard !didSeed else { return }
        channel = p.selectedChannel ?? FollowUpChannel.from(action: p.preferredActionGuess)
        if let o = p.outreach { draft = o }
        didSeed = true
    }

    private func bodyText(_ o: OutreachDraftDTO) -> String {
        switch channel {
        case .linkedinDm: return o.linkedinDm
        case .coldEmail: return o.coldEmail
        case .inPerson: return o.inPersonOpener
        }
    }

    private func copyText(_ o: OutreachDraftDTO) -> String {
        switch channel {
        case .coldEmail: return "Subject: \(o.coldEmailSubject)\n\n\(o.coldEmail)"
        default: return bodyText(o)
        }
    }

    private func contactLinks(_ p: GTMProspectDTO) -> [(label: String, icon: String, url: String)] {
        var links: [(String, String, String)] = []
        if let l = p.linkedinUrl, !l.isEmpty { links.append(("LinkedIn", "person.crop.square", l)) }
        if let e = p.email, !e.isEmpty { links.append(("Email", "envelope", "mailto:\(e)")) }
        return links
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased()).font(.caption2.weight(.bold)).foregroundStyle(Theme.textTertiary)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private extension GTMProspectDTO {
    /// A reasonable default channel when the prospect has no chosen one: prefer
    /// LinkedIn when present, else email, else in-person.
    var preferredActionGuess: PreferredAction {
        if hasLinkedIn { return .linkedinDm }
        if hasEmail { return .coldEmail }
        return .inPerson
    }
}
