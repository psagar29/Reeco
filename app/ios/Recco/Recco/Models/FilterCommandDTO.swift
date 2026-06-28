import Foundation

/// A filter/rank/reset/draft instruction. Mirrors `FilterCommand` from
/// `docs/API_CONTRACTS.md`. This is the single shape that voice, typed
/// commands, and manual chips all produce, so every input path funnels into
/// the same state update (`AppModel.apply(_:)`).
struct FilterCommandDTO: Codable, Equatable, Hashable {
    enum Action: String, Codable {
        case filter
        case rank
        case reset
        case draft
    }

    enum RankBy: String, Codable {
        case relevance
        case infra
        case growth
        case ai
        case founder
    }

    var action: Action
    var includeTags: [String]
    var excludeTags: [String]
    var rankBy: RankBy?
    var targetPersonId: String?
    var rawText: String?

    init(
        action: Action,
        includeTags: [String] = [],
        excludeTags: [String] = [],
        rankBy: RankBy? = nil,
        targetPersonId: String? = nil,
        rawText: String? = nil
    ) {
        self.action = action
        self.includeTags = includeTags
        self.excludeTags = excludeTags
        self.rankBy = rankBy
        self.targetPersonId = targetPersonId
        self.rawText = rawText
    }

    /// The neutral "show everyone" command.
    static let reset = FilterCommandDTO(action: .reset, rawText: "reset")

    /// Convenience filter for a single tag (used by manual chips).
    static func tag(_ tag: String) -> FilterCommandDTO {
        FilterCommandDTO(action: .filter, includeTags: [tag], rawText: "Only \(tag) people")
    }

    /// Human-readable summary for the transcript ribbon / status area.
    var summary: String {
        switch action {
        case .reset:
            return "Showing everyone"
        case .draft:
            return "Drafting opener"
        case .filter, .rank:
            if includeTags.isEmpty { return "Showing everyone" }
            let verb = action == .rank ? "Ranking by" : "Filtering"
            return "\(verb) \(includeTags.joined(separator: " + "))"
        }
    }
}
