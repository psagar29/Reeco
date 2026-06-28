import Foundation

/// The three demo fallback levels from `docs/API_CONTRACTS.md`.
///
/// - `mockAll`: no backend at all. Local JSON roster + fake recognition +
///   on-device command parsing + on-device opener generation. This is the
///   stage-safe default that always works with no network.
/// - `mockCV`: backend (Convex) is live for people/state/voice/drafts, but the
///   CV face-match action returns deterministic demo matches.
/// - `live`: everything real — Convex + CV service + voice actions.
enum DemoMode: String, CaseIterable, Identifiable, Codable {
    case mockAll
    case mockCV
    case live

    var id: String { rawValue }

    var title: String {
        switch self {
        case .mockAll: return "Mock All"
        case .mockCV: return "Mock CV"
        case .live: return "Live"
        }
    }

    var subtitle: String {
        switch self {
        case .mockAll: return "No backend · local JSON · fake recognition"
        case .mockCV: return "Convex live · deterministic CV matches"
        case .live: return "Convex + CV + voice"
        }
    }

    var systemImage: String {
        switch self {
        case .mockAll: return "wifi.slash"
        case .mockCV: return "camera.metering.unknown"
        case .live: return "bolt.fill"
        }
    }

    /// Whether this mode talks to a remote backend at all. `mockAll` is fully
    /// offline; the other two expect a Convex URL.
    var usesBackend: Bool { self != .mockAll }

    /// The default the app launches into. Stage-safe: works with zero network.
    static let `default`: DemoMode = .mockAll
}
