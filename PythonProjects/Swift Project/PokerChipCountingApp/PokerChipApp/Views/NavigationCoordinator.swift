import SwiftUI

/// Every screen the main stack can show. Routes carry the data the screen
/// needs, so the whole path is plain value types — nothing is hidden in a
/// view's `@State` where a pop-and-push could lose it.
enum AppRoute: Hashable {
    case buyIn(GameSetup?)
    case players(GameSetup)
    case chipStyle(GameSetup)
    case suggested(GameSetup)
    case custom(GameSetup)
    case night(UUID)
    case cashOut(CashOutTarget)
    case bankCheck(UUID)
    case settleUp(UUID)
    case result(UUID)
    case pokerHealth
}

/// The four tabs. Each has its own navigation stack; only Play's path lives in
/// the coordinator, because it is the one other screens need to steer.
enum AppTab: Hashable {
    case play
    case history
    case stats
    case settings
}

/// Whose chips are being counted, in which night.
struct CashOutTarget: Hashable {
    let nightID: UUID
    let playerID: UUID
}

/// Owns the app's root navigation path so a deeply nested screen (e.g. the
/// result screen's "Done") can reset back to the real root Home screen
/// instead of pushing a disconnected copy of it.
@MainActor
final class NavigationCoordinator: ObservableObject {
    @Published var path: [AppRoute] = []
    @Published var tab: AppTab = .play

    func push(_ route: AppRoute) {
        path.append(route)
    }

    func popToRoot() {
        path.removeAll()
    }

    func pop() {
        if !path.isEmpty { path.removeLast() }
    }

    /// Shows the night, replacing whatever led to it. Back from the night lands
    /// on Home — where the Resume card lives — instead of on a setup screen that
    /// would start a second night.
    func open(night id: UUID) {
        path = [.night(id)]
    }
}
