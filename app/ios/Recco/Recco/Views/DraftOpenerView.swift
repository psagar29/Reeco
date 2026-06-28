import SwiftUI

/// Draft opener panel. Shows the generated opener sentence and an optional short
/// email, with a copy action and a stubbed "Sent" button. The draft comes from
/// `appModel.draft` (on-device in `mockAll`, backend `drafts:createOpener`
/// otherwise).
struct DraftOpenerView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.dismiss) private var dismiss
    let person: PersonDTO

    @State private var goal: String = ""
    @State private var didSend = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header

                // Optional goal to personalize the opener.
                VStack(alignment: .leading, spacing: 6) {
                    Text("YOUR GOAL (OPTIONAL)")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(Theme.textTertiary)
                    HStack {
                        TextField("e.g. raising a seed round", text: $goal)
                            .textFieldStyle(.plain)
                            .foregroundStyle(Theme.textPrimary)
                        Button {
                            Task { await appModel.draftOpener(for: person.id, userGoal: goal.isEmpty ? nil : goal) }
                        } label: {
                            Image(systemName: "arrow.clockwise.circle.fill")
                                .font(.title3)
                                .foregroundStyle(Theme.accent)
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .glassCard(corner: 12)
                }

                content
            }
            .padding(20)
        }
        .background(Theme.bg.opacity(0.4))
    }

    private var header: some View {
        HStack(spacing: 12) {
            AvatarView(person: person, size: 48)
            VStack(alignment: .leading, spacing: 2) {
                Text("Opener for \(person.firstName)")
                    .font(.headline)
                    .foregroundStyle(Theme.textPrimary)
                Text("\(person.role) · \(person.company)")
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
            }
            Spacer()
        }
    }

    @ViewBuilder private var content: some View {
        if appModel.isDrafting {
            HStack(spacing: 10) {
                ProgressView().tint(Theme.accent)
                Text("Writing a specific opener…")
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 24)
        } else if let draft = appModel.draft, draft.personId == person.id {
            draftCard(draft)
        } else {
            Text("Tap refresh to generate an opener.")
                .font(.subheadline)
                .foregroundStyle(Theme.textTertiary)
                .padding(.vertical, 24)
        }
    }

    private func draftCard(_ draft: DraftResultDTO) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            if let subject = draft.subject {
                labeled("SUBJECT") {
                    Text(subject).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.textPrimary)
                }
            }
            labeled("OPENER") {
                Text(draft.opener)
                    .font(.body)
                    .foregroundStyle(Theme.textPrimary)
            }
            if let email = draft.email {
                labeled("EMAIL") {
                    Text(email)
                        .font(.subheadline)
                        .foregroundStyle(Theme.textSecondary)
                }
            }

            HStack(spacing: 12) {
                Button {
                    UIPasteboard.general.string = draft.email ?? draft.opener
                } label: {
                    Label("Copy", systemImage: "doc.on.doc")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.textPrimary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .glassCard(corner: 14)
                }

                Button {
                    // Stub only — does not actually send anything.
                    withAnimation { didSend = true }
                } label: {
                    Label(didSend ? "Sent" : "Send", systemImage: didSend ? "checkmark" : "paperplane.fill")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(didSend ? Color.green : Theme.accent, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .disabled(didSend)
            }

            Text("“Sent” is a demo stub — no message actually leaves the device.")
                .font(.caption2)
                .foregroundStyle(Theme.textTertiary)
        }
        .padding(16)
        .glassCard()
    }

    private func labeled<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption2.weight(.bold))
                .foregroundStyle(Theme.textTertiary)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
