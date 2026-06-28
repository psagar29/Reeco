import Foundation

/// On-device mirror of the backend `lib/mission.ts` + `lib/leadScoring.ts`.
///
/// Two jobs:
///  - `MissionParser` parses free text into a `MissionProfileDTO` for the offline
///    (`mockAll`) backend.
///  - `LeadScorer` scores a memory against the active mission. `AppModel` runs it
///    on every loaded memory so the Brain reflects the *current* mission instantly
///    (seeded rows, mission edits) without a per-row backend round-trip — the live
///    backend scores authoritatively on upsert; this keeps the UI consistent.
///
/// Deterministic by contract: same memory + mission ⇒ same priority.
enum MissionParser {

    private struct GoalRule {
        let goalType: MissionGoalType
        let match: [String]
        let roles: [String]
        let keywords: [String]
        let action: PreferredAction
    }

    private static let rules: [GoalRule] = [
        GoalRule(goalType: .getHired,
                 match: ["get hired", "getting hired", "looking for a job", "find a job", "get a job", "looking for work", "land a role", "find a role", "job hunting"],
                 roles: ["recruiter", "hiring manager", "engineering manager", "founder", "head of talent"],
                 keywords: ["hiring", "recruiting", "open roles", "talent"], action: .linkedinDm),
        GoalRule(goalType: .fundraising,
                 match: ["investor", "raise", "raising", "fundrais", "venture", "vc", "angel", "seed round", "pre-seed", "capital"],
                 roles: ["investor", "partner", "angel", "venture partner", "general partner"],
                 keywords: ["venture", "seed", "fund", "capital", "angel", "portfolio"], action: .linkedinDm),
        GoalRule(goalType: .cofounder,
                 match: ["cofounder", "co-founder", "co founder", "technical cofounder"],
                 roles: ["founder", "engineer", "cto", "co-founder"],
                 keywords: ["cofounder", "founding", "startup", "build"], action: .inPerson),
        GoalRule(goalType: .sponsors,
                 match: ["sponsor", "sponsorship", "partnership", "community", "devrel", "developer relations"],
                 roles: ["sponsor", "partnerships", "community", "devrel", "marketing"],
                 keywords: ["sponsorship", "partnership", "community", "brand", "budget"], action: .coldEmail),
        GoalRule(goalType: .hiring,
                 match: ["hiring", "hire ", "recruit", "looking to hire", "find engineers", "find talent", "build my team", "grow my team"],
                 roles: ["engineer", "designer", "candidate", "operator"],
                 keywords: ["hiring", "open to work", "candidate"], action: .linkedinDm),
        GoalRule(goalType: .customers,
                 match: ["customer", "clients", "design partner", "pilot", "users", "sell", "go to market", "leads"],
                 roles: ["founder", "head of", "vp", "director", "product lead", "operator"],
                 keywords: ["product", "pilot", "customer", "budget", "team"], action: .coldEmail),
        GoalRule(goalType: .founders,
                 match: ["founder", "startup founders", "find founders", "meet founders", "early stage"],
                 roles: ["founder", "ceo", "co-founder", "cto"],
                 keywords: ["startup", "founder", "building", "early stage"], action: .linkedinDm),
        GoalRule(goalType: .networking,
                 match: ["network", "meet people", "make friends", "connections", "general"],
                 roles: [], keywords: [], action: .inPerson),
    ]

    private static let industryKeywords: [String: [String]] = [
        "ai": ["ai", "artificial intelligence", "ml", "machine learning", "llm"],
        "infra": ["infra", "infrastructure", "devops", "platform", "cloud"],
        "fintech": ["fintech", "payments", "banking", "finance"],
        "health": ["health", "healthcare", "biotech", "medical"],
        "climate": ["climate", "energy", "sustainability", "cleantech"],
        "crypto": ["crypto", "web3", "blockchain", "defi"],
        "devtools": ["devtools", "developer tools", "sdk"],
        "data": ["data", "analytics", "database"],
        "security": ["security", "cyber", "infosec"],
        "design": ["design", "ux", "ui"],
        "hardware": ["hardware", "robotics", "devices", "chips"],
        "saas": ["saas", "b2b", "enterprise software"],
    ]

    /// Word-boundary-aware contains, so "fundraising" doesn't match "ai".
    private static func hit(_ text: String, _ needle: String) -> Bool {
        if needle.count <= 3 || needle.contains(where: { !$0.isLetter }) {
            let escaped = NSRegularExpression.escapedPattern(for: needle)
            let pattern = "(^|[^a-z])\(escaped)([^a-z]|$)"
            return text.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
        }
        return text.contains(needle)
    }

    static func detectIndustries(_ text: String) -> [String] {
        let lower = text.lowercased()
        return industryKeywords.compactMap { key, needles in
            needles.contains(where: { hit(lower, $0) }) ? key : nil
        }.sorted()
    }

    static func parse(_ rawText: String, now: Double = Date().timeIntervalSince1970 * 1000) -> MissionProfileDTO {
        let text = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = text.lowercased()
        let rule = text.isEmpty
            ? rules.first { $0.goalType == .networking }
            : rules.first { r in r.match.contains { lower.contains($0) } }
        let resolved = rule ?? rules.first { $0.goalType == .networking }!
        let industries = detectIndustries(lower)

        return MissionProfileDTO(
            rawText: text.isEmpty ? "General networking" : text,
            goalType: resolved.goalType,
            targetRoles: resolved.roles,
            targetKeywords: Array(Set(resolved.keywords + industries)).sorted(),
            targetCompanies: [],
            targetIndustries: industries,
            preferredAction: resolved.action,
            tone: "warm, concise, specific",
            createdAt: now,
            updatedAt: now
        )
    }
}

/// The result of scoring one memory.
struct LeadResult: Equatable {
    let priority: LeadPriority
    let score: Double
    let reasons: [String]
    let nextAction: PreferredAction
    let missingInfo: [String]
}

enum LeadScorer {

    private static let highPriorityCues = [
        "high priority", "must follow", "follow up", "important", "key contact",
        "priority", "great fit", "perfect fit", "love to", "definitely", "top of list",
    ]
    private static let notRelevantCues = [
        "not relevant", "not a fit", "ignore", "skip", "no thanks", "not interested", "irrelevant", "archive",
    ]

    private static let goalSignals: [MissionGoalType: (needles: [String], points: Double, reason: String)] = [
        .fundraising: (["investor", "venture", "vc", "partner", "angel", "capital", "fund"], 35, "Matches your investor mission"),
        .getHired: (["recruiter", "hiring", "talent", "people ops", "engineering manager", "head of"], 35, "Recruiter / hiring signal — matches your search"),
        .sponsors: (["sponsor", "partnership", "partnerships", "community", "devrel", "brand", "marketing"], 30, "Sponsorship / partnerships match"),
    ]
    private static let founderNeedles = ["founder", "co-founder", "cofounder", "ceo", "cto"]
    private static let founderGoals: Set<MissionGoalType> = [.fundraising, .customers, .founders, .cofounder]

    static func score(_ m: ScanMemoryDTO, mission: MissionProfileDTO?, now: Double = Date().timeIntervalSince1970 * 1000) -> LeadResult {
        var reasons: [String] = []
        var missing: [String] = []
        var score = 0.0

        let hasLinkedIn = m.hasLinkedIn
        let hasEmail = (m.email?.trimmingCharacters(in: .whitespaces).isEmpty == false)
        let hasName = (m.name?.trimmingCharacters(in: .whitespaces).isEmpty == false)

        switch m.confidence {
        case .verified: score += 20; reasons.append("Verified identity")
        case .possible: score += 8; reasons.append("Possible identity")
        case .needsConfirmation: score -= 15; reasons.append("Needs confirmation before follow-up")
        case .unknown: break
        }
        if hasLinkedIn { score += 15; reasons.append("LinkedIn profile found") }
        if hasEmail { score += 10; reasons.append("Email found") }
        if m.scanCount > 1 { score += 5; reasons.append("Scanned \(m.scanCount) times") }
        if (m.notes?.trimmingCharacters(in: .whitespaces).isEmpty == false) { score += 8; reasons.append("You added notes") }

        let haystack = [m.role, m.headline, m.company, m.school, m.badgeText]
            .compactMap { $0?.lowercased() }.joined(separator: " ")

        if let mission {
            if let role = mission.targetRoles.first(where: { !$0.isEmpty && haystack.contains($0.lowercased()) }) {
                score += 25; reasons.append("Matches target role: \(role)")
            }
            if let kw = mission.targetKeywords.first(where: { !$0.isEmpty && haystack.contains($0.lowercased()) }) {
                score += 20; reasons.append("Keyword match: \(kw)")
            }
            if let company = mission.targetCompanies.first(where: { !$0.isEmpty && haystack.contains($0.lowercased()) }) {
                score += 15; reasons.append("Target company: \(company)")
            }
            if let industry = mission.targetIndustries.first(where: { !$0.isEmpty && haystack.contains($0.lowercased()) }) {
                score += 15; reasons.append("Industry match: \(industry)")
            }
            if let signal = goalSignals[mission.goalType], signal.needles.contains(where: { haystack.contains($0) }) {
                score += signal.points; reasons.append(signal.reason)
            }
            if founderGoals.contains(mission.goalType), founderNeedles.contains(where: { haystack.contains($0) }) {
                score += 15; reasons.append("Founder keyword in headline")
            }
        }

        let intent = "\(m.notes ?? "")".lowercased()
        let flaggedNotRelevant = notRelevantCues.contains { intent.contains($0) }
        let flaggedHigh = highPriorityCues.contains { intent.contains($0) }
        if flaggedHigh && !flaggedNotRelevant { score += 30; reasons.append("You flagged this as high priority") }

        if !hasName { missing.append("No name resolved") }
        if !hasLinkedIn && !hasEmail { missing.append("No contact link found") }
        if m.confidence == .needsConfirmation || m.confidence == .unknown { missing.append("Identity needs confirmation") }

        let clamped = min(100, max(0, score.rounded()))

        let priority: LeadPriority
        if flaggedNotRelevant {
            priority = .cold; reasons.append("Marked not relevant — suggest archive")
        } else if clamped >= 75 {
            priority = .hot
        } else if clamped >= 45 {
            priority = .warm
        } else if clamped >= 15 {
            priority = .cold
        } else {
            priority = missing.isEmpty ? .cold : .needsInfo
        }
        if reasons.isEmpty { reasons.append("Not enough signal yet") }

        let nextAction = chooseAction(mission: mission, hasLinkedIn: hasLinkedIn, hasEmail: hasEmail, needsInfo: priority == .needsInfo)
        return LeadResult(priority: priority, score: clamped, reasons: reasons, nextAction: nextAction, missingInfo: missing)
    }

    private static func chooseAction(mission: MissionProfileDTO?, hasLinkedIn: Bool, hasEmail: Bool, needsInfo: Bool) -> PreferredAction {
        if needsInfo { return .reminder }
        if let mission {
            if mission.preferredAction == .linkedinDm && !hasLinkedIn && hasEmail { return .coldEmail }
            if mission.preferredAction == .coldEmail && !hasEmail && hasLinkedIn { return .linkedinDm }
            return mission.preferredAction
        }
        if hasLinkedIn { return .linkedinDm }
        if hasEmail { return .coldEmail }
        return .inPerson
    }
}
