import CoreLocation
import Observation
import PickleCore

/// Foreground location with contextual permission. Background location is never requested.
@Observable
@MainActor
final class LocationService: NSObject {
    enum Authorization: Equatable { case notDetermined, denied, restricted, authorized }

    private(set) var authorization: Authorization = .notDetermined
    private(set) var lastFix: LocationFix?
    private(set) var lastLocation: CLLocation?

    @ObservationIgnored private let manager = CLLocationManager()
    @ObservationIgnored private var fixContinuations: [CheckedContinuation<LocationFix?, Never>] = []
    @ObservationIgnored private let fixedLocation: CLLocation?
    @ObservationIgnored private var updatesActive = false
    @ObservationIgnored var onFix: ((LocationFix) -> Void)?

    /// - Parameter fixedLocation: used by UI tests / previews to bypass Core Location entirely.
    init(fixedLocation: CLLocation? = nil) {
        self.fixedLocation = fixedLocation
        super.init()
        if let fixedLocation {
            authorization = .authorized
            apply(fixedLocation)
            return
        }
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
        manager.distanceFilter = 25
        manager.pausesLocationUpdatesAutomatically = true
        authorization = Self.map(manager.authorizationStatus)
    }

    var isAuthorized: Bool { authorization == .authorized }

    /// Only called after the user has seen the in-app explanation (LocationPrimerView).
    func requestPermission() {
        guard fixedLocation == nil, authorization == .notDetermined else { return }
        manager.requestWhenInUseAuthorization()
    }

    func startUpdates() {
        guard fixedLocation == nil, isAuthorized, !updatesActive else { return }
        updatesActive = true
        manager.startUpdatingLocation()
    }

    func stopUpdates() {
        guard updatesActive else { return }
        updatesActive = false
        manager.stopUpdatingLocation()
    }

    /// A fresh fix (≤ 30 s old) or waits up to `timeout` for one.
    func currentFix(timeout: TimeInterval = 8) async -> LocationFix? {
        if let fix = lastFix, Date().timeIntervalSince(fix.timestamp) < 30 || fixedLocation != nil {
            return fixedLocation != nil ? LocationFix(point: fix.point, horizontalAccuracy: fix.horizontalAccuracy, timestamp: Date(),
                                                      isSimulatedBySoftware: fix.isSimulatedBySoftware) : fix
        }
        guard isAuthorized else { return nil }
        manager.requestLocation()
        return await withCheckedContinuation { continuation in
            fixContinuations.append(continuation)
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(timeout))
                self.resumeAll(with: self.lastFix)
            }
        }
    }

    private func resumeAll(with fix: LocationFix?) {
        let pending = fixContinuations
        fixContinuations.removeAll()
        pending.forEach { $0.resume(returning: fix) }
    }

    private func apply(_ location: CLLocation) {
        lastLocation = location
        let fix = LocationFix(
            point: GeoPoint(latitude: location.coordinate.latitude, longitude: location.coordinate.longitude),
            horizontalAccuracy: location.horizontalAccuracy,
            timestamp: location.timestamp,
            isSimulatedBySoftware: location.sourceInformation?.isSimulatedBySoftware ?? false,
            isProducedByAccessory: location.sourceInformation?.isProducedByAccessory ?? false)
        lastFix = fix
        resumeAll(with: fix)
        onFix?(fix)
    }

    private static func map(_ s: CLAuthorizationStatus) -> Authorization {
        switch s {
        case .notDetermined: .notDetermined
        case .denied: .denied
        case .restricted: .restricted
        case .authorizedAlways, .authorizedWhenInUse: .authorized
        @unknown default: .denied
        }
    }
}

extension LocationService: CLLocationManagerDelegate {
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            self.authorization = Self.map(status)
            if self.isAuthorized { self.manager.requestLocation() }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let best = locations.last else { return }
        Task { @MainActor in self.apply(best) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in self.resumeAll(with: self.lastFix) }
    }
}
