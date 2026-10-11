import Foundation
import Observation
import PickleCore

/// User preferences (all optional) persisted locally and mirrored to the server profile when a session exists.
@Observable
@MainActor
final class PreferencesStore {
    struct Stored: Codable {
        var prefs = UserPreferences()
        var passiveVisitsEnabled = false
        var savedFacilityIDs: Set<UUID> = []
        var hasSeenLocationPrimer = false
        var sortMode: SortMode = .bestOverall
    }

    var prefs: UserPreferences { didSet { persist(sync: true) } }
    var passiveVisitsEnabled: Bool { didSet { persist(sync: true) } }
    var savedFacilityIDs: Set<UUID> { didSet { persist(sync: false) } }
    var hasSeenLocationPrimer: Bool { didSet { persist(sync: false) } }
    var sortMode: SortMode { didSet { persist(sync: false) } }

    @ObservationIgnored private let store: LocalStore
    @ObservationIgnored private let profile: ProfileRepository
    @ObservationIgnored private var syncTask: Task<Void, Never>?

    init(store: LocalStore, profile: ProfileRepository) {
        self.store = store
        self.profile = profile
        let s = store.load(Stored.self, key: StoreKeys.preferences) ?? Stored()
        prefs = s.prefs
        passiveVisitsEnabled = s.passiveVisitsEnabled
        savedFacilityIDs = s.savedFacilityIDs
        hasSeenLocationPrimer = s.hasSeenLocationPrimer
        sortMode = s.sortMode
    }

    func toggleSaved(_ id: UUID) {
        if savedFacilityIDs.contains(id) { savedFacilityIDs.remove(id) } else { savedFacilityIDs.insert(id) }
    }

    func setAccessGranted(_ id: UUID, _ granted: Bool) {
        if granted { prefs.accessGrantedFacilityIDs.insert(id) } else { prefs.accessGrantedFacilityIDs.remove(id) }
    }

    private func persist(sync: Bool) {
        store.save(Stored(prefs: prefs, passiveVisitsEnabled: passiveVisitsEnabled, savedFacilityIDs: savedFacilityIDs,
                          hasSeenLocationPrimer: hasSeenLocationPrimer, sortMode: sortMode), key: StoreKeys.preferences)
        guard sync else { return }
        // Debounced server sync; only meaningful once the user has an (anonymous) session.
        syncTask?.cancel()
        let prefs = self.prefs, passive = passiveVisitsEnabled, profile = self.profile
        syncTask = Task {
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            try? await profile.saveProfile(prefs, passiveVisits: passive)
        }
    }
}

/// Server-controlled contributor entitlement (never decided on the client).
@Observable
@MainActor
final class ContributorStore {
    private(set) var status: ContributorStatus = .unknown
    /// Set after a qualifying contribution to show the one-time thank-you.
    var justUnlockedUntil: Date?
    @ObservationIgnored private let profile: ProfileRepository

    init(profile: ProfileRepository) { self.profile = profile }

    func refresh() async {
        if let s = try? await profile.contributorStatus() { status = s }
    }

    func noteContribution(insightsUntil: Date?) {
        guard let insightsUntil else { return }
        if (status.insightsUntil ?? .distantPast) < Date() { justUnlockedUntil = insightsUntil }
        status.insightsUntil = insightsUntil
        status.qualifyingContributions += 1
    }
}
