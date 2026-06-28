import SwiftUI

/// Profile detail sheet. Opened from a camera overlay tap (Person C) or a Brain
/// node tap (Person D). Shows everything about a person and the "Draft opener"
/// entry point.
struct ProfileSheetView: View {
    @Environment(AppModel.self) private var appModel
    let person: PersonDTO
    @State private var showDraft = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                headerCard
                section("Why talk to \(person.firstName)") {
                    Text(person.whyTalk)
                        .font(.subheadline)
                        .foregroundStyle(Theme.textPrimary)
                }
                section("Bio") {
                    Text(person.bio)
                        .font(.subheadline)
                        .foregroundStyle(Theme.textSecondary)
                }
                section("Tags") {
                    FlowTags(tags: person.tags)
                }
                if !person.links.displayPairs.isEmpty {
                    section("Links") { linksRow }
                }
                draftButton
            }
            .padding(20)
        }
        .background(Theme.bg.opacity(0.4))
        .sheet(isPresented: $showDraft) {
            DraftOpenerView(person: person)
                .environment(appModel)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
                .presentationBackground(.ultraThinMaterial)
        }
    }

    // MARK: - Pieces

    private var headerCard: some View {
        HStack(spacing: 14) {
            AvatarView(person: person, size: 68)
            VStack(alignment: .leading, spacing: 3) {
                Text(person.name)
                    .font(.title2.weight(.bold))
                    .foregroundStyle(Theme.textPrimary)
                Text(person.role)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.accent)
                Text(person.company)
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
            }
            Spacer()
        }
    }

    private var linksRow: some View {
        FlowLayout(spacing: 8, lineSpacing: 8) {
            ForEach(person.links.displayPairs, id: \.label) { pair in
                if let url = URL(string: pair.url) {
                    Link(destination: url) {
                        HStack(spacing: 5) {
                            Image(systemName: icon(for: pair.label))
                            Text(pair.label)
                        }
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

    private var draftButton: some View {
        Button {
            showDraft = true
            Task { await appModel.draftOpener(for: person.id) }
        } label: {
            HStack {
                Image(systemName: "sparkles")
                Text("Draft opener")
            }
            .font(.headline)
            .foregroundStyle(.black)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(Theme.accent, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .padding(.top, 4)
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

    private func icon(for label: String) -> String {
        switch label {
        case "GitHub": return "chevron.left.forwardslash.chevron.right"
        case "LinkedIn": return "person.crop.square"
        case "X": return "at"
        default: return "link"
        }
    }
}
