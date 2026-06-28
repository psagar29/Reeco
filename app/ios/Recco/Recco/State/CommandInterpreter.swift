import Foundation

/// On-device natural-language → `FilterCommandDTO` parser. This is the
/// `mockAll` stand-in for the backend `voice:interpretCommand` action, and it
/// also powers the typed command bar in every mode so the demo never depends
/// on a network round-trip to feel responsive.
///
/// Deliberately simple keyword matching — predictable on stage beats clever.
enum CommandInterpreter {

    /// Parse a transcript into a command. `people` is used to resolve a draft
    /// target by name (e.g. "draft an opener for Ava").
    static func interpret(_ transcript: String, people: [PersonDTO]) -> FilterCommandDTO {
        let raw = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = raw.lowercased()

        // 1. Reset / clear.
        if matchesAny(lower, ["reset", "clear", "start over", "show everyone", "show all", "everybody"]) {
            return FilterCommandDTO(action: .reset, rawText: raw)
        }

        // 2. Draft an opener.
        if matchesAny(lower, ["draft", "opener", "write an intro", "intro for", "message for", "reach out"]) {
            let target = resolvePerson(in: lower, people: people)
            return FilterCommandDTO(
                action: .draft,
                targetPersonId: target?.id,
                rawText: raw
            )
        }

        // 3. Tags mentioned anywhere in the phrase.
        let tags = extractTags(from: lower)

        // 4. "Who should I talk to about X" / "rank" phrasing → rank action.
        let isRank = matchesAny(lower, ["who should i talk", "who do i talk", "who can help", "rank", "best person", "most relevant", "who should i meet"])
        if isRank {
            return FilterCommandDTO(
                action: .rank,
                includeTags: tags,
                rankBy: rankBy(for: tags),
                rawText: raw
            )
        }

        // 5. Default: a filter (covers "show me AI founders", "only growth people").
        if tags.isEmpty {
            // No recognizable intent — treat as reset rather than empty filter.
            return FilterCommandDTO(action: .reset, rawText: raw)
        }
        return FilterCommandDTO(
            action: .filter,
            includeTags: tags,
            rankBy: .relevance,
            rawText: raw
        )
    }

    // MARK: - Helpers

    private static func matchesAny(_ haystack: String, _ needles: [String]) -> Bool {
        needles.contains { haystack.contains($0) }
    }

    /// Pull canonical tags out of a phrase, preserving first-seen order and
    /// dropping duplicates.
    private static func extractTags(from lower: String) -> [String] {
        let tokens = lower.split { !$0.isLetter && !$0.isNumber }.map(String.init)
        var seen = Set<String>()
        var result: [String] = []
        for token in tokens {
            if let tag = TagVocabulary.canonical(for: token), !seen.contains(tag) {
                seen.insert(tag)
                result.append(tag)
            }
        }
        return result
    }

    private static func rankBy(for tags: [String]) -> FilterCommandDTO.RankBy {
        if tags.contains("Infra") { return .infra }
        if tags.contains("Growth") { return .growth }
        if tags.contains("AI") { return .ai }
        if tags.contains("Founder") { return .founder }
        return .relevance
    }

    /// Find a roster person referenced by first name or full name in the text.
    private static func resolvePerson(in lower: String, people: [PersonDTO]) -> PersonDTO? {
        // Prefer a full-name hit, then a first-name hit.
        if let full = people.first(where: { lower.contains($0.name.lowercased()) }) {
            return full
        }
        return people.first { lower.contains($0.firstName.lowercased()) }
    }
}
