import Foundation
import PickleCore

/// Region-aware facility loading. Fetches a padded bounding box and serves later camera moves from that
/// cache while the visible region stays inside it, so small pans/zooms never hit the network.
actor FacilityService {
    struct Snapshot: Sendable {
        var facilities: [Facility]
        var fetchedBox: GeoBoundingBox
        var fetchedAt: Date
        var fromCache: Bool
    }

    private let repository: FacilityRepository
    private let store: LocalStore
    private var current: Snapshot?
    private var discoveryAttempts: [String: Date]
    private let ttl: TimeInterval = 120
    private let discoveryCooldown: TimeInterval = 24 * 3600

    init(repository: FacilityRepository, store: LocalStore) {
        self.repository = repository
        self.store = store
        self.discoveryAttempts = store.load([String: Date].self, key: StoreKeys.regionDiscovery) ?? [:]
    }

    var timeZone: String { TimeZone.current.identifier }

    /// - Parameter force: bypass the cache (pull to refresh, after submitting a report).
    func facilities(visible: GeoBoundingBox, force: Bool = false) async throws -> Snapshot {
        if !force, let c = current, c.fetchedBox.contains(visible), Date().timeIntervalSince(c.fetchedAt) < ttl,
           visible.latitudeDelta > c.fetchedBox.latitudeDelta * 0.15 {
            return Snapshot(facilities: c.facilities.filter { visible.padded(by: 0.1).contains($0.coordinate) },
                            fetchedBox: c.fetchedBox, fetchedAt: c.fetchedAt, fromCache: true)
        }
        // Clamp to what the backend accepts (≤ 3° each side).
        var box = visible.padded(by: 0.25)
        if box.latitudeDelta > 2.9 || box.longitudeDelta > 2.9 {
            box = GeoBoundingBox(center: visible.center, latitudeDelta: min(box.latitudeDelta, 2.9), longitudeDelta: min(box.longitudeDelta, 2.9))
        }
        do {
            let list = try await repository.nearby(in: box, timeZone: timeZone)
            let snap = Snapshot(facilities: list, fetchedBox: box, fetchedAt: Date(), fromCache: false)
            current = snap
            store.save(list, key: StoreKeys.facilityCache)
            return snap
        } catch let error as APIError where error.isConnectivity {
            // Offline: fall back to the last loaded facilities so the map is never blank.
            if let c = current { return Snapshot(facilities: c.facilities, fetchedBox: c.fetchedBox, fetchedAt: c.fetchedAt, fromCache: true) }
            if let saved = store.load([Facility].self, key: StoreKeys.facilityCache), !saved.isEmpty {
                return Snapshot(facilities: saved, fetchedBox: box, fetchedAt: .distantPast, fromCache: true)
            }
            throw error
        }
    }

    func invalidate() { current = nil }

    func detail(id: UUID) async throws -> FacilityDetail? {
        try await repository.detail(id: id, timeZone: timeZone)
    }

    func search(_ query: String, near: GeoPoint?) async throws -> [Facility] {
        try await repository.search(query, near: near, timeZone: timeZone)
    }

    /// Asks the backend to backfill an empty region. Client-side throttle: once per geohash-4 cell per day.
    /// The server applies its own authoritative throttling and caching.
    func discoverIfEmpty(center: GeoPoint) async -> RegionDiscoveryResult? {
        let cell = GeoMath.geohash(center, precision: 4)
        if let last = discoveryAttempts[cell], Date().timeIntervalSince(last) < discoveryCooldown { return nil }
        discoveryAttempts[cell] = Date()
        store.save(discoveryAttempts, key: StoreKeys.regionDiscovery)
        let result = try? await repository.requestRegionDiscovery(at: center)
        if result?.action == "imported" { current = nil }
        return result
    }
}
