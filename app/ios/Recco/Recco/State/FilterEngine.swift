import Foundation

/// Pure function that turns a `FilterCommandDTO` + roster into the visible /
/// dimmed partition. This is the iOS mirror of the backend `state:setFilter`
/// recompute rule, used directly in `mockAll` and as the optimistic local
/// update in every mode. Keeping it pure makes it trivial to test and reason
/// about on stage.
enum FilterEngine {

    struct Partition: Equatable {
        var visible: [String]
        var dimmed: [String]
    }

    static func partition(people: [PersonDTO], command: FilterCommandDTO) -> Partition {
        switch command.action {
        case .reset:
            // Everyone visible, nobody dimmed.
            return Partition(visible: people.map(\.id), dimmed: [])

        case .draft:
            // Drafting doesn't change who's visible; caller preserves the prior
            // partition. Default to "all visible" if used standalone.
            return Partition(visible: people.map(\.id), dimmed: [])

        case .filter, .rank:
            let include = Set(command.includeTags)
            let exclude = Set(command.excludeTags)

            if include.isEmpty && exclude.isEmpty {
                return Partition(visible: people.map(\.id), dimmed: [])
            }

            var visible: [String] = []
            var dimmed: [String] = []
            for person in people {
                let tagSet = Set(person.tags)
                let hasExcluded = !tagSet.isDisjoint(with: exclude)
                // OR semantics (matches the backend `state:setFilter` rule):
                // visible if the person has ANY requested include tag — "AI
                // founders" surfaces everyone tagged AI or Founder — and no
                // excluded tag. Empty include means everyone (minus excludes).
                let hasAnyIncluded = include.isEmpty || !tagSet.isDisjoint(with: include)
                if hasAnyIncluded && !hasExcluded {
                    visible.append(person.id)
                } else {
                    dimmed.append(person.id)
                }
            }

            // For rank, order visible by how many include-tags they hit.
            if command.action == .rank, !include.isEmpty {
                visible.sort { lhs, rhs in
                    let l = matchCount(personId: lhs, people: people, include: include)
                    let r = matchCount(personId: rhs, people: people, include: include)
                    return l > r
                }
            }

            return Partition(visible: visible, dimmed: dimmed)
        }
    }

    private static func matchCount(personId: String, people: [PersonDTO], include: Set<String>) -> Int {
        guard let person = people.first(where: { $0.id == personId }) else { return 0 }
        return Set(person.tags).intersection(include).count
    }
}
