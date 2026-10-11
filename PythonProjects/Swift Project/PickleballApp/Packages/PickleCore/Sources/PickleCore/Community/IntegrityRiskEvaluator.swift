import Foundation

/// A previously submitted report, as remembered on-device (facility location only — never a trail).
public struct ReportHistoryEntry: Codable, Hashable, Sendable {
    public var facilityID: UUID
    public var facilityLocation: GeoPoint
    public var at: Date
    public init(facilityID: UUID, facilityLocation: GeoPoint, at: Date) {
        self.facilityID = facilityID; self.facilityLocation = facilityLocation; self.at = at
    }
}

public enum IntegrityFlag: String, Hashable, Sendable, Codable {
    case simulatedLocation, poorAccuracy, staleFix, impossibleTravel, burst, manyFacilities
}

public struct IntegrityAssessment: Hashable, Sendable {
    /// 0 (very suspicious) … 1 (no concerns). Internal only — never shown to users.
    public var score: Double
    public var flags: Set<IntegrityFlag>
}

/// Mirrors the server's `compute_integrity_score` so behaviour can be unit-tested and so the client can
/// avoid sending reports that would certainly be discarded. The server value is the only one that counts.
public struct IntegrityRiskEvaluator: Sendable {
    public var maxPlausibleSpeedKmh = 150.0
    public var burstWindow: TimeInterval = 600
    public var burstLimit = 4
    public var facilitiesPerHourLimit = 3
    public var isProduction: Bool

    public init(isProduction: Bool) { self.isProduction = isProduction }

    public func assess(fix: LocationFix, facilityID: UUID, facilityLocation: GeoPoint,
                       history: [ReportHistoryEntry], now: Date) -> IntegrityAssessment {
        var score = 1.0
        var flags: Set<IntegrityFlag> = []

        if fix.isSimulatedBySoftware && isProduction { score *= 0.2; flags.insert(.simulatedLocation) }
        if fix.horizontalAccuracy > 65 { score *= 0.7; flags.insert(.poorAccuracy) }
        if now.timeIntervalSince(fix.timestamp) > 60 { score *= 0.8; flags.insert(.staleFix) }

        if let last = history.filter({ $0.at <= now }).max(by: { $0.at < $1.at }), last.facilityID != facilityID {
            let hours = max(now.timeIntervalSince(last.at) / 3600, 1.0 / 60)
            let km = GeoMath.distanceMeters(last.facilityLocation, facilityLocation) / 1000
            if km / hours > maxPlausibleSpeedKmh { score *= 0.25; flags.insert(.impossibleTravel) }
        }
        let recent = history.filter { now.timeIntervalSince($0.at) < burstWindow && $0.at <= now }
        if recent.count >= burstLimit { score *= 0.5; flags.insert(.burst) }
        let lastHourFacilities = Set(history.filter { now.timeIntervalSince($0.at) < 3600 && $0.at <= now }.map(\.facilityID))
            .union([facilityID])
        if lastHourFacilities.count > facilitiesPerHourLimit { score *= 0.5; flags.insert(.manyFacilities) }

        return IntegrityAssessment(score: max(0, min(1, score)), flags: flags)
    }
}
