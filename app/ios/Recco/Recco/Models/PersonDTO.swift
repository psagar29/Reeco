import Foundation

/// Links block attached to a person. Matches the `Person.links` shape in
/// `docs/API_CONTRACTS.md`. All fields optional.
struct PersonLinksDTO: Codable, Equatable, Hashable {
    var github: String?
    var linkedin: String?
    var x: String?
    var site: String?

    /// Ordered, display-ready list of the links that are actually present.
    var displayPairs: [(label: String, url: String)] {
        var pairs: [(String, String)] = []
        if let github { pairs.append(("GitHub", github)) }
        if let linkedin { pairs.append(("LinkedIn", linkedin)) }
        if let x { pairs.append(("X", x)) }
        if let site { pairs.append(("Website", site)) }
        return pairs
    }
}

/// A person on the event roster. Mirrors the frozen `Person` type from
/// `docs/API_CONTRACTS.md`. `faceEmbedding` is intentionally omitted because
/// iOS never needs it (server-side only). `enrollmentImagePath` is decoded
/// leniently because the sample JSON carries it.
struct PersonDTO: Identifiable, Codable, Equatable, Hashable {
    let id: String
    let name: String
    let role: String
    let company: String
    let avatarUrl: String?
    let bio: String
    let tags: [String]
    let links: PersonLinksDTO
    let whyTalk: String
    let openerSeed: String?
    /// Present in the demo roster fixture; unused by the app UI.
    let enrollmentImagePath: String?

    enum CodingKeys: String, CodingKey {
        case id, name, role, company, avatarUrl, bio, tags, links, whyTalk, openerSeed, enrollmentImagePath
    }

    init(
        id: String,
        name: String,
        role: String,
        company: String,
        avatarUrl: String? = nil,
        bio: String,
        tags: [String],
        links: PersonLinksDTO = .init(),
        whyTalk: String,
        openerSeed: String? = nil,
        enrollmentImagePath: String? = nil
    ) {
        self.id = id
        self.name = name
        self.role = role
        self.company = company
        self.avatarUrl = avatarUrl
        self.bio = bio
        self.tags = tags
        self.links = links
        self.whyTalk = whyTalk
        self.openerSeed = openerSeed
        self.enrollmentImagePath = enrollmentImagePath
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        role = try c.decode(String.self, forKey: .role)
        company = try c.decode(String.self, forKey: .company)
        avatarUrl = try c.decodeIfPresent(String.self, forKey: .avatarUrl)
        bio = try c.decode(String.self, forKey: .bio)
        tags = try c.decode([String].self, forKey: .tags)
        links = try c.decodeIfPresent(PersonLinksDTO.self, forKey: .links) ?? .init()
        whyTalk = try c.decode(String.self, forKey: .whyTalk)
        openerSeed = try c.decodeIfPresent(String.self, forKey: .openerSeed)
        enrollmentImagePath = try c.decodeIfPresent(String.self, forKey: .enrollmentImagePath)
    }

    /// First name, handy for openers and short labels.
    var firstName: String {
        name.split(separator: " ").first.map(String.init) ?? name
    }

    /// Initials for the avatar fallback circle.
    var initials: String {
        let parts = name.split(separator: " ")
        let letters = parts.prefix(2).compactMap { $0.first }
        return String(letters).uppercased()
    }
}
