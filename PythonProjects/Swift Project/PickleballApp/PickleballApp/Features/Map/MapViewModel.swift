import Foundation
import MapKit
import Observation
import PickleCore

@Observable
@MainActor
final class MapViewModel {
    enum LoadState: Equatable {
        case idle, loading, loaded, empty, zoomedOut, error(String), offline
    }

    private(set) var loadState: LoadState = .idle
    private(set) var recommendations = RecommendationSet(ranked: [], notAvailable: [], picks: [])
    private(set) var visibleBox: GeoBoundingBox?
    private(set) var discoveryInProgress = false
    private(set) var showingCachedData = false
    var filters: FilterState { didSet { filtersChanged() } }

    @ObservationIgnored private var facilities: [Facility] = []
    @ObservationIgnored private var debounceTask: Task<Void, Never>?
    @ObservationIgnored private var refineTask: Task<Void, Never>?
    @ObservationIgnored private let env: AppEnvironment
    @ObservationIgnored private let debounce: Duration
    /// Larger spans are too broad to be useful (and rejected by the backend's cost guard).
    @ObservationIgnored let maxQuerySpan = 2.5

    init(env: AppEnvironment, debounce: Duration = .milliseconds(350)) {
        self.env = env
        self.debounce = debounce
        self.filters = env.store.load(FilterState.self, key: StoreKeys.filters) ?? FilterState()
    }

    // MARK: Derived state

    var origin: GeoPoint? { env.location.isAuthorized ? env.location.lastFix?.point : nil }

    /// Eligible + not-available facilities after filters, in ranking order.
    var displayed: [FacilityRecommendation] {
        recommendations.ranked + (filters.likelyAvailableOnly ? [] : recommendations.notAvailable)
    }

    var picks: [FacilityRecommendation] { recommendations.picks }

    func recommendation(for id: UUID) -> FacilityRecommendation? {
        recommendations.ranked.first { $0.id == id } ?? recommendations.notAvailable.first { $0.id == id }
    }

    func clusters(in box: GeoBoundingBox?) -> [MapCluster<UUID>] {
        guard let box = box ?? visibleBox else { return [] }
        return FacilityClusterer.cluster(displayed.map { ClusterItem(id: $0.id, point: $0.facility.coordinate) }, visible: box)
    }

    // MARK: Loading

    /// Called when the map camera settles. Debounced; cache-aware in FacilityService.
    func cameraChanged(to box: GeoBoundingBox) {
        visibleBox = box
        debounceTask?.cancel()
        debounceTask = Task { [debounce] in
            try? await Task.sleep(for: debounce)
            guard !Task.isCancelled else { return }
            await load(force: false)
        }
    }

    func refresh() async {
        await env.facilityService.invalidate()
        await load(force: true)
    }

    func load(force: Bool) async {
        guard let box = visibleBox else { return }
        if box.latitudeDelta > maxQuerySpan || box.longitudeDelta > maxQuerySpan {
            loadState = .zoomedOut
            return
        }
        if facilities.isEmpty { loadState = .loading }
        do {
            let snapshot = try await env.facilityService.facilities(visible: box, force: force)
            guard !Task.isCancelled else { return }
            facilities = snapshot.facilities
            showingCachedData = snapshot.fromCache && snapshot.fetchedAt == .distantPast
            await recompute()
            if facilities.isEmpty {
                loadState = .empty
                await discoverIfNeeded(center: box.center)
            } else {
                loadState = showingCachedData ? .offline : .loaded
            }
            scheduleRefinement()
        } catch is CancellationError {
        } catch let error as APIError where error.isConnectivity {
            loadState = .offline
        } catch {
            loadState = .error((error as? LocalizedError)?.errorDescription ?? "Couldn't load courts.")
        }
    }

    private func discoverIfNeeded(center: GeoPoint) async {
        guard !env.isDemo else { return }
        discoveryInProgress = true
        defer { discoveryInProgress = false }
        env.log("region_discovery")
        if let result = await env.facilityService.discoverIfEmpty(center: center), result.action == "imported",
           (result.inserted ?? 0) > 0 {
            await load(force: true)
        }
    }

    /// Re-ranks with current preferences, location, travel and weather caches. Cheap; no network.
    func recompute() async {
        let origin = self.origin
        let filtered = facilities.filter { filters.includes($0, origin: origin) }
        var set = await env.recommendationService.recommend(filtered, origin: origin, prefs: env.preferences.prefs,
                                                            mode: env.preferences.sortMode)
        set.ranked = set.ranked.filter(filters.includes)
        set.picks = set.picks.filter(filters.includes)
        set.notAvailable = set.notAvailable.filter(filters.includes)
        recommendations = set
        env.visits.update(recommendations: set.all)
    }

    /// Weather and routed ETAs arrive after first paint, then re-rank once.
    private func scheduleRefinement() {
        refineTask?.cancel()
        let facilities = self.facilities, origin = self.origin, service = env.recommendationService
        let current = recommendations
        refineTask = Task {
            async let weatherChanged = service.refreshWeather(for: facilities)
            async let travelChanged: Bool = origin == nil ? false : service.refineTravel(for: current, origin: origin!)
            _ = await (weatherChanged, travelChanged)
            // Always re-rank: an earlier, cancelled refinement may have filled the caches.
            guard !Task.isCancelled else { return }
            await recompute()
        }
    }

    private func filtersChanged() {
        env.store.save(filters, key: StoreKeys.filters)
        env.log("filters_changed", props: ["count": .int(filters.activeCount)])
        Task { await recompute() }
    }

    func preferencesChanged() {
        Task { await recompute() }
    }

    @ObservationIgnored private var lastRankedOrigin: GeoPoint?

    /// Re-rank when the user's position changes enough to matter for travel time (≥ 300 m).
    func locationChanged(_ point: GeoPoint?) {
        guard let point else { return }
        if let last = lastRankedOrigin, GeoMath.distanceMeters(last, point) < 300 { return }
        lastRankedOrigin = point
        Task {
            await recompute()
            scheduleRefinement()
        }
    }
}

extension GeoBoundingBox {
    init(region: MKCoordinateRegion) {
        self.init(center: GeoPoint(latitude: region.center.latitude, longitude: region.center.longitude),
                  latitudeDelta: region.span.latitudeDelta, longitudeDelta: region.span.longitudeDelta)
    }
}

extension GeoPoint {
    var coordinate: CLLocationCoordinate2D { CLLocationCoordinate2D(latitude: latitude, longitude: longitude) }
}

extension Facility {
    var clCoordinate: CLLocationCoordinate2D { CLLocationCoordinate2D(latitude: latitude, longitude: longitude) }
}
