import Foundation

/// A location fix as reported by Core Location, reduced to what verification needs.
public struct LocationFix: Hashable, Sendable {
    public var point: GeoPoint
    public var horizontalAccuracy: Double
    public var timestamp: Date
    public var isSimulatedBySoftware: Bool
    public var isProducedByAccessory: Bool

    public init(point: GeoPoint, horizontalAccuracy: Double, timestamp: Date,
                isSimulatedBySoftware: Bool = false, isProducedByAccessory: Bool = false) {
        self.point = point; self.horizontalAccuracy = horizontalAccuracy; self.timestamp = timestamp
        self.isSimulatedBySoftware = isSimulatedBySoftware; self.isProducedByAccessory = isProducedByAccessory
    }
}

public enum LocationCheck: Hashable, Sendable {
    case nearby(distanceMeters: Double)
    case tooFar(distanceMeters: Double)
    case imprecise
    case stale
    case unavailable

    public var allowsLiveReport: Bool { if case .nearby = self { true } else { false } }

    public var userMessage: String {
        switch self {
        case .nearby: "You're at this facility"
        case .tooFar(let d): String(format: "Live reports open when you're at the courts (%.1f mi away)", d / 1609.34)
        case .imprecise: "Waiting for a more precise location…"
        case .stale: "Updating your location…"
        case .unavailable: "Turn on location to share live court status"
        }
    }
}

/// Client pre-check that gates the live-report button. The server repeats the check and decides trust.
public struct LocationVerifier: Sendable {
    public var facilityRadiusMeters = 250.0
    public var accuracyAllowanceCap = 75.0
    public var maxAccuracy = 150.0
    public var maxFixAge: TimeInterval = 120

    public init() {}

    public func check(_ fix: LocationFix?, facility: GeoPoint, now: Date) -> LocationCheck {
        guard let fix, fix.point.isValid, fix.horizontalAccuracy >= 0 else { return .unavailable }
        if now.timeIntervalSince(fix.timestamp) > maxFixAge { return .stale }
        if fix.horizontalAccuracy > maxAccuracy { return .imprecise }
        let d = GeoMath.distanceMeters(fix.point, facility)
        return d <= facilityRadiusMeters + min(fix.horizontalAccuracy, accuracyAllowanceCap) ? .nearby(distanceMeters: d) : .tooFar(distanceMeters: d)
    }
}
