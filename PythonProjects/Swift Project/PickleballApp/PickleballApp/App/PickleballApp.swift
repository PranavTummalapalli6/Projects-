import SwiftUI

@main
struct PickleballApp: App {
    @State private var environment = AppEnvironment()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(environment)
                .tint(Theme.accent)
        }
    }
}
