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

    init(people: [PersonDTO], latency: Duration = .milliseconds(450)) {
        self.people = people
        self.peopleById = Dictionary(uniqueKeysWithValues: people.map { ($0.id, $0) })
        self.latency = latency
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
}
