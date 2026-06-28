import Foundation

/// The frozen tag vocabulary from `docs/API_CONTRACTS.md`. Voice/typed command
/// parsing maps free text into this fixed set.
enum TagVocabulary {
    static let all: [String] = [
        "AI", "Founder", "Infra", "Rust", "Python", "Design", "Growth",
        "DevTools", "ML", "Search", "Seed", "Backend", "Frontend",
        "Product", "GoToMarket", "Evaluation"
    ]

    /// Tags surfaced as manual chips in the control strip. A focused subset of
    /// the full vocabulary, per the Person D brief (plus Reset handled in UI).
    static let chipTags: [String] = ["AI", "Founder", "Infra", "Growth", "Design"]

    /// Canonical tag for a lowercased keyword, or nil. Includes a handful of
    /// natural-language synonyms so spoken/typed phrasing resolves cleanly.
    static func canonical(for keyword: String) -> String? {
        let k = keyword.lowercased().trimmingCharacters(in: .whitespacesAndPunctuation)
        if let direct = all.first(where: { $0.lowercased() == k }) { return direct }
        return synonyms[k]
    }

    /// Lowercased keyword -> canonical tag.
    private static let synonyms: [String: String] = [
        "founders": "Founder",
        "founder": "Founder",
        "infrastructure": "Infra",
        "infra": "Infra",
        "growth": "Growth",
        "marketing": "Growth",
        "gtm": "GoToMarket",
        "go-to-market": "GoToMarket",
        "design": "Design",
        "designer": "Design",
        "designers": "Design",
        "ux": "Design",
        "ai": "AI",
        "ml": "ML",
        "machine": "ML",
        "rust": "Rust",
        "python": "Python",
        "devtools": "DevTools",
        "tooling": "DevTools",
        "search": "Search",
        "retrieval": "Search",
        "rag": "Search",
        "seed": "Seed",
        "backend": "Backend",
        "frontend": "Frontend",
        "product": "Product",
        "eval": "Evaluation",
        "evals": "Evaluation",
        "evaluation": "Evaluation"
    ]
}

private extension CharacterSet {
    static let whitespacesAndPunctuation = CharacterSet.whitespacesAndNewlines
        .union(.punctuationCharacters)
}
