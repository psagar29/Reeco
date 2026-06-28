import SwiftUI

@main
struct ReccoApp: App {
    /// Public Convex HTTP Actions origin for the hackathon deployment.
    ///
    /// This is not a secret: it is the backend's public HTTPS endpoint. Keeping
    /// it as an installed-app fallback means Recco still works after unplugging
    /// the iPhone from Xcode and launching from the home screen.
    private static let installedDemoBackendURL =
        URL(string: "https://fabulous-hyena-861.convex.site")!

    /// The one shared model for the whole app. Defaults to the live demo path so
    /// a TestFlight/dev-installed build works without Xcode environment vars.
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
        return .live
    }

    /// Backend base URL. Prefers `RECCO_API_BASE_URL` (Person C's HTTP bridge),
    /// falls back to the existing `CONVEX_URL`, then to the public hackathon
    /// deployment so the installed app works when launched without Xcode.
    private static func apiBaseURL() -> URL? {
        let env = ProcessInfo.processInfo.environment
        let candidates = [env["RECCO_API_BASE_URL"], env["CONVEX_URL"]]
        for case let raw? in candidates {
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty, let url = URL(string: trimmed) { return url }
        }
        return installedDemoBackendURL
    }
}
