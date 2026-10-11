import Foundation
import MapKit
import PickleCore

/// Travel time for recommendation ranking. Straight-line estimates for everything (free, instant);
/// routed MapKit ETAs only for the top few candidates, cached, to stay within Apple's throttles.
actor TravelTimeService {
    private struct Key: Hashable { let facility: UUID; let originCell: String }
    private var cache: [Key: (TravelEstimate, Date)] = [:]
    private let ttl: TimeInterval = 600
    private let routedEnabled: Bool

    init(routedEnabled: Bool = true) { self.routedEnabled = routedEnabled }

    nonisolated func estimate(from origin: GeoPoint, to facility: Facility) -> TravelEstimate {
        TravelEstimate.straightLine(meters: GeoMath.distanceMeters(origin, facility.coordinate))
    }

    func cached(from origin: GeoPoint, to id: UUID) -> TravelEstimate? {
        let key = Key(facility: id, originCell: GeoMath.geohash(origin, precision: 6))
        guard let (value, at) = cache[key], Date().timeIntervalSince(at) < ttl else { return nil }
        return value
    }

    /// Routed driving ETA; falls back to the straight-line estimate on any failure.
    func routed(from origin: GeoPoint, to facility: Facility) async -> TravelEstimate {
        let key = Key(facility: facility.id, originCell: GeoMath.geohash(origin, precision: 6))
        if let (value, at) = cache[key], Date().timeIntervalSince(at) < ttl { return value }
        let fallback = estimate(from: origin, to: facility)
        guard routedEnabled else { return fallback }
        let request = MKDirections.Request()
        request.source = MKMapItem(placemark: MKPlacemark(coordinate: CLLocationCoordinate2D(latitude: origin.latitude, longitude: origin.longitude)))
        request.destination = MKMapItem(placemark: MKPlacemark(coordinate: CLLocationCoordinate2D(latitude: facility.latitude, longitude: facility.longitude)))
        request.transportType = .automobile
        do {
            let eta = try await MKDirections(request: request).calculateETA()
            let value = TravelEstimate(minutes: eta.expectedTravelTime / 60 + 2, distanceMeters: eta.distance, isEstimate: false)
            cache[key] = (value, Date())
            return value
        } catch {
            return fallback
        }
    }
}
