import Foundation

/// Fully offline backend for `mockAll` (and the deterministic-CV half of
/// `mockCV`). Uses the bundled roster plus the on-device `CommandInterpreter`
/// and `OpenerGenerator`. Adds a tiny artificial delay so the "thinking" state
/// is visible in the demo, but never depends on the network.
final class MockBackend: ReccoBackend {
    private let people: [PersonDTO]
    private let peopleById: [String: PersonDTO]
    /// Simulated round-trip latency for thinking-state visibility.
    private let latency: Duration
    /// In-memory Brain store so the offline demo shows a populated event memory.
    private let memoryStore: MockMemoryStore

    init(people: [PersonDTO], latency: Duration = .milliseconds(450)) {
        self.people = people
        self.peopleById = Dictionary(uniqueKeysWithValues: people.map { ($0.id, $0) })
        self.latency = latency
        self.memoryStore = MockMemoryStore(seedPeople: people)
    }

    func listPeople() async throws -> [PersonDTO] {
        people
    }

    func interpretCommand(transcript: String, visiblePersonIds: [String]) async throws -> FilterCommandDTO {
        try? await Task.sleep(for: latency)
        return CommandInterpreter.interpret(transcript, people: people)
    }

    func createOpener(personId: String, userGoal: String?) async throws -> DraftResultDTO {
        guard let person = peopleById[personId] else {
            throw BackendError.unknownPerson(personId)
        }
        try? await Task.sleep(for: latency)
        return OpenerGenerator.draft(for: person, userGoal: userGoal)
    }

    func matchFace(imageBase64: String, imageMimeType: String, trackId: String) async throws -> FaceMatchResultDTO {
        // Deterministic demo match: hash the trackId onto a roster person so the
        // same track always resolves to the same person (stable overlays).
        try? await Task.sleep(for: .milliseconds(200))
        guard !people.isEmpty else {
            return FaceMatchResultDTO(trackId: trackId, status: .noFace)
        }
        let index = abs(trackId.hashValue) % people.count
        let person = people[index]
        return FaceMatchResultDTO(
            trackId: trackId,
            status: .matched,
            personId: person.id,
            score: 0.44,
            quality: FaceQualityDTO(faceDetected: true, detectionScore: 0.97, cropWidth: 180, cropHeight: 180, model: "mock"),
            message: "deterministic demo match",
            latencyMs: 200
        )
    }

    func resolveIdentity(
        transcript: String,
        trackId: String,
        faceImageBase64: String,
        contextImageBase64: String
    ) async throws -> IdentityResolveResultDTO {
        // Deterministic demo identity: hash the trackId onto a roster person and
        // present a fully-formed candidate so the demo shows the complete flow
        // with no backend. CRITICAL: mock mode has no real CV, so we return
        // `.possible` (never `.verified`) — the app must never claim a verified
        // face match without a real CV embedding (the live path on a device
        // returns `.verified`).
        try? await Task.sleep(for: latency)
        guard !people.isEmpty else {
            return IdentityResolveResultDTO(
                trackId: trackId,
                status: .notFound,
                message: "No roster loaded."
            )
        }
        let index = abs(trackId.hashValue) % people.count
        let person = people[index]
        let candidate = IdentityCandidateDTO(
            candidateId: "cand_mock_\(person.id)",
            fullName: person.name,
            headline: "\(person.role) at \(person.company)",
            role: person.role,
            company: person.company,
            location: nil,
            linkedinUrl: person.links.linkedin,
            email: nil,
            profilePhotoUrl: person.avatarUrl,
            source: "mock",
            matchScore: 0.62
        )
        let verification = FaceVerificationDTO(
            candidateId: candidate.candidateId,
            verified: false,
            score: nil,
            threshold: 0.32,
            faceDetected: false,
            message: "Mock mode: CV unavailable — face not verified."
        )
        let clue = IdentityClueDTO(
            rawText: "\(person.name) · \(person.company)",
            fullName: person.name,
            company: person.company,
            role: person.role,
            confidence: 0.88,
            evidence: "demo badge"
        )
        return IdentityResolveResultDTO(
            trackId: trackId,
            status: .possible,
            clue: clue,
            candidates: [candidate],
            bestCandidate: candidate,
            verification: verification,
            message: "Possible match (demo): \(person.name) · \(person.company). Face not verified in mock mode.",
            latencyMs: 200
        )
    }

    // MARK: - Mission (offline)

    func parseMission(clientId: String, rawText: String) async throws -> MissionProfileDTO {
        try? await Task.sleep(for: .milliseconds(350))
        var mission = MissionParser.parse(rawText)
        mission.clientId = clientId
        memoryStore.setMission(mission)
        return mission
    }

    func currentMission(clientId: String) async throws -> MissionProfileDTO? {
        memoryStore.currentMission()
    }

    // MARK: - Brain scan memory (offline)

    func listScanMemories(clientId: String?) async throws -> [ScanMemoryDTO] {
        memoryStore.list()
    }

    func upsertScanMemory(_ input: ScanMemoryInputDTO) async throws -> ScanMemoryDTO {
        try? await Task.sleep(for: .milliseconds(150))
        return memoryStore.upsert(input)
    }

    func scoreScanMemory(id: String, clientId: String?, mission: MissionProfileDTO) async throws -> ScanMemoryDTO? {
        memoryStore.score(id: id, mission: mission)
    }

    func updateScanMemoryNotes(id: String, notes: String?) async throws -> ScanMemoryDTO? {
        memoryStore.updateNotes(id: id, notes: notes)
    }

    func updateFollowUpStatus(
        id: String,
        status: FollowUpStatus,
        channel: FollowUpChannel?,
        editedOutreach: OutreachDraftDTO?,
        sentAt: Double?
    ) async throws -> ScanMemoryDTO? {
        try? await Task.sleep(for: .milliseconds(120))
        return memoryStore.updateFollowUp(id: id, status: status, channel: channel, editedOutreach: editedOutreach, sentAt: sentAt)
    }

    func generateScanMemoryOutreach(
        id: String,
        eventName: String?,
        senderName: String?,
        mission: MissionProfileDTO?
    ) async throws -> OutreachDraftDTO {
        try? await Task.sleep(for: latency)
        return memoryStore.generateOutreach(id: id, eventName: eventName, senderName: senderName, mission: mission)
    }

    // MARK: - Lazy GTM / Scout Mode (offline)

    private let gtmStore = GTMStore()

    func runGTMScout(clientId: String, transcript: String, count: Int?) async throws -> GTMRunResultDTO {
        // Feel like a real search (parse → rank → draft).
        try? await Task.sleep(for: .milliseconds(950))
        let now = Date().timeIntervalSince1970 * 1000
        let intent = GTMScout.parseIntent(transcript, count: count)
        let runId = "gtmrun_\(UUID().uuidString.prefix(8).lowercased())"
        let prospects = GTMScout.mockProspects(intent: intent, runId: runId, clientId: clientId, now: now)
        let run = GTMRunDTO(
            id: runId, clientId: clientId, rawText: transcript, parsedIntent: intent,
            goalType: intent.goalType, query: intent.searchQuery, count: intent.count,
            status: "ready", errorMessage: nil, createdAt: now, updatedAt: now
        )
        gtmStore.add(run: run, prospects: prospects)
        return GTMRunResultDTO(run: run, prospects: prospects)
    }

    func listGTMRuns(clientId: String) async throws -> [GTMRunDTO] {
        gtmStore.runs(clientId: clientId)
    }

    func listGTMProspects(clientId: String, runId: String?) async throws -> [GTMProspectDTO] {
        gtmStore.prospects(clientId: clientId, runId: runId)
    }

    func generateGTMOutreach(id: String, eventName: String?, senderName: String?) async throws -> OutreachDraftDTO {
        try? await Task.sleep(for: latency)
        return gtmStore.regenerateOutreach(id: id)
    }

    func updateGTMProspectStatus(
        id: String,
        status: GTMProspectStatus,
        channel: FollowUpChannel?,
        editedOutreach: OutreachDraftDTO?,
        sentAt: Double?
    ) async throws -> GTMProspectDTO? {
        try? await Task.sleep(for: .milliseconds(120))
        return gtmStore.updateStatus(id: id, status: status, channel: channel, editedOutreach: editedOutreach, sentAt: sentAt)
    }
}

/// Thread-safe in-memory Scout store for the offline backend.
private final class GTMStore: @unchecked Sendable {
    private let lock = NSLock()
    private var runs: [GTMRunDTO] = []
    private var prospects: [GTMProspectDTO] = []

    func add(run: GTMRunDTO, prospects: [GTMProspectDTO]) {
        lock.lock(); defer { lock.unlock() }
        runs.insert(run, at: 0)
        self.prospects.insert(contentsOf: prospects, at: 0)
    }

    func runs(clientId: String) -> [GTMRunDTO] {
        lock.lock(); defer { lock.unlock() }
        return runs.filter { $0.clientId == clientId }.sorted { $0.createdAt > $1.createdAt }
    }

    func prospects(clientId: String, runId: String?) -> [GTMProspectDTO] {
        lock.lock(); defer { lock.unlock() }
        return prospects
            .filter { $0.clientId == clientId && (runId == nil || $0.runId == runId) }
            .sorted { $0.matchScore > $1.matchScore }
    }

    private func goal(forRun runId: String) -> String {
        runs.first { $0.id == runId }?.goalType ?? "other"
    }

    func regenerateOutreach(id: String) -> OutreachDraftDTO {
        lock.lock(); defer { lock.unlock() }
        guard let i = prospects.firstIndex(where: { $0.id == id }) else {
            return MockOutreach.draft(name: "there", role: nil, company: nil, headline: nil, goalType: "other")
        }
        let p = prospects[i]
        let draft = MockOutreach.draft(name: p.name, role: p.role, company: p.company, headline: p.headline, goalType: goal(forRun: p.runId))
        prospects[i] = p.replacingOutreach(draft)
        return draft
    }

    func updateStatus(
        id: String,
        status: GTMProspectStatus,
        channel: FollowUpChannel?,
        editedOutreach: OutreachDraftDTO?,
        sentAt: Double?
    ) -> GTMProspectDTO? {
        lock.lock(); defer { lock.unlock() }
        guard let i = prospects.firstIndex(where: { $0.id == id }) else { return nil }
        let resolvedSentAt = status == .sent ? (sentAt ?? Date().timeIntervalSince1970 * 1000) : (sentAt ?? prospects[i].sentAt)
        prospects[i] = prospects[i].replacingStatus(status: status, channel: channel, outreach: editedOutreach, sentAt: resolvedSentAt)
        return prospects[i]
    }
}

/// Thread-safe in-memory Brain store for the offline (`mockAll`) backend. Seeded
/// with a few demo memories from the roster so the Brain is demoable with no
/// network; `RECCO_BRAIN_EMPTY=1` starts it empty (for the empty-state demo).
/// Marked `@unchecked Sendable` because all access is guarded by `lock`.
private final class MockMemoryStore: @unchecked Sendable {
    private let lock = NSLock()
    private var memories: [ScanMemoryDTO]
    private var mission: MissionProfileDTO?

    init(seedPeople people: [PersonDTO]) {
        if ProcessInfo.processInfo.environment["RECCO_BRAIN_EMPTY"] == "1" {
            memories = []
        } else {
            memories = MockMemoryStore.seed(from: people)
        }
    }

    func list() -> [ScanMemoryDTO] {
        lock.lock(); defer { lock.unlock() }
        return memories.sorted { $0.lastScannedAt > $1.lastScannedAt }
    }

    func setMission(_ mission: MissionProfileDTO) {
        lock.lock(); defer { lock.unlock() }
        self.mission = mission
    }

    func currentMission() -> MissionProfileDTO? {
        lock.lock(); defer { lock.unlock() }
        return mission
    }

    func score(id: String, mission: MissionProfileDTO) -> ScanMemoryDTO? {
        lock.lock(); defer { lock.unlock() }
        guard let i = memories.firstIndex(where: { $0.id == id }) else { return nil }
        let r = LeadScorer.score(memories[i], mission: mission)
        memories[i] = memories[i].replacingLead(
            priority: r.priority, score: r.score, reasons: r.reasons,
            nextAction: r.nextAction.rawValue,
            missionSnapshot: MissionProfileDTO(rawText: mission.rawText, goalType: mission.goalType)
        )
        return memories[i]
    }

    func updateFollowUp(
        id: String,
        status: FollowUpStatus,
        channel: FollowUpChannel?,
        editedOutreach: OutreachDraftDTO?,
        sentAt: Double?
    ) -> ScanMemoryDTO? {
        lock.lock(); defer { lock.unlock() }
        guard let i = memories.firstIndex(where: { $0.id == id }) else { return nil }
        let resolvedSentAt = status == .sent ? (sentAt ?? Date().timeIntervalSince1970 * 1000) : (sentAt ?? memories[i].sentAt)
        memories[i] = memories[i].replacingFollowUp(
            status: status,
            channel: channel ?? memories[i].followUpChannel,
            editedOutreach: editedOutreach ?? memories[i].editedOutreach,
            sentAt: resolvedSentAt
        )
        return memories[i]
    }

    func updateNotes(id: String, notes: String?) -> ScanMemoryDTO? {
        lock.lock(); defer { lock.unlock() }
        guard let i = memories.firstIndex(where: { $0.id == id }) else { return nil }
        let trimmed = notes?.trimmingCharacters(in: .whitespacesAndNewlines)
        memories[i] = memories[i].replacingNotes((trimmed?.isEmpty == false) ? trimmed : nil)
        return memories[i]
    }

    func generateOutreach(id: String, eventName: String?, senderName: String?, mission: MissionProfileDTO?) -> OutreachDraftDTO {
        lock.lock(); defer { lock.unlock() }
        let goal = mission?.goalType ?? self.mission?.goalType
        let draft: OutreachDraftDTO
        if let i = memories.firstIndex(where: { $0.id == id }) {
            draft = MockMemoryStore.outreach(for: memories[i], eventName: eventName, senderName: senderName, goal: goal)
            memories[i] = memories[i].replacingOutreach(draft)
        } else {
            draft = MockMemoryStore.outreach(for: nil, eventName: eventName, senderName: senderName, goal: goal)
        }
        return draft
    }

    func upsert(_ input: ScanMemoryInputDTO) -> ScanMemoryDTO {
        lock.lock(); defer { lock.unlock() }
        let now = Date().timeIntervalSince1970 * 1000
        let linkedinKey = MockMemoryStore.normalizeLinkedIn(input.linkedinUrl)
        let nameKey = MockMemoryStore.nameCompanyKey(input.name, input.company)

        let index = memories.firstIndex { existing in
            if let lk = linkedinKey, MockMemoryStore.normalizeLinkedIn(existing.linkedinUrl) == lk { return true }
            if let nk = nameKey, MockMemoryStore.nameCompanyKey(existing.name, existing.company) == nk { return true }
            return false
        }

        let confidence = MockMemoryStore.confidence(from: input.status)
        var sources = Set<String>()
        if (input.badgeText?.isEmpty == false) { sources.insert("badge") }
        if input.candidateCount > 0 { sources.insert("fiber") }
        if input.hadFaceVerification { sources.insert("face") }
        if (input.transcript?.isEmpty == false) { sources.insert("voice") }
        if input.personId != nil { sources.insert("roster") }

        if let i = index {
            let prev = memories[i]
            let merged = ScanMemoryDTO(
                id: prev.id,
                scanId: input.scanId,
                personId: input.personId ?? prev.personId,
                name: input.name ?? prev.name,
                headline: input.headline ?? prev.headline,
                role: input.role ?? prev.role,
                company: input.company ?? prev.company,
                school: input.school ?? prev.school,
                linkedinUrl: input.linkedinUrl ?? prev.linkedinUrl,
                email: input.email ?? prev.email,
                confidence: confidence,
                confidenceScore: input.confidenceScore ?? prev.confidenceScore,
                sources: Array(Set(prev.sources).union(sources)).sorted(),
                notes: prev.notes,
                badgeText: input.badgeText ?? prev.badgeText,
                outreach: prev.outreach,
                firstScannedAt: prev.firstScannedAt,
                lastScannedAt: now,
                scanCount: prev.scanCount + 1
            )
            memories[i] = merged
            return merged
        }

        let created = ScanMemoryDTO(
            id: "mem_\(UUID().uuidString.prefix(8))",
            scanId: input.scanId,
            personId: input.personId,
            name: input.name,
            headline: input.headline,
            role: input.role,
            company: input.company,
            school: input.school,
            linkedinUrl: input.linkedinUrl,
            email: input.email,
            confidence: confidence,
            confidenceScore: input.confidenceScore,
            sources: Array(sources).sorted(),
            notes: nil,
            badgeText: input.badgeText,
            outreach: nil,
            firstScannedAt: now,
            lastScannedAt: now,
            scanCount: 1
        )
        memories.append(created)
        return created
    }

    // MARK: - Offline helpers (mirror backend lib/scanMemory + lib/outreach)

    private static func confidence(from status: String) -> ScanConfidence {
        switch status {
        case "verified": return .verified
        case "possible": return .possible
        case "needs_clarification": return .needsConfirmation
        default: return .unknown
        }
    }

    private static func normalizeLinkedIn(_ url: String?) -> String? {
        guard var s = url?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(), !s.isEmpty else { return nil }
        if let r = s.range(of: "://") { s = String(s[r.upperBound...]) }
        if s.hasPrefix("www.") { s.removeFirst(4) }
        if let cut = s.firstIndex(where: { $0 == "?" || $0 == "#" }) { s = String(s[..<cut]) }
        while s.hasSuffix("/") { s.removeLast() }
        return s.isEmpty ? nil : s
    }

    private static func nameCompanyKey(_ name: String?, _ company: String?) -> String? {
        let n = (name ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !n.isEmpty else { return nil }
        let c = (company ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return c.isEmpty ? n : "\(n)|\(c)"
    }

    /// A subtle, goal-aware extra clause (empty for networking/other).
    private static func missionAngle(_ goal: MissionGoalType?) -> String {
        switch goal {
        case .fundraising: return "I'd genuinely value your perspective as an investor as we shape our next round."
        case .getHired: return "I'm exploring my next role, and your team came to mind."
        case .hiring: return "We're growing the team and I'd love to keep you in the loop."
        case .customers: return "Curious whether what we're building could be useful for your team."
        case .sponsors: return "Wondering if there might be a fit for a partnership down the line."
        case .cofounder: return "Always keen to meet people I might end up building with."
        case .founders: return "Always up for trading notes with other founders."
        default: return ""
        }
    }

    private static func outreach(
        for memory: ScanMemoryDTO?,
        eventName: String?,
        senderName: String?,
        goal: MissionGoalType?
    ) -> OutreachDraftDTO {
        let fn = memory?.firstName ?? "there"
        let topic = memory?.company ?? memory?.role ?? "what you're building"
        let event = (eventName?.isEmpty == false ? eventName! : "the event")
        let sender = senderName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let signoff = sender.isEmpty ? "Best" : "Best,\n\(sender)"
        let angle = missionAngle(goal)
        let dmAngle = angle.isEmpty ? "" : " \(angle)"
        let emailAngle = angle.isEmpty ? "" : "\(angle)\n\n"
        return OutreachDraftDTO(
            linkedinDm: "Hey \(fn), great meeting you at \(event). Loved hearing about \(topic).\(dmAngle) "
                + "We're building Recco, an AR memory layer for event networking — would love to compare notes.",
            coldEmailSubject: "Great meeting you at \(event)",
            coldEmail: "Hey \(fn),\n\nGreat meeting you at \(event). I noticed you're working around \(topic), "
                + "and it connected with what we're building in Recco: a lightweight AR memory layer for event networking.\n\n"
                + "\(emailAngle)Would love to compare notes sometime this week.\n\n\(signoff)",
            inPersonOpener: "Hey \(fn) — good to see you again. I was just telling someone about your work on \(topic). "
                + "How's \(event) treating you?"
        )
    }

    /// Seed a handful of memories crafted so the priority graph reads well even
    /// offline: a hot lead (flagged high-priority), a warm one, a cold one, a
    /// needs-info one, and one already marked Sent. Scoring is applied by the app
    /// against the active mission; the *content* here guarantees a spread.
    private static func seed(from people: [PersonDTO]) -> [ScanMemoryDTO] {
        let now = Date().timeIntervalSince1970 * 1000
        let confidences: [ScanConfidence] = [.verified, .verified, .possible, .needsConfirmation, .verified]
        let hasLinkedIn = [true, true, true, false, true]
        let hasEmail = [true, true, false, false, true]
        let scanCounts = [3, 2, 1, 1, 1]
        let notesArr: [String?] = [
            "High priority — great fit, follow up this week.",
            nil, nil, nil,
            "Met at the booth; already reached out.",
        ]
        let statuses: [FollowUpStatus] = [.new, .new, .new, .new, .sent]
        let scores = [0.92, 0.81, 0.66, 0.34, 0.88]
        let sourceSets = [
            ["badge", "fiber", "face"],
            ["badge", "fiber", "voice"],
            ["badge", "fiber"],
            ["badge"],
            ["badge", "fiber", "face", "voice"],
        ]

        return people.prefix(5).enumerated().map { idx, p in
            let slug = p.name.lowercased().replacingOccurrences(of: " ", with: "-")
            let linkedin = hasLinkedIn[idx]
                ? (p.links.linkedin ?? "https://www.linkedin.com/in/\(slug)")
                : nil
            let email = hasEmail[idx]
                ? "\(p.firstName.lowercased())@\(p.company.lowercased().replacingOccurrences(of: " ", with: "")).com"
                : nil
            let status = statuses[idx]
            let outreach = status == .sent
                ? MockMemoryStore.outreach(for: nil, eventName: nil, senderName: "Pranav", goal: nil)
                : nil
            return ScanMemoryDTO(
                id: "mem_seed_\(p.id)",
                scanId: "trk_seed_\(idx)",
                personId: p.id,
                name: p.name,
                headline: "\(p.role) at \(p.company)",
                role: p.role,
                company: p.company,
                school: nil,
                linkedinUrl: linkedin,
                email: email,
                confidence: confidences[idx],
                confidenceScore: scores[idx],
                sources: sourceSets[idx],
                notes: notesArr[idx],
                badgeText: "\(p.name) · \(p.company)",
                outreach: outreach,
                firstScannedAt: now - Double((idx + 1) * 1000 * 60 * 9),
                lastScannedAt: now - Double(idx * 1000 * 60 * 4),
                scanCount: scanCounts[idx],
                followUpStatus: status,
                sentAt: status == .sent ? now - Double(1000 * 60 * 30) : nil
            )
        }
    }
}
