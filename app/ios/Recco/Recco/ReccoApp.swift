import SwiftUI

@main
struct ReccoApp: App {
    /// The one shared model for the whole app. Launches in the stage-safe
    /// `mockAll` mode (overridable via the DEMO_MODE env var).
    @State private var appModel = AppModel(
        demoMode: ReccoApp.initialDemoMode(),
        apiBaseURL: ReccoApp.apiBaseURL()
    )

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(appModel)
                .preferredColorScheme(.dark)
                .task { await appModel.bootstrap() }
        }
    }

    // MARK: - Environment configuration

    private static func initialDemoMode() -> DemoMode {
        if let raw = ProcessInfo.processInfo.environment["DEMO_MODE"],
           let mode = DemoMode(rawValue: raw) {
            return mode
        }
        return .default
    }

    /// Backend base URL. Prefers `RECCO_API_BASE_URL` (Person C's HTTP bridge),
    /// falls back to the existing `CONVEX_URL`. Empty/whitespace strings are
    /// treated as "not set" so the app degrades to the local fallback.
    private static func apiBaseURL() -> URL? {
        let env = ProcessInfo.processInfo.environment
        let candidates = [env["RECCO_API_BASE_URL"], env["CONVEX_URL"]]
        for case let raw? in candidates {
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty, let url = URL(string: trimmed) { return url }
        }
        return nil
    }
}
