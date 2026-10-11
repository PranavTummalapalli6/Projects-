import Foundation

public struct GeoPoint: Codable, Hashable, Sendable {
    public var latitude: Double
    public var longitude: Double
    public init(latitude: Double, longitude: Double) { self.latitude = latitude; self.longitude = longitude }

    public var isValid: Bool {
        (-90...90).contains(latitude) && (-180...180).contains(longitude)
            && !(abs(latitude) < 0.0001 && abs(longitude) < 0.0001) && latitude.isFinite && longitude.isFinite
    }
}

public struct GeoBoundingBox: Codable, Hashable, Sendable {
    public var minLatitude: Double
    public var minLongitude: Double
    public var maxLatitude: Double
    public var maxLongitude: Double

    public init(minLatitude: Double, minLongitude: Double, maxLatitude: Double, maxLongitude: Double) {
        self.minLatitude = minLatitude; self.minLongitude = minLongitude
        self.maxLatitude = maxLatitude; self.maxLongitude = maxLongitude
    }

    public init(center: GeoPoint, latitudeDelta: Double, longitudeDelta: Double) {
        self.init(minLatitude: center.latitude - latitudeDelta / 2, minLongitude: center.longitude - longitudeDelta / 2,
                  maxLatitude: center.latitude + latitudeDelta / 2, maxLongitude: center.longitude + longitudeDelta / 2)
    }

    public var center: GeoPoint {
        GeoPoint(latitude: (minLatitude + maxLatitude) / 2, longitude: (minLongitude + maxLongitude) / 2)
    }
    public var latitudeDelta: Double { maxLatitude - minLatitude }
    public var longitudeDelta: Double { maxLongitude - minLongitude }

    public func contains(_ p: GeoPoint) -> Bool {
        (minLatitude...maxLatitude).contains(p.latitude) && (minLongitude...maxLongitude).contains(p.longitude)
    }

    public func contains(_ other: GeoBoundingBox) -> Bool {
        other.minLatitude >= minLatitude && other.maxLatitude <= maxLatitude
            && other.minLongitude >= minLongitude && other.maxLongitude <= maxLongitude
    }

    /// Expands each side by `factor` of the span (0.25 → 1.5× total span).
    public func padded(by factor: Double) -> GeoBoundingBox {
        let dLat = latitudeDelta * factor, dLng = longitudeDelta * factor
        return GeoBoundingBox(minLatitude: max(-90, minLatitude - dLat), minLongitude: max(-180, minLongitude - dLng),
                              maxLatitude: min(90, maxLatitude + dLat), maxLongitude: min(180, maxLongitude + dLng))
    }
}

public enum GeoMath {
    public static let earthRadiusMeters = 6_371_008.8

    public static func distanceMeters(_ a: GeoPoint, _ b: GeoPoint) -> Double {
        let lat1 = a.latitude * .pi / 180, lat2 = b.latitude * .pi / 180
        let dLat = lat2 - lat1, dLng = (b.longitude - a.longitude) * .pi / 180
        let h = sin(dLat / 2) * sin(dLat / 2) + cos(lat1) * cos(lat2) * sin(dLng / 2) * sin(dLng / 2)
        return 2 * earthRadiusMeters * asin(min(1, sqrt(h)))
    }

    private static let base32 = Array("0123456789bcdefghjkmnpqrstuvwxyz")

    /// Standard geohash; precision 4 ≈ 39 × 20 km cells (used for region coverage).
    public static func geohash(_ p: GeoPoint, precision: Int = 4) -> String {
        var latRange = (-90.0, 90.0), lngRange = (-180.0, 180.0)
        var hash = "", bit = 0, ch = 0, even = true
        while hash.count < precision {
            if even {
                let mid = (lngRange.0 + lngRange.1) / 2
                if p.longitude >= mid { ch |= (1 << (4 - bit)); lngRange.0 = mid } else { lngRange.1 = mid }
            } else {
                let mid = (latRange.0 + latRange.1) / 2
                if p.latitude >= mid { ch |= (1 << (4 - bit)); latRange.0 = mid } else { latRange.1 = mid }
            }
            even.toggle()
            if bit < 4 { bit += 1 } else { hash.append(base32[ch]); bit = 0; ch = 0 }
        }
        return hash
    }
}
