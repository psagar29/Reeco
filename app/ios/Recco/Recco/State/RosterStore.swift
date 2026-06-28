import Foundation

/// Loads the demo roster from the bundled `people.sample.json`. Falls back to a
/// small hard-coded roster if the resource is missing for any reason, so the
/// app is never empty on stage.
enum RosterStore {

    static func loadBundledPeople() -> [PersonDTO] {
        guard let url = Bundle.main.url(forResource: "people.sample", withExtension: "json") else {
            return fallbackPeople
        }
        do {
            let data = try Data(contentsOf: url)
            let people = try JSONDecoder().decode([PersonDTO].self, from: data)
            return people.isEmpty ? fallbackPeople : people
        } catch {
            print("[RosterStore] Failed to decode people.sample.json: \(error). Using fallback.")
            return fallbackPeople
        }
    }

    /// Minimal in-code roster mirroring the fixture, used only if the bundled
    /// JSON can't be read. Keeps the demo alive no matter what.
    static let fallbackPeople: [PersonDTO] = [
        PersonDTO(
            id: "person_ava_shah", name: "Ava Shah", role: "Founder", company: "VectorKit",
            bio: "Building infra for multimodal AI agents.",
            tags: ["AI", "Founder", "Infra", "Seed", "Python"],
            links: PersonLinksDTO(github: "https://github.com/ava-demo", linkedin: "https://linkedin.com/in/ava-demo", x: "https://x.com/ava_demo"),
            whyTalk: "Ava is useful if you want to discuss AI infra, agent memory, or seed-stage founder problems.",
            openerSeed: "Ask about the hardest latency issue in multimodal agent infra."
        ),
        PersonDTO(
            id: "person_miles_chen", name: "Miles Chen", role: "Engineer", company: "Runloop",
            bio: "Systems engineer working on Rust services and developer tooling.",
            tags: ["Rust", "Infra", "DevTools", "Backend"],
            links: PersonLinksDTO(github: "https://github.com/miles-demo", linkedin: "https://linkedin.com/in/miles-demo"),
            whyTalk: "Miles is a strong match for low-level infra, Rust, and developer workflow conversations.",
            openerSeed: "Ask what Rust tooling still feels too painful for startup teams."
        ),
        PersonDTO(
            id: "person_sam_rivera", name: "Sam Rivera", role: "Growth Lead", company: "LaunchPad",
            bio: "Growth operator helping technical founders find first users.",
            tags: ["Growth", "Founder", "GoToMarket", "Seed"],
            links: PersonLinksDTO(github: "https://github.com/sam-demo", linkedin: "https://linkedin.com/in/sam-demo", x: "https://x.com/sam_demo"),
            whyTalk: "Sam is the right person for founder-led growth, early user acquisition, and positioning.",
            openerSeed: "Ask what channel is working for technical founders right now."
        ),
        PersonDTO(
            id: "person_nina_park", name: "Nina Park", role: "Designer", company: "Northstar",
            bio: "Designs AI-native interfaces for prosumer tools.",
            tags: ["Design", "AI", "Product", "Frontend"],
            links: PersonLinksDTO(github: "https://github.com/nina-demo", linkedin: "https://linkedin.com/in/nina-demo"),
            whyTalk: "Nina can help with interaction design, AI UX, and making demos feel obvious.",
            openerSeed: "Ask how she decides when an AI interface should be chat, canvas, or direct manipulation."
        ),
        PersonDTO(
            id: "person_omar_wilson", name: "Omar Wilson", role: "ML Engineer", company: "Searchlight",
            bio: "Works on retrieval, ranking, and evaluation pipelines.",
            tags: ["AI", "Search", "ML", "Evaluation", "Python"],
            links: PersonLinksDTO(github: "https://github.com/omar-demo", linkedin: "https://linkedin.com/in/omar-demo"),
            whyTalk: "Omar is useful for RAG, ranking quality, evals, and search infrastructure.",
            openerSeed: "Ask what evaluation signal he trusts most for retrieval quality."
        )
    ]
}
