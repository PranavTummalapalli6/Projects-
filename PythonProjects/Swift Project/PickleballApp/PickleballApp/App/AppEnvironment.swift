import CoreLocation
import Foundation
import Observation
import PickleCore

/// Dependency container. Built once at launch and injected through the SwiftUI environment.
@MainActor
@Observable
final class AppEnvironment {
    @ObservationIgnored let config: AppConfig
    @ObservationIgnored let backend: Backend
    @ObservationIgnored let store: LocalStore
    @ObservationIgnored let facilityService: FacilityService
    @ObservationIgnored let recommendationService: RecommendationService
    @ObservationIgnored let submissionService: SubmissionService
    @ObservationIgnored let demoBackend: DemoBackend?
    let location: LocationService
    let preferences: PreferencesStore
    let contributor: ContributorStore
    let reports: ReportService
    let visits: VisitService

    init(config: AppConfig = .load()) {
        self.config = config
        let store = LocalStore()
        if config.isUITesting { store.reset() }
        self.store = store

        let demo: DemoBackend?
        let backend: Backend
        if config.isDemo {
            let d = DemoBackend()
            demo = d
            backend = Backend(facilities: d, reports: d, submissions: d, profile: d, isDemo: true)
        } else {
            let client = SupabaseClient(baseURL: config.supabaseURL!, anonKey: config.supabaseAnonKey!)
            demo = nil
            backend = Backend(facilities: SupabaseFacilityRepository(client: client),
                              reports: SupabaseReportRepository(client: client),
                              submissions: SupabaseSubmissionRepository(client: client),
                              profile: SupabaseProfileRepository(client: client), isDemo: false)
        }
        self.demoBackend = demo
        self.backend = backend

        // UI tests run at a fixed spot next to a demo facility, without permission prompts.
        self.location = LocationService(fixedLocation: config.isUITesting ? CLLocation(latitude: 38.8458, longitude: -77.3060) : nil)
        self.preferences = PreferencesStore(store: store, profile: backend.profile)
        self.contributor = ContributorStore(profile: backend.profile)
        self.facilityService = FacilityService(repository: backend.facilities, store: store)
        self.recommendationService = RecommendationService(
            engine: RecommendationEngine(),
            travel: TravelTimeService(routedEnabled: !config.isUITesting),
            conditions: ConditionsService(primary: config.useWeatherKit ? WeatherKitProvider() : nil,
                                          fallback: config.isUITesting ? nil : OpenMeteoProvider()))
        self.submissionService = SubmissionService(repository: backend.submissions, analytics: backend.profile)
        let reports = ReportService(repository: backend.reports, location: location, contributor: contributor, store: store,
                                    analytics: backend.profile, isProduction: config.isProduction,
                                    allowsSimulatedPresence: backend.isDemo || !config.isProduction)
        self.reports = reports
        let visits = VisitService(reports: reports, profile: backend.profile, prefs: preferences,
                                  arrivalDwell: config.isUITesting ? 0 : 60)
        self.visits = visits
        location.onFix = { [weak visits] fix in visits?.handle(fix: fix) }
        if let fix = location.lastFix { visits.handle(fix: fix) }
    }

    var isDemo: Bool { backend.isDemo }

    func log(_ event: String, facilityID: UUID? = nil, props: [String: JSONValue] = [:]) {
        let profile = backend.profile
        Task { await profile.logEvent(event, facilityID: facilityID, props: props) }
    }
}
