import Foundation

/// Live / `mockCV` backend client. Talks to Person C's HTTP bridge over plain
/// `URLSession` + `Codable` — no third-party networking package. When no base
/// URL is configured it transparently delegates to an offline `MockBackend`, so
/// the app stays fully demoable (the Person D fallback plan: "Keep the app
/// demoable."). HTTP failures surface as `ConvexBackendError` with a readable
/// message; `AppModel` catches them, keeps the seeded roster, falls back where
/// it is safe, and shows a status line in the transcript ribbon.
///
/// Endpoint map (see `docs/API_CONTRACTS.md` + `AGENT_PROMPT.md`):
///   - listPeople()        -> GET  /api/people
///   - interpretCommand()  -> POST /api/voice/interpret
///   - createOpener()      -> POST /api/drafts/opener
///   - matchFace()         -> POST /api/vision/match-face
final class ConvexBackend: ReccoBackend {
    /// Base URL for the backend HTTP bridge (`RECCO_API_BASE_URL` / `CONVEX_URL`).
    /// `nil` means "no backend configured" → always use the offline fallback.
    let baseURL: URL?
    let mode: DemoMode
    /// Offline fallback that keeps the demo recoverable when no URL is set.
    private let fallback: MockBackend
    private let session: URLSession
    private enum RequestTimeout {
        static let standard: TimeInterval = 12
        static let resource: TimeInterval = 20
        static let identity: TimeInterval = 70
    }

    init(baseURL: URL?, mode: DemoMode, fallbackPeople: [PersonDTO]) {
        self.baseURL = baseURL
        self.mode = mode
        self.fallback = MockBackend(people: fallbackPeople)
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = RequestTimeout.standard      // fail fast on lightweight calls
        config.timeoutIntervalForResource = RequestTimeout.resource
        config.waitsForConnectivity = false
        self.session = URLSession(configuration: config)
    }

    /// True when a real backend is reachable (a base URL was configured).
    private var hasBackend: Bool { baseURL != nil }

    // MARK: - ReccoBackend

    func listPeople() async throws -> [PersonDTO] {
        guard hasBackend else { return try await fallback.listPeople() }
        return try await get("/api/people", as: [PersonDTO].self)
    }

    func interpretCommand(transcript: String, visiblePersonIds: [String]) async throws -> FilterCommandDTO {
        guard hasBackend else {
            return try await fallback.interpretCommand(transcript: transcript, visiblePersonIds: visiblePersonIds)
        }
        let body = InterpretRequest(transcript: transcript, visiblePersonIds: visiblePersonIds)
        return try await post("/api/voice/interpret", body: body, as: FilterCommandDTO.self)
    }

    func createOpener(personId: String, userGoal: String?) async throws -> DraftResultDTO {
        guard hasBackend else {
            return try await fallback.createOpener(personId: personId, userGoal: userGoal)
        }
        let body = OpenerRequest(personId: personId, userGoal: userGoal)
        return try await post("/api/drafts/opener", body: body, as: DraftResultDTO.self)
    }

    func matchFace(imageBase64: String, imageMimeType: String, trackId: String) async throws -> FaceMatchResultDTO {
        guard hasBackend else {
            return try await fallback.matchFace(imageBase64: imageBase64, imageMimeType: imageMimeType, trackId: trackId)
        }
        let body = MatchFaceRequest(imageBase64: imageBase64, imageMimeType: imageMimeType, trackId: trackId)
        return try await post("/api/vision/match-face", body: body, as: FaceMatchResultDTO.self)
    }

    func resolveIdentity(
        transcript: String,
        trackId: String,
        faceImageBase64: String,
        contextImageBase64: String
    ) async throws -> IdentityResolveResultDTO {
        // Identity is the one lane that must NOT fall back to the offline mock on
        // failure: the mock can't actually face-verify, and surfacing a
        // fabricated "Verified" identity for an unrelated person would break the
        // safety invariant. With no backend we return an honest `.error`; a real
        // HTTP failure throws `ConvexBackendError`, which `AppModel` maps to
        // `.error`. A successful but degraded status (not_found /
        // needs_clarification) is passed through unchanged.
        guard hasBackend else {
            return IdentityResolveResultDTO(
                trackId: trackId, status: .error,
                message: "Identity service not configured (set RECCO_API_BASE_URL)."
            )
        }
        let body = IdentityResolveRequest(
            trackId: trackId,
            transcript: transcript,
            faceImageBase64: faceImageBase64,
            contextImageBase64: contextImageBase64,
            imageMimeType: "image/jpeg"
        )
        return try await post(
            "/api/identity/resolve",
            body: body,
            as: IdentityResolveResultDTO.self,
            timeoutInterval: RequestTimeout.identity
        )
    }

    // MARK: - Mission

    func parseMission(clientId: String, rawText: String) async throws -> MissionProfileDTO {
        guard hasBackend else { return try await fallback.parseMission(clientId: clientId, rawText: rawText) }
        let body = MissionParseRequest(clientId: clientId, rawText: rawText)
        return try await post("/api/mission/parse", body: body, as: MissionProfileDTO.self)
    }

    func currentMission(clientId: String) async throws -> MissionProfileDTO? {
        guard hasBackend else { return try await fallback.currentMission(clientId: clientId) }
        let body = MissionCurrentRequest(clientId: clientId)
        return try await post("/api/mission/current", body: body, as: NullableMission.self).value
    }

    // MARK: - Brain scan memory

    func listScanMemories(clientId: String?) async throws -> [ScanMemoryDTO] {
        guard hasBackend else { return try await fallback.listScanMemories(clientId: clientId) }
        var path = "/api/brain/memories"
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        if let clientId,
           let encoded = clientId.addingPercentEncoding(withAllowedCharacters: allowed) {
            path += "?clientId=\(encoded)"
        }
        return try await get(path, as: [ScanMemoryDTO].self)
    }

    func upsertScanMemory(_ input: ScanMemoryInputDTO) async throws -> ScanMemoryDTO {
        guard hasBackend else { return try await fallback.upsertScanMemory(input) }
        return try await post("/api/brain/memories/upsert", body: input, as: ScanMemoryDTO.self)
    }

    func scoreScanMemory(id: String, clientId: String?, mission: MissionProfileDTO) async throws -> ScanMemoryDTO? {
        guard hasBackend else { return try await fallback.scoreScanMemory(id: id, clientId: clientId, mission: mission) }
        let body = ScoreRequest(id: id, clientId: clientId, mission: mission)
        return try await post("/api/brain/memories/score", body: body, as: NullableScanMemory.self).value
    }

    func updateScanMemoryNotes(id: String, notes: String?) async throws -> ScanMemoryDTO? {
        guard hasBackend else { return try await fallback.updateScanMemoryNotes(id: id, notes: notes) }
        let body = NotesRequest(id: id, notes: notes)
        return try await post("/api/brain/memories/notes", body: body, as: NullableScanMemory.self).value
    }

    func updateFollowUpStatus(
        id: String,
        status: FollowUpStatus,
        channel: FollowUpChannel?,
        editedOutreach: OutreachDraftDTO?,
        sentAt: Double?
    ) async throws -> ScanMemoryDTO? {
        guard hasBackend else {
            return try await fallback.updateFollowUpStatus(id: id, status: status, channel: channel, editedOutreach: editedOutreach, sentAt: sentAt)
        }
        let body = FollowUpStatusRequest(
            id: id, status: status.rawValue, channel: channel?.rawValue,
            editedOutreach: editedOutreach, sentAt: sentAt
        )
        return try await post("/api/brain/memories/follow-up-status", body: body, as: NullableScanMemory.self).value
    }

    func generateScanMemoryOutreach(
        id: String,
        eventName: String?,
        senderName: String?,
        mission: MissionProfileDTO?
    ) async throws -> OutreachDraftDTO {
        guard hasBackend else {
            return try await fallback.generateScanMemoryOutreach(id: id, eventName: eventName, senderName: senderName, mission: mission)
        }
        let body = OutreachRequest(id: id, eventName: eventName, senderName: senderName, mission: mission)
        return try await post(
            "/api/brain/memories/outreach",
            body: body,
            as: OutreachDraftDTO.self,
            timeoutInterval: RequestTimeout.identity
        )
    }

    // MARK: - Lazy GTM / Scout Mode

    func runGTMScout(clientId: String, transcript: String, count: Int?) async throws -> GTMRunResultDTO {
        guard hasBackend else { return try await fallback.runGTMScout(clientId: clientId, transcript: transcript, count: count) }
        let body = GTMRunRequest(clientId: clientId, transcript: transcript, count: count)
        return try await post("/api/gtm/run", body: body, as: GTMRunResultDTO.self, timeoutInterval: RequestTimeout.identity)
    }

    func listGTMRuns(clientId: String) async throws -> [GTMRunDTO] {
        guard hasBackend else { return try await fallback.listGTMRuns(clientId: clientId) }
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let enc = clientId.addingPercentEncoding(withAllowedCharacters: allowed) ?? clientId
        return try await get("/api/gtm/runs?clientId=\(enc)", as: [GTMRunDTO].self)
    }

    func listGTMProspects(clientId: String, runId: String?) async throws -> [GTMProspectDTO] {
        guard hasBackend else { return try await fallback.listGTMProspects(clientId: clientId, runId: runId) }
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let enc = clientId.addingPercentEncoding(withAllowedCharacters: allowed) ?? clientId
        var path = "/api/gtm/prospects?clientId=\(enc)"
        if let runId, let r = runId.addingPercentEncoding(withAllowedCharacters: allowed) {
            path += "&runId=\(r)"
        }
        return try await get(path, as: [GTMProspectDTO].self)
    }

    func generateGTMOutreach(id: String, eventName: String?, senderName: String?) async throws -> OutreachDraftDTO {
        guard hasBackend else { return try await fallback.generateGTMOutreach(id: id, eventName: eventName, senderName: senderName) }
        let body = GTMOutreachRequest(id: id, eventName: eventName, senderName: senderName)
        return try await post("/api/gtm/prospects/outreach", body: body, as: OutreachDraftDTO.self, timeoutInterval: RequestTimeout.identity)
    }

    func updateGTMProspectStatus(
        id: String,
        status: GTMProspectStatus,
        channel: FollowUpChannel?,
        editedOutreach: OutreachDraftDTO?,
        sentAt: Double?
    ) async throws -> GTMProspectDTO? {
        guard hasBackend else {
            return try await fallback.updateGTMProspectStatus(id: id, status: status, channel: channel, editedOutreach: editedOutreach, sentAt: sentAt)
        }
        let body = GTMStatusRequest(id: id, status: status.rawValue, channel: channel?.rawValue, editedOutreach: editedOutreach, sentAt: sentAt)
        return try await post("/api/gtm/prospects/status", body: body, as: NullableProspect.self).value
    }

    // MARK: - HTTP helpers

    private func get<T: Decodable>(_ path: String, as type: T.Type) async throws -> T {
        let request = try makeRequest(path: path, method: "GET", body: Optional<Empty>.none)
        return try await send(request, as: type)
    }

    private func post<Body: Encodable, T: Decodable>(
        _ path: String,
        body: Body,
        as type: T.Type,
        timeoutInterval: TimeInterval? = nil
    ) async throws -> T {
        let request = try makeRequest(
            path: path,
            method: "POST",
            body: body,
            timeoutInterval: timeoutInterval
        )
        return try await send(request, as: type)
    }

    private func makeRequest<Body: Encodable>(
        path: String,
        method: String,
        body: Body?,
        timeoutInterval: TimeInterval? = nil
    ) throws -> URLRequest {
        guard let url = url(for: path) else { throw ConvexBackendError.notConfigured }
        var request = URLRequest(url: url)
        request.httpMethod = method
        if let timeoutInterval {
            request.timeoutInterval = timeoutInterval
        }
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            do {
                request.httpBody = try JSONEncoder().encode(body)
            } catch {
                throw ConvexBackendError.encoding(error)
            }
        }
        return request
    }

    private func send<T: Decodable>(_ request: URLRequest, as type: T.Type) async throws -> T {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw ConvexBackendError.transport(error)
        }
        guard let http = response as? HTTPURLResponse else {
            throw ConvexBackendError.invalidResponse
        }
        guard (200...299).contains(http.statusCode) else {
            throw ConvexBackendError.http(status: http.statusCode, body: Self.shortBody(data))
        }
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw ConvexBackendError.decoding(error)
        }
    }

    /// Robust path join so both `https://foo` and `https://foo/` work, and the
    /// path's leading slash is optional.
    private func url(for path: String) -> URL? {
        guard let baseURL else { return nil }
        var base = baseURL.absoluteString
        while base.hasSuffix("/") { base.removeLast() }
        let suffix = path.hasPrefix("/") ? path : "/" + path
        return URL(string: base + suffix)
    }

    private static func shortBody(_ data: Data) -> String {
        guard let s = String(data: data, encoding: .utf8) else { return "" }
        let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.count > 200 ? String(trimmed.prefix(200)) + "…" : trimmed
    }

    // MARK: - Request bodies

    private struct Empty: Encodable {}

    private struct InterpretRequest: Encodable {
        let transcript: String
        let visiblePersonIds: [String]
    }

    private struct OpenerRequest: Encodable {
        let personId: String
        let userGoal: String?
    }

    private struct MatchFaceRequest: Encodable {
        let imageBase64: String
        let imageMimeType: String
        let trackId: String
    }

    private struct IdentityResolveRequest: Encodable {
        let trackId: String
        let transcript: String
        let faceImageBase64: String
        let contextImageBase64: String
        let imageMimeType: String
    }

    private struct NotesRequest: Encodable {
        let id: String
        let notes: String?
    }

    private struct OutreachRequest: Encodable {
        let id: String
        let eventName: String?
        let senderName: String?
        let mission: MissionProfileDTO?
    }

    private struct MissionParseRequest: Encodable {
        let clientId: String
        let rawText: String
    }

    private struct MissionCurrentRequest: Encodable {
        let clientId: String
    }

    private struct ScoreRequest: Encodable {
        let id: String
        let clientId: String?
        let mission: MissionProfileDTO
    }

    private struct FollowUpStatusRequest: Encodable {
        let id: String
        let status: String
        let channel: String?
        let editedOutreach: OutreachDraftDTO?
        let sentAt: Double?
    }

    /// Decodes a `ScanMemory | null` response (the notes endpoint returns null
    /// when the id is unknown).
    private struct NullableScanMemory: Decodable {
        let value: ScanMemoryDTO?
        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            value = container.decodeNil() ? nil : try container.decode(ScanMemoryDTO.self)
        }
    }

    /// Decodes a `MissionProfile | null` response.
    private struct NullableMission: Decodable {
        let value: MissionProfileDTO?
        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            value = container.decodeNil() ? nil : try container.decode(MissionProfileDTO.self)
        }
    }

    private struct GTMRunRequest: Encodable {
        let clientId: String
        let transcript: String
        let count: Int?
    }

    private struct GTMOutreachRequest: Encodable {
        let id: String
        let eventName: String?
        let senderName: String?
    }

    private struct GTMStatusRequest: Encodable {
        let id: String
        let status: String
        let channel: String?
        let editedOutreach: OutreachDraftDTO?
        let sentAt: Double?
    }

    /// Decodes a `GTMProspect | null` response.
    private struct NullableProspect: Decodable {
        let value: GTMProspectDTO?
        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            value = container.decodeNil() ? nil : try container.decode(GTMProspectDTO.self)
        }
    }
}

/// Readable HTTP/transport errors from `ConvexBackend`. `AppModel` turns these
/// into the user-visible status line and decides whether a local fallback is
/// safe (people/voice/drafts yes; face matching no — never show a wrong card).
enum ConvexBackendError: LocalizedError {
    case notConfigured
    case invalidResponse
    case transport(Error)
    case http(status: Int, body: String)
    case encoding(Error)
    case decoding(Error)

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "Backend URL is not configured."
        case .invalidResponse:
            return "Backend returned an invalid response."
        case .transport(let e):
            return "Network error: \(e.localizedDescription)"
        case .http(let status, let body):
            return body.isEmpty ? "Backend error \(status)." : "Backend error \(status): \(body)"
        case .encoding:
            return "Failed to encode request."
        case .decoding:
            return "Failed to decode backend response."
        }
    }
}
