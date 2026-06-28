import Foundation

/// A generated opener / email draft. Mirrors `DraftResult` from
/// `docs/API_CONTRACTS.md`.
struct DraftResultDTO: Codable, Equatable, Hashable, Identifiable {
    let personId: String
    let subject: String?
    let opener: String
    let email: String?
    let generatedAt: Double

    var id: String { "\(personId)-\(generatedAt)" }

    init(
        personId: String,
        subject: String? = nil,
        opener: String,
        email: String? = nil,
        generatedAt: Double = Date().timeIntervalSince1970 * 1000
    ) {
        self.personId = personId
        self.subject = subject
        self.opener = opener
        self.email = email
        self.generatedAt = generatedAt
    }
}
