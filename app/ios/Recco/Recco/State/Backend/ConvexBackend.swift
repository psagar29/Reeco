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

    init(baseURL: URL?, mode: DemoMode, fallbackPeople: [PersonDTO]) {
        self.baseURL = baseURL
        self.mode = mode
        self.fallback = MockBackend(people: fallbackPeople)
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 12      // fail fast on stage Wi-Fi
        config.timeoutIntervalForResource = 20
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

    // MARK: - HTTP helpers

    private func get<T: Decodable>(_ path: String, as type: T.Type) async throws -> T {
        let request = try makeRequest(path: path, method: "GET", body: Optional<Empty>.none)
        return try await send(request, as: type)
    }

    private func post<Body: Encodable, T: Decodable>(_ path: String, body: Body, as type: T.Type) async throws -> T {
        let request = try makeRequest(path: path, method: "POST", body: body)
        return try await send(request, as: type)
    }

    private func makeRequest<Body: Encodable>(path: String, method: String, body: Body?) throws -> URLRequest {
        guard let url = url(for: path) else { throw ConvexBackendError.notConfigured }
        var request = URLRequest(url: url)
        request.httpMethod = method
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
