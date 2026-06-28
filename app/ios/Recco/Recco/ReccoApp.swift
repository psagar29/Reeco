import SwiftUI

@main
struct ReccoApp: App {
    /// The one shared model for the whole app. Launches in the stage-safe
    /// `mockAll` mode (overridable via the DEMO_MODE env var).
    @State private var appModel = AppModel(
        demoMode: ReccoApp.initialDemoMode(),
        convexURL: ReccoApp.convexURL()
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

    private static func convexURL() -> URL? {
        guard let raw = ProcessInfo.processInfo.environment["CONVEX_URL"] else { return nil }
        return URL(string: raw)
    }
}
