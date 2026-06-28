import Foundation

/// "Lazy GTM / Scout Mode" DTOs. AI-found prospects from a voice/text request —
/// kept conceptually separate from `ScanMemoryDTO` (real people the user met).
/// All decoding is lenient so a partial/older backend payload never crashes.

// MARK: - Intent

/// A parsed Scout request. Mirrors the backend `GTMIntent`.
struct GTMIntentDTO: Codable, Equatable, Hashable {
    var rawText: String
    var goalType: String
    var searchQuery: String
    var targetRoles: [String]
    var targetKeywords: [String]
    var targetCompanies: [String]
    var targetIndustries: [String]
    var count: Int
    var preferredAction: PreferredAction

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        rawText = (try? c.decode(String.self, forKey: .rawText)) ?? ""
        goalType = (try? c.decode(String.self, forKey: .goalType)) ?? "other"
        searchQuery = (try? c.decode(String.self, forKey: .searchQuery)) ?? ""
        targetRoles = (try? c.decode([String].self, forKey: .targetRoles)) ?? []
        targetKeywords = (try? c.decode([String].self, forKey: .targetKeywords)) ?? []
        targetCompanies = (try? c.decode([String].self, forKey: .targetCompanies)) ?? []
        targetIndustries = (try? c.decode([String].self, forKey: .targetIndustries)) ?? []
        count = (try? c.decode(Int.self, forKey: .count)) ?? 8
        preferredAction = (try? c.decode(PreferredAction.self, forKey: .preferredAction)) ?? .linkedinDm
    }

    init(
        rawText: String, goalType: String, searchQuery: String,
        targetRoles: [String] = [], targetKeywords: [String] = [],
        targetCompanies: [String] = [], targetIndustries: [String] = [],
        count: Int = 8, preferredAction: PreferredAction = .linkedinDm
    ) {
        self.rawText = rawText
        self.goalType = goalType
        self.searchQuery = searchQuery
        self.targetRoles = targetRoles
        self.targetKeywords = targetKeywords
        self.targetCompanies = targetCompanies
        self.targetIndustries = targetIndustries
        self.count = count
        self.preferredAction = preferredAction
    }
}

// MARK: - Run

/// A Scout search run. Mirrors the backend `GTMRun`.
struct GTMRunDTO: Identifiable, Codable, Equatable, Hashable {
    let id: String
    let clientId: String
    let rawText: String
    let parsedIntent: GTMIntentDTO?
    let goalType: String
    let query: String
    let count: Int
    let status: String
    let errorMessage: String?
    let createdAt: Double
    let updatedAt: Double

    init(
        id: String, clientId: String, rawText: String, parsedIntent: GTMIntentDTO?,
        goalType: String, query: String, count: Int, status: String,
        errorMessage: String? = nil, createdAt: Double, updatedAt: Double
    ) {
        self.id = id
        self.clientId = clientId
        self.rawText = rawText
        self.parsedIntent = parsedIntent
        self.goalType = goalType
        self.query = query
        self.count = count
        self.status = status
        self.errorMessage = errorMessage
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        clientId = (try? c.decode(String.self, forKey: .clientId)) ?? ""
        rawText = (try? c.decode(String.self, forKey: .rawText)) ?? ""
        parsedIntent = try c.decodeIfPresent(GTMIntentDTO.self, forKey: .parsedIntent)
        goalType = (try? c.decode(String.self, forKey: .goalType)) ?? "other"
        query = (try? c.decode(String.self, forKey: .query)) ?? ""
        count = (try? c.decode(Int.self, forKey: .count)) ?? 0
        status = (try? c.decode(String.self, forKey: .status)) ?? "ready"
        errorMessage = try c.decodeIfPresent(String.self, forKey: .errorMessage)
        createdAt = (try? c.decode(Double.self, forKey: .createdAt)) ?? 0
        updatedAt = (try? c.decode(Double.self, forKey: .updatedAt)) ?? 0
    }

    /// "Hiring · swift engineer" style label for the query pill.
    var label: String {
        let goal = goalType.prefix(1).uppercased() + goalType.dropFirst()
        if let role = parsedIntent?.targetRoles.first ?? targetFirstRole {
            return "\(goal) · \(role)"
        }
        return goal == "Other" ? String(rawText.prefix(28)) : goal
    }

    private var targetFirstRole: String? { parsedIntent?.targetRoles.first }
}

// MARK: - Prospect

/// Where a prospect is in the (fake) follow-up flow.
enum GTMProspectStatus: String, Codable, Hashable {
    case new, drafted, sent, archived

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = GTMProspectStatus(rawValue: raw) ?? .new
    }
}

/// An AI-found prospect. Mirrors the backend `GTMProspect`. Text/links/scores
/// only — never raw images.
struct GTMProspectDTO: Identifiable, Codable, Equatable, Hashable {
    let id: String
    let runId: String
    let clientId: String
    let prospectId: String
    let name: String
    let headline: String?
    let role: String?
    let company: String?
    let location: String?
    let linkedinUrl: String?
    let email: String?
    let profilePhotoUrl: String?
    let source: String
    let matchScore: Double
    let priority: LeadPriority
    let reasons: [String]
    let missingInfo: [String]
    var outreach: OutreachDraftDTO?
    var selectedChannel: FollowUpChannel?
    var status: GTMProspectStatus
    var sentAt: Double?
    let createdAt: Double
    let updatedAt: Double

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        runId = (try? c.decode(String.self, forKey: .runId)) ?? ""
        clientId = (try? c.decode(String.self, forKey: .clientId)) ?? ""
        prospectId = (try? c.decode(String.self, forKey: .prospectId)) ?? id
        name = (try? c.decode(String.self, forKey: .name)) ?? "Unknown"
        headline = try c.decodeIfPresent(String.self, forKey: .headline)
        role = try c.decodeIfPresent(String.self, forKey: .role)
        company = try c.decodeIfPresent(String.self, forKey: .company)
        location = try c.decodeIfPresent(String.self, forKey: .location)
        linkedinUrl = try c.decodeIfPresent(String.self, forKey: .linkedinUrl)
        email = try c.decodeIfPresent(String.self, forKey: .email)
        profilePhotoUrl = try c.decodeIfPresent(String.self, forKey: .profilePhotoUrl)
        source = (try? c.decode(String.self, forKey: .source)) ?? "mock"
        matchScore = (try? c.decode(Double.self, forKey: .matchScore)) ?? 0
        priority = (try? c.decode(LeadPriority.self, forKey: .priority)) ?? .needsInfo
        reasons = (try? c.decode([String].self, forKey: .reasons)) ?? []
        missingInfo = (try? c.decode([String].self, forKey: .missingInfo)) ?? []
        outreach = try c.decodeIfPresent(OutreachDraftDTO.self, forKey: .outreach)
        selectedChannel = try c.decodeIfPresent(FollowUpChannel.self, forKey: .selectedChannel)
        status = (try? c.decode(GTMProspectStatus.self, forKey: .status)) ?? .new
        sentAt = try c.decodeIfPresent(Double.self, forKey: .sentAt)
        createdAt = (try? c.decode(Double.self, forKey: .createdAt)) ?? 0
        updatedAt = (try? c.decode(Double.self, forKey: .updatedAt)) ?? 0
    }

    init(
        id: String, runId: String, clientId: String, prospectId: String, name: String,
        headline: String? = nil, role: String? = nil, company: String? = nil,
        location: String? = nil, linkedinUrl: String? = nil, email: String? = nil,
        profilePhotoUrl: String? = nil, source: String = "mock", matchScore: Double = 0,
        priority: LeadPriority = .needsInfo, reasons: [String] = [], missingInfo: [String] = [],
        outreach: OutreachDraftDTO? = nil, selectedChannel: FollowUpChannel? = nil,
        status: GTMProspectStatus = .new, sentAt: Double? = nil,
        createdAt: Double = 0, updatedAt: Double = 0
    ) {
        self.id = id
        self.runId = runId
        self.clientId = clientId
        self.prospectId = prospectId
        self.name = name
        self.headline = headline
        self.role = role
        self.company = company
        self.location = location
        self.linkedinUrl = linkedinUrl
        self.email = email
        self.profilePhotoUrl = profilePhotoUrl
        self.source = source
        self.matchScore = matchScore
        self.priority = priority
        self.reasons = reasons
        self.missingInfo = missingInfo
        self.outreach = outreach
        self.selectedChannel = selectedChannel
        self.status = status
        self.sentAt = sentAt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    var displayName: String {
        let t = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? "Unknown" : t
    }

    var roleCompanyLine: String? {
        let r = role?.trimmingCharacters(in: .whitespaces)
        let co = company?.trimmingCharacters(in: .whitespaces)
        switch (r?.isEmpty == false ? r : nil, co?.isEmpty == false ? co : nil) {
        case let (rr?, cc?): return "\(rr) · \(cc)"
        case let (rr?, nil): return rr
        case let (nil, cc?): return cc
        default: return headline
        }
    }

    var hasLinkedIn: Bool { (linkedinUrl?.trimmingCharacters(in: .whitespaces).isEmpty == false) }
    var hasEmail: Bool { (email?.trimmingCharacters(in: .whitespaces).isEmpty == false) }
    var isSent: Bool { status == .sent }

    var initials: String {
        let parts = displayName.split(separator: " ")
        let letters = parts.prefix(2).compactMap { $0.first }
        let s = String(letters).uppercased()
        return s.isEmpty ? "?" : s
    }

    func replacingStatus(
        status: GTMProspectStatus,
        channel: FollowUpChannel?,
        outreach: OutreachDraftDTO?,
        sentAt: Double?
    ) -> GTMProspectDTO {
        var copy = self
        copy.status = status
        copy.selectedChannel = channel ?? selectedChannel
        if let outreach { copy.outreach = outreach }
        copy.sentAt = sentAt ?? self.sentAt
        return copy
    }

    func replacingOutreach(_ outreach: OutreachDraftDTO) -> GTMProspectDTO {
        var copy = self
        copy.outreach = outreach
        if copy.status == .new { copy.status = .drafted }
        return copy
    }
}

/// The `/api/gtm/run` response: the run plus its scored prospects.
struct GTMRunResultDTO: Codable, Equatable {
    let run: GTMRunDTO
    let prospects: [GTMProspectDTO]
}
