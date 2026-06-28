import SwiftUI

/// Result sheet for "find info on him". Mirrors `ProfileSheetView`'s layout.
///
/// Shows the resolved person's name / role / company, LinkedIn + email when the
/// backend returned them, and a confidence badge. The badge is driven straight
/// off `result.confidenceLabel`, so it is only ever "Verified" when the backend
/// actually face-verified the candidate — the UI never upgrades it.
struct IdentityResultSheet: View {
    @Environment(AppModel.self) private var appModel
    let result: IdentityResolveResultDTO

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                statusBadge

                if let best = result.bestCandidate {
                    headerCard(best)
                    let pairs = contactPairs(best)
                    if !pairs.isEmpty {
                        section("Links & contact") { contactRow(pairs) }
                    }
                    if let headline = best.headline {
                        section("Headline") {
                            Text(headline)
                                .font(.subheadline)
                                .foregroundStyle(Theme.textSecondary)
                        }
                    }
                }

                if let clueLine {
                    section("Read from badge") {
                        Text(clueLine)
                            .font(.subheadline)
                            .foregroundStyle(Theme.textSecondary)
                    }
                }

                if result.bestCandidate == nil, let message = result.message {
                    section("Result") {
                        Text(message)
                            .font(.subheadline)
                            .foregroundStyle(Theme.textPrimary)
                    }
                }

                if !otherCandidates.isEmpty {
                    section("Other possibilities") {
                        VStack(spacing: 8) {
                            ForEach(otherCandidates) { other in
                                otherRow(other)
                            }
                        }
                    }
                }

                doneButton
            }
            .padding(20)
        }
        .background(Theme.bg.opacity(0.4))
    }

    // MARK: - Status

    private var statusColor: Color {
        switch result.status {
        case .verified: return .green
        case .possible: return Theme.accent
        case .notFound: return Theme.textTertiary
        case .needsClarification: return .orange
        case .error: return .red
        }
    }

    private var statusBadge: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: result.statusSymbol)
                Text(result.confidenceLabel.uppercased())
            }
            .font(.caption.weight(.bold))
            .foregroundStyle(statusColor)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(statusColor.opacity(0.16), in: Capsule())

            if let message = result.message, result.bestCandidate != nil {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(Theme.textSecondary)
            }
        }
    }

    // MARK: - Header

    private func headerCard(_ candidate: IdentityCandidateDTO) -> some View {
        HStack(spacing: 14) {
            CandidateAvatar(candidate: candidate, size: 68)
            VStack(alignment: .leading, spacing: 3) {
                Text(candidate.fullName)
                    .font(.title2.weight(.bold))
                    .foregroundStyle(Theme.textPrimary)
                if let role = candidate.role {
                    Text(role)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.accent)
                }
                if let company = candidate.company {
                    Text(company)
                        .font(.subheadline)
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            Spacer()
        }
    }

    // MARK: - Contact links

    /// (label, SF Symbol, URL string) for each present link/contact.
    private func contactPairs(_ candidate: IdentityCandidateDTO) -> [(label: String, icon: String, url: String)] {
        var pairs: [(String, String, String)] = []
        if let linkedin = candidate.linkedinUrl, !linkedin.isEmpty {
            pairs.append(("LinkedIn", "person.crop.square", linkedin))
        }
        if let email = candidate.email, !email.isEmpty {
            pairs.append(("Email", "envelope.fill", "mailto:\(email)"))
        }
        return pairs
    }

    private func contactRow(_ pairs: [(label: String, icon: String, url: String)]) -> some View {
        FlowLayout(spacing: 8, lineSpacing: 8) {
            ForEach(pairs, id: \.label) { pair in
                if let url = URL(string: pair.url) {
                    Link(destination: url) {
                        HStack(spacing: 5) {
                            Image(systemName: pair.icon)
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

    // MARK: - Other candidates

    private var otherCandidates: [IdentityCandidateDTO] {
        let bestId = result.bestCandidate?.candidateId
        return result.candidates.filter { $0.candidateId != bestId }.prefix(3).map { $0 }
    }

    private func otherRow(_ candidate: IdentityCandidateDTO) -> some View {
        HStack(spacing: 10) {
            CandidateAvatar(candidate: candidate, size: 34)
            VStack(alignment: .leading, spacing: 1) {
                Text(candidate.fullName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)
                if let line = candidate.roleCompany {
                    Text(line)
                        .font(.caption2)
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(1)
                }
            }
            Spacer()
            if let url = candidate.linkedinUrl, let link = URL(string: url) {
                Link(destination: link) {
                    Image(systemName: "arrow.up.right.square")
                        .foregroundStyle(Theme.accent)
                }
            }
        }
        .padding(10)
        .glassCard(corner: 12)
    }

    // MARK: - Clue + done

    private var clueLine: String? {
        guard let clue = result.clue else { return nil }
        if !clue.rawText.isEmpty { return clue.rawText }
        let parts = [clue.fullName, clue.role, clue.company, clue.school].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private var doneButton: some View {
        Button {
            appModel.clearIdentity()
        } label: {
            Text("Done")
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
}

/// Avatar for an identity candidate: async profile photo with an initials
/// fallback (candidates have no bundled PersonDTO, so `AvatarView` can't be
/// reused directly).
private struct CandidateAvatar: View {
    let candidate: IdentityCandidateDTO
    var size: CGFloat = 56

    var body: some View {
        ZStack {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [Theme.accent.opacity(0.9), Theme.accent.opacity(0.4)],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    )
                )
            Text(initials)
                .font(.system(size: size * 0.36, weight: .bold, design: .rounded))
                .foregroundStyle(.white)

            if let urlString = candidate.profilePhotoUrl,
               let url = URL(string: urlString),
               !urlString.contains("example.com") {
                AsyncImage(url: url) { phase in
                    if case .success(let image) = phase {
                        image.resizable().scaledToFill()
                    }
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay(Circle().strokeBorder(Color.white.opacity(0.15), lineWidth: 1))
    }

    private var initials: String {
        let parts = candidate.fullName.split(separator: " ")
        let letters = parts.prefix(2).compactMap { $0.first }
        return String(letters).uppercased()
    }
}
