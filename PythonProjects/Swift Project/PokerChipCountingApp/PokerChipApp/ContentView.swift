import SwiftUI

struct ContentView: View {
    @StateObject private var auth = AuthViewModel()
    @StateObject private var coordinator = NavigationCoordinator()
    @StateObject private var nightStore: NightStore
    @StateObject private var nightSync: NightSync
    @State private var showsSplash = SplashPolicy.shouldShow()
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(PrefKey.sessionReminderHours) private var reminderHours = 0.0
    @State private var reminders = SessionReminders()
    /// A link from the Lock Screen that arrived before the nights were read or anyone was signed in.
    @State private var pendingLink: NightLink?

    /// Everything that decides when the break reminder fires; when it changes, it is rescheduled.
    private struct ReminderKey: Equatable {
        let night: UUID?
        let isLive: Bool
        let hasOpenPause: Bool
        let pauses: Int
        let hours: Double
    }

    private var reminderKey: ReminderKey {
        let night = nightStore.openNight
        return ReminderKey(night: night?.id, isLive: night?.isLive ?? false, hasOpenPause: night?.hasOpenPause ?? false, pauses: night?.pauses.count ?? 0, hours: reminderHours)
    }

    /// Everything the Lock Screen's Live Activity shows; when it changes, the activity is updated.
    private struct ActivityKey: Equatable {
        let isReady: Bool
        let night: UUID?
        let isLive: Bool
        let hasOpenPause: Bool
        let pauses: Int
        let totalInMinor: Int
        let players: Int
    }

    private var activityKey: ActivityKey {
        let night = nightStore.openNight
        return ActivityKey(
            isReady: nightStore.phase == .ready, night: night?.id, isLive: night?.isLive ?? false,
            hasOpenPause: night?.hasOpenPause ?? false, pauses: night?.pauses.count ?? 0,
            totalInMinor: night?.totalInMinor ?? 0, players: night?.players.count ?? 0
        )
    }

    init() {
        // The store and the sync that serves it are created together, so they
        // always refer to each other.
        let store = NightStore(repository: FileNightRepository())
        _nightStore = StateObject(wrappedValue: store)
        _nightSync = StateObject(wrappedValue: NightSync(store: store))
    }

    var body: some View {
        ZStack {
            PokerBackground()

            mainContent

            if showsSplash {
                SplashScreenView {
                    withAnimation(.easeOut(duration: 0.25)) { showsSplash = false }
                }
                .transition(.opacity)
                .zIndex(1)
            }
        }
        .environmentObject(auth)
        .environmentObject(coordinator)
        .environmentObject(nightStore)
        .environmentObject(nightSync)
        // The app has one fixed dark "high-stakes" look regardless of the
        // system setting — this also makes every system control (nav bar,
        // back button, segmented picker, text cursor) adopt dark-appropriate,
        // gold-tinted styling automatically, without touching each screen.
        .preferredColorScheme(.dark)
        .tint(.pokerGold)
        .onAppear {
            if showsSplash { SplashPolicy.markShown() }
        }
        // Signing in or out starts the main stack from a clean slate.
        .onChange(of: auth.isSignedIn) { _ in
            coordinator.popToRoot()
            coordinator.tab = .play
        }
        // Nights are read from the phone first; the backup follows in the
        // background, for whoever is signed in (and again if that changes).
        .task(id: auth.account?.uid) {
            await nightStore.load()
            #if DEBUG
            if AppEnvironment.seedsLiveNight, nightStore.nights.isEmpty {
                nightStore.start(GameNight.start(
                    now: Date().addingTimeInterval(-25 * 60), buyInMinor: 2_500, playerNames: ["Sam", "Alex", "Jo"],
                    colors: ["White", "Red", "Blue", "Green", "Black"],
                    denominationsMinor: ["White": 25, "Red": 100, "Blue": 200, "Green": 500, "Black": 1_000]
                ))
            }
            #endif
            if let link = pendingLink, auth.isSignedIn {
                pendingLink = nil
                open(link)
            }
            await nightSync.sync(uid: auth.account?.uid)
        }
        // The night's clock and money on the Lock Screen and in the Dynamic Island follow the night in progress.
        .task(id: activityKey) {
            guard !AppEnvironment.isUITest || AppEnvironment.seedsLiveNight, nightStore.phase == .ready else { return }
            NightActivityController.shared.sync(with: nightStore.openNight)
        }
        // The Lock Screen's Break button and a tap on the activity come back here.
        .onOpenURL { url in
            guard let link = NightLink(url: url) else { return }
            open(link)
        }
        // The optional "time for a break?" reminder follows the night in progress.
        .task(id: reminderKey) {
            guard !AppEnvironment.isUITest else { return }
            await reminders.update(night: nightStore.openNight, hours: reminderHours > 0 ? reminderHours : nil)
        }
        // A change is backed up after a quiet moment, and coming back to the app checks in again.
        .onChange(of: nightStore.pendingCount) { count in
            if count > 0 { nightSync.schedule(uid: auth.account?.uid) }
        }
        .onChange(of: scenePhase) { phase in
            guard phase == .active else { return }
            nightStore.retrySaving()
            nightSync.schedule(uid: auth.account?.uid)
        }
    }

    /// Shows the night in progress for a link from the Lock Screen, or holds it until the nights are
    /// read and someone is signed in.
    private func open(_ link: NightLink) {
        guard nightStore.phase == .ready, auth.isSignedIn else {
            pendingLink = link
            return
        }
        guard let id = nightStore.handle(link) else { return }
        coordinator.tab = .play
        coordinator.open(night: id)
    }

    @ViewBuilder
    private var mainContent: some View {
        switch auth.state {
        case .unknown:
            // Firebase reports the stored sign-in within a frame or two.
            Color.clear
        case .signedOut:
            NavigationStack {
                AuthenticationView()
            }
        case .signedIn:
            // Four tabs, each with a stack of its own. The flow screens (setting
            // up and playing a night) hide the tab bar to keep the room and so a
            // night in progress can't be wandered away from by accident.
            TabView(selection: $coordinator.tab) {
                NavigationStack(path: $coordinator.path) {
                    StartScreenView()
                        .navigationDestination(for: AppRoute.self) { route in
                            destination(for: route)
                                .toolbar(.hidden, for: .tabBar)
                        }
                }
                .tabItem { Label("Play", systemImage: "suit.spade.fill") }
                .tag(AppTab.play)

                NavigationStack { HistoryView() }
                    .tabItem { Label("History", systemImage: "clock.arrow.circlepath") }
                    .tag(AppTab.history)

                NavigationStack { StatsView() }
                    .tabItem { Label("Stats", systemImage: "chart.line.uptrend.xyaxis") }
                    .tag(AppTab.stats)

                NavigationStack { SettingsView() }
                    .tabItem { Label("Settings", systemImage: "gearshape.fill") }
                    .tag(AppTab.settings)
            }
        }
    }

    @ViewBuilder
    private func destination(for route: AppRoute) -> some View {
        switch route {
        case .buyIn(let prefill):
            BuyInView(prefill: prefill)
        case .players(let setup):
            PlayersView(setup: setup)
        case .chipStyle(let setup):
            DenominationStyleView(setup: setup)
        case .suggested(let setup):
            CombinedDenominationsView(setup: setup)
        case .custom(let setup):
            CustomDenominationView(setup: setup)
        case .night(let id):
            LiveNightView(nightID: id)
        case .cashOut(let target):
            ReviewCountsView(target: target, night: nightStore.night(target.nightID))
        case .bankCheck(let id):
            BankCheckView(nightID: id)
        case .settleUp(let id):
            SettleUpView(nightID: id)
        case .result(let id):
            ResultView(nightID: id)
        case .pokerHealth:
            PokerHealthView()
        }
    }
}
