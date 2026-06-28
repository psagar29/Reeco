import Foundation

/// On-device opener / email generator. This is the `mockAll` stand-in for the
/// backend `drafts:createOpener` action. It builds a short, specific, human
/// opener from the person's own data (tags, bio, openerSeed) — no fake claims.
enum OpenerGenerator {

    static func draft(for person: PersonDTO, userGoal: String? = nil) -> DraftResultDTO {
        let topic = primaryTopic(for: person)
        let opener = makeOpener(person: person, topic: topic, userGoal: userGoal)
        let email = makeEmail(person: person, opener: opener)
        let subject = "Quick question on \(topic.lowercased())"
        return DraftResultDTO(
            personId: person.id,
            subject: subject,
            opener: opener,
            email: email
        )
    }

    // MARK: - Building blocks

    /// A short topic phrase grounded in what the person actually does.
    private static func primaryTopic(for person: PersonDTO) -> String {
        if person.tags.contains("Infra") { return "infra" }
        if person.tags.contains("Growth") { return "growth" }
        if person.tags.contains("Design") { return "design" }
        if person.tags.contains("Search") || person.tags.contains("ML") { return "retrieval and evals" }
        if person.tags.contains("AI") { return "AI" }
        return person.tags.first ?? person.role
    }

    private static func makeOpener(person: PersonDTO, topic: String, userGoal: String?) -> String {
        // Prefer the curated seed when present — it's the most specific hook.
        if let seed = person.openerSeed, !seed.isEmpty {
            let hook = seed.prefix(1).lowercased() + seed.dropFirst()
            var line = "Hey \(person.firstName), I saw you're at \(person.company) working on \(person.bio.trimmingTrailingPeriod.lowercasedFirst). I'd love to \(hook)"
            if let goal = userGoal, !goal.isEmpty {
                line += " I'm currently focused on \(goal), so this feels timely."
            }
            return line.ensuringPeriod
        }

        var line = "Hey \(person.firstName), I saw you're working on \(person.bio.trimmingTrailingPeriod.lowercasedFirst). I'm curious what's been the hardest part of the \(topic) side so far."
        if let goal = userGoal, !goal.isEmpty {
            line += " I'm digging into \(goal) right now and would value your take."
        }
        return line
    }

    private static func makeEmail(person: PersonDTO, opener: String) -> String {
        """
        Hey \(person.firstName),

        \(opener)

        Would love to compare notes for a minute while we're both at the event.

        Thanks!
        """
    }
}

private extension String {
    var trimmingTrailingPeriod: String {
        hasSuffix(".") ? String(dropLast()) : self
    }

    var lowercasedFirst: String {
        isEmpty ? self : prefix(1).lowercased() + dropFirst()
    }

    var ensuringPeriod: String {
        let t = trimmingCharacters(in: .whitespaces)
        guard let last = t.last else { return t }
        return ".!?".contains(last) ? t : t + "."
    }
}
