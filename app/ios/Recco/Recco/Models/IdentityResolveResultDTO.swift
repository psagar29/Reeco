import Foundation

/// Badge/name-tag clue read by OpenAI Vision. Mirrors `IdentityClue` from
/// `docs/API_CONTRACTS.md`. Produced by Person B's `identity:resolveTarget`.
struct IdentityClueDTO: Codable, Equatable, Hashable {
    let rawText: String
    let fullName: String?
    let company: String?
    let role: String?
    let school: String?
    let confidence: Double
    let evidence: String?

    init(
        rawText: String = "",
        fullName: String? = nil,
        company: String? = nil,
        role: String? = nil,
        school: String? = nil,
        confidence: Double = 0,
        evidence: String? = nil
    ) {
        self.rawText = rawText
        self.fullName = fullName
        self.company = company
        self.role = role
        self.school = school
        self.confidence = confidence
        self.evidence = evidence
    }
}

/// A candidate identity from the Fiber AI lookup. Mirrors `IdentityCandidate`.
struct IdentityCandidateDTO: Identifiable, Codable, Equatable, Hashable {
    let candidateId: String
    let fullName: String
    let headline: String?
    let role: String?
    let company: String?
    let school: String?
    let location: String?
    let linkedinUrl: String?
    let email: String?
    let profilePhotoUrl: String?
    let source: String
    let matchScore: Double

    var id: String { candidateId }

    init(
        candidateId: String,
        fullName: String,
        headline: String? = nil,
        role: String? = nil,
        company: String? = nil,
        school: String? = nil,
        location: String? = nil,
        linkedinUrl: String? = nil,
        email: String? = nil,
        profilePhotoUrl: String? = nil,
        source: String = "fiber",
        matchScore: Double = 0
    ) {
        self.candidateId = candidateId
        self.fullName = fullName
        self.headline = headline
        self.role = role
        self.company = company
        self.school = school
        self.location = location
        self.linkedinUrl = linkedinUrl
        self.email = email
        self.profilePhotoUrl = profilePhotoUrl
        self.source = source
        self.matchScore = matchScore
    }

    /// "Role · Company" when both are present (handy one-liner for the sheet).
    var roleCompany: String? {
        switch (role, company) {
        case let (r?, c?): return "\(r) · \(c)"
        case let (r?, nil): return r
        case let (nil, c?): return c
        default: return nil
        }
    }
}

/// Face verification of a candidate's profile photo vs the live face. Mirrors
/// `FaceVerification`.
struct FaceVerificationDTO: Codable, Equatable, Hashable {
    let candidateId: String
    let verified: Bool
    let score: Double?
    let threshold: Double
    let faceDetected: Bool
    let message: String?

    init(
        candidateId: String,
        verified: Bool,
        score: Double? = nil,
        threshold: Double = 0,
        faceDetected: Bool = false,
        message: String? = nil
    ) {
        self.candidateId = candidateId
        self.verified = verified
        self.score = score
        self.threshold = threshold
        self.faceDetected = faceDetected
        self.message = message
    }
}

/// Result of "find info on him". Mirrors `IdentityResolveResult` from
/// `docs/API_CONTRACTS.md`. Returned by `POST /api/identity/resolve`.
///
/// SAFETY: `status == .verified` is only ever produced by the backend when the
/// text match is strong AND the candidate's profile photo face-verified against
/// the live face. The UI must never relabel a non-`.verified` result as
/// "Verified" (see `confidenceLabel`).
struct IdentityResolveResultDTO: Identifiable, Codable, Equatable, Hashable {
    enum Status: String, Codable {
        case verified
        case possible
        case notFound = "not_found"
        case needsClarification = "needs_clarification"
        case error
    }

    let trackId: String
    let status: Status
    let clue: IdentityClueDTO?
    let candidates: [IdentityCandidateDTO]
    let bestCandidate: IdentityCandidateDTO?
    let verification: FaceVerificationDTO?
    let message: String?
    let latencyMs: Double?

    /// Stable-enough id for `.sheet(item:)`. Includes status + best candidate so
    /// a fresh resolution re-presents the sheet.
    var id: String {
        "\(trackId)-\(status.rawValue)-\(bestCandidate?.candidateId ?? "none")"
    }

    init(
        trackId: String,
        status: Status,
        clue: IdentityClueDTO? = nil,
        candidates: [IdentityCandidateDTO] = [],
        bestCandidate: IdentityCandidateDTO? = nil,
        verification: FaceVerificationDTO? = nil,
        message: String? = nil,
        latencyMs: Double? = nil
    ) {
        self.trackId = trackId
        self.status = status
        self.clue = clue
        self.candidates = candidates
        self.bestCandidate = bestCandidate
        self.verification = verification
        self.message = message
        self.latencyMs = latencyMs
    }

    /// True only for a face-verified result.
    var isVerified: Bool { status == .verified }

    /// User-facing confidence label. NEVER returns "Verified" unless the backend
    /// actually face-verified the candidate.
    var confidenceLabel: String {
        switch status {
        case .verified: return "Verified"
        case .possible: return "Possible"
        case .notFound: return "Not found"
        case .needsClarification: return "Unclear"
        case .error: return "Error"
        }
    }

    /// SF Symbol that matches `confidenceLabel`.
    var statusSymbol: String {
        switch status {
        case .verified: return "checkmark.seal.fill"
        case .possible: return "questionmark.circle.fill"
        case .notFound: return "magnifyingglass"
        case .needsClarification: return "exclamationmark.bubble.fill"
        case .error: return "xmark.octagon.fill"
        }
    }
}
