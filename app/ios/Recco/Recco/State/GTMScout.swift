import Foundation

/// On-device mirror of the backend GTM intent parser + prospect generator, used
/// by `MockBackend` so Scout Mode is fully demoable offline (DEMO_MODE=mockAll).
/// Reuses `MissionParser` (goal/keywords/industries) and `LeadScorer` (priority).
enum GTMScout {

    // MARK: - Intent

    private static let roleRegex = try? NSRegularExpression(
        pattern: "\\b((?:senior|staff|lead|principal|junior|swift|ios|android|backend|front[\\s-]?end|full[\\s-]?stack|ml|ai|infra|infrastructure|growth|product|platform|data|devrel|startup|technical|early[\\s-]?stage)\\s+)?(engineers?|developers?|designers?|founders?|recruiters?|investors?|partners?|marketers?|managers?|operators?|scientists?|researchers?|ctos?|ceos?|pms?|advisors?)\\b",
        options: [.caseInsensitive]
    )

    static func extractRoles(_ text: String) -> [String] {
        guard let regex = roleRegex else { return [] }
        let ns = text as NSString
        var out: [String] = []
        for m in regex.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            let phrase = ns.substring(with: m.range)
                .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
                .trimmingCharacters(in: .whitespaces)
                .lowercased()
            guard !phrase.isEmpty else { continue }
            out.append(phrase.hasSuffix("s") ? String(phrase.dropLast()) : phrase)
        }
        return Array(Set(out))
    }

    static func countFromText(_ text: String) -> Int? {
        guard let r = text.range(of: "\\b\\d{1,2}\\b", options: .regularExpression) else { return nil }
        return Int(text[r])
    }

    static func clampCount(_ n: Int?) -> Int { max(3, min(12, n ?? 8)) }

    private static func mapGoal(_ g: MissionGoalType) -> String {
        switch g {
        case .fundraising: return "fundraising"
        case .hiring, .getHired: return "hiring"
        case .customers: return "customers"
        case .sponsors: return "sponsors"
        case .cofounder, .founders: return "founders"
        case .networking: return "networking"
        case .other: return "other"
        }
    }

    static func parseIntent(_ transcript: String, count: Int?) -> GTMIntentDTO {
        let text = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        let mission = MissionParser.parse(text)
        let extracted = extractRoles(text)
        let roles = extracted.isEmpty ? mission.targetRoles : extracted
        let resolvedCount = clampCount(count ?? countFromText(text))
        let goal = mapGoal(mission.goalType)

        let roleList = Array(roles.prefix(3))
        let industries = Array(mission.targetIndustries.prefix(2))
        let query: String
        if !roleList.isEmpty {
            query = "Find " + roleList.joined(separator: " / ") + (industries.isEmpty ? "" : " in " + industries.joined(separator: " / "))
        } else if !industries.isEmpty {
            query = "Find people in " + industries.joined(separator: " / ")
        } else {
            query = text.isEmpty ? "Find relevant people to connect with" : text
        }

        return GTMIntentDTO(
            rawText: text.isEmpty ? "Find relevant people" : text,
            goalType: goal,
            searchQuery: query,
            targetRoles: roles,
            targetKeywords: Array(Set(mission.targetKeywords + mission.targetIndustries)),
            targetCompanies: [],
            targetIndustries: mission.targetIndustries,
            count: resolvedCount,
            preferredAction: mission.preferredAction
        )
    }

    // MARK: - Scoring (reuses LeadScorer)

    private static func mission(from intent: GTMIntentDTO, now: Double) -> MissionProfileDTO {
        let goal = MissionGoalType(rawValue: intent.goalType) ?? .other
        return MissionProfileDTO(
            rawText: intent.rawText, goalType: goal,
            targetRoles: intent.targetRoles, targetKeywords: intent.targetKeywords,
            targetCompanies: intent.targetCompanies, targetIndustries: intent.targetIndustries,
            preferredAction: intent.preferredAction, createdAt: now, updatedAt: now
        )
    }

    static func score(_ prospect: GTMProspectDTO, intent: GTMIntentDTO, now: Double) -> (LeadPriority, [String], [String]) {
        let temp = ScanMemoryDTO(
            id: prospect.prospectId, scanId: prospect.prospectId, name: prospect.name,
            headline: prospect.headline, role: prospect.role, company: prospect.company,
            linkedinUrl: prospect.linkedinUrl, email: prospect.email,
            confidence: .possible, sources: [prospect.source], scanCount: 1
        )
        let r = LeadScorer.score(temp, mission: mission(from: intent, now: now), now: now)
        let reasons = r.reasons.map {
            $0.replacingOccurrences(of: "Matches target role:", with: "Matches requested role:")
              .replacingOccurrences(of: "Possible identity", with: "Found via search")
        }
        return (r.priority, reasons, r.missingInfo)
    }

    // MARK: - Mock prospects

    private static let names = [
        "Ava Shah", "Miles Carter", "Sam Rivera", "Priya Patel", "Diego Santos",
        "Lena Fischer", "Noah Kim", "Zoe Bennett", "Omar Haddad", "Grace Liu",
        "Ethan Brooks", "Maya Singh",
    ]
    private static let companies = [
        "Northwind", "Vela Labs", "Brightseed", "Orbital", "Lumen AI", "Foundry",
        "Atlas", "Kestrel", "Harbor", "Meridian", "Drift", "Cobalt",
    ]
    private static let locations = ["SF", "NYC", "London", "Berlin", "Toronto", "Austin"]

    private static func slug(_ s: String) -> String {
        s.lowercased().replacingOccurrences(of: "[^a-z0-9]+", with: "_", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "_"))
    }

    private static func defaultRole(_ goal: String) -> String {
        switch goal {
        case "hiring": return "engineer"
        case "fundraising": return "investor"
        case "customers": return "head of product"
        case "sponsors": return "head of partnerships"
        case "founders": return "founder"
        default: return "operator"
        }
    }

    /// Deterministic scored mock prospects for a run.
    static func mockProspects(intent: GTMIntentDTO, runId: String, clientId: String, now: Double) -> [GTMProspectDTO] {
        let roles = intent.targetRoles.isEmpty ? [defaultRole(intent.goalType)] : intent.targetRoles
        var out: [GTMProspectDTO] = []
        for i in 0..<intent.count {
            let name = names[i % names.count]
            let role = roles[i % roles.count].capitalized
            let company = companies[i % companies.count]
            let hasLinkedIn = i % 4 != 3
            let hasEmail = i % 5 < 2
            let linkedin = hasLinkedIn ? "https://www.linkedin.com/in/\(slug(name))-\(i)" : nil
            let email = hasEmail ? "\(name.split(separator: " ").first.map(String.init)?.lowercased() ?? "x")@\(company.lowercased().replacingOccurrences(of: " ", with: "")).com" : nil

            var prospect = GTMProspectDTO(
                id: "\(runId)_\(i)",
                runId: runId, clientId: clientId, prospectId: "gp_mock_\(i)_\(slug(name))",
                name: name, headline: "\(role) at \(company)", role: role, company: company,
                location: locations[i % locations.count], linkedinUrl: linkedin, email: email,
                source: "mock", matchScore: max(0.4, 0.95 - Double(i) * 0.05),
                createdAt: now, updatedAt: now
            )
            let (priority, reasons, missing) = score(prospect, intent: intent, now: now)
            let outreach = MockOutreach.draft(name: prospect.name, role: prospect.role, company: prospect.company, headline: prospect.headline, goalType: intent.goalType)
            prospect = GTMProspectDTO(
                id: prospect.id, runId: runId, clientId: clientId, prospectId: prospect.prospectId,
                name: prospect.name, headline: prospect.headline, role: prospect.role, company: prospect.company,
                location: prospect.location, linkedinUrl: prospect.linkedinUrl, email: prospect.email,
                source: "mock", matchScore: prospect.matchScore,
                priority: priority, reasons: reasons, missingInfo: missing,
                outreach: outreach, status: .drafted, createdAt: now, updatedAt: now
            )
            out.append(prospect)
        }
        return out.sorted { $0.matchScore > $1.matchScore }
    }
}

/// Tiny offline outreach builder shared by Scout mock generation (mirrors the
/// backend `buildOutreachOffline` + mission angle).
enum MockOutreach {
    static func angle(_ goal: String) -> String {
        switch goal {
        case "fundraising": return "I'd genuinely value your perspective as an investor as we shape our next round."
        case "hiring": return "We're growing the team and your background stood out."
        case "customers": return "Curious whether what we're building could be useful for your team."
        case "sponsors": return "Wondering if there might be a fit for a partnership down the line."
        case "founders": return "Always up for trading notes with other founders."
        default: return ""
        }
    }

    static func draft(name: String, role: String?, company: String?, headline: String?, goalType: String) -> OutreachDraftDTO {
        let fn = name.split(separator: " ").first.map(String.init) ?? "there"
        let topic = company ?? role ?? "what you're building"
        let a = angle(goalType)
        let dm = a.isEmpty ? "" : " \(a)"
        let em = a.isEmpty ? "" : "\(a)\n\n"
        return OutreachDraftDTO(
            linkedinDm: "Hey \(fn), came across your work\(company.map { " at \($0)" } ?? "").\(dm) We're building Recco, an AR memory layer for event networking — would love to connect.",
            coldEmailSubject: "Quick note from Recco",
            coldEmail: "Hey \(fn),\n\nI came across your work on \(topic) and thought I'd reach out.\n\n\(em)We're building Recco, a lightweight AR memory layer for event networking. Would love to compare notes.\n\nBest",
            inPersonOpener: "Hey \(fn) — I've been meaning to connect about your work on \(topic). Got a minute?"
        )
    }
}
