import SwiftUI

struct RootView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        MapScreen(env: env)
            .onChange(of: scenePhase) { _, phase in
                switch phase {
                case .active:
                    env.location.startUpdates()
                    Task { await env.contributor.refresh() }
                case .background:
                    // Foreground-only location: stop as soon as the app leaves the screen.
                    env.location.stopUpdates()
                default:
                    break
                }
            }
    }
}
