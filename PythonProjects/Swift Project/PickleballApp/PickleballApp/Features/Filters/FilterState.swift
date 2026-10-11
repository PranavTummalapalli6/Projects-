import Foundation
import PickleCore

/// Map/list filters. Static facility facets are checked before ranking; live facets after.
struct FilterState: Codable, Equatable, Sendable {
    enum Setting: String, Codable, CaseIterable, Identifiable, Sendable {
        case any, indoor, outdoor
        var id: String { rawValue }
        var label: String { rawValue.capitalized }
    }

    var likelyAvailableOnly = false
    var dedicatedOnly = false
    var setting: Setting = .any
    var lightsOnly = false
    var publicWalkOnOnly = false
    var freeOnly = false
    var reservationAvailable = false
    var openPlayOnly = false
    var skillMatchOnly = false
    var maxMiles: Double?
    var minCourts = 0

    var activeCount: Int {
        [likelyAvailableOnly, dedicatedOnly, setting != .any, lightsOnly, publicWalkOnOnly, freeOnly,
         reservationAvailable, openPlayOnly, skillMatchOnly, maxMiles != nil, minCourts > 0].filter { $0 }.count
    }

    var isActive: Bool { activeCount > 0 }

    /// Short summary for the persistent "filters active" chip.
    var summary: String {
        var parts: [String] = []
        if likelyAvailableOnly { parts.append("Available") }
        if freeOnly { parts.append("Free") }
        if dedicatedOnly { parts.append("Dedicated") }
        if setting != .any { parts.append(setting.label) }
        if let maxMiles { parts.append("≤\(Int(maxMiles)) mi") }
        if parts.isEmpty { return "\(activeCount) filter\(activeCount == 1 ? "" : "s")" }
        return parts.prefix(2).joined(separator: " · ") + (parts.count > 2 || activeCount > parts.count ? " +" : "")
    }

    func includes(_ f: Facility, origin: GeoPoint?) -> Bool {
        if dedicatedOnly && f.courtType != .dedicatedPickleball { return false }
        switch setting {
        case .indoor: if f.indoorOutdoor != .indoor && f.indoorOutdoor != .both { return false }
        case .outdoor: if f.indoorOutdoor == .indoor { return false }
        case .any: break
        }
        if lightsOnly && f.hasLights != true { return false }
        if publicWalkOnOnly && f.access.accessType != .publicWalkOn { return false }
        if freeOnly && f.cost.costType != .free { return false }
        if reservationAvailable && f.access.reservationAvailable != true { return false }
        if openPlayOnly && !(f.playSystem.isRotation || f.culture.contains { $0.tag == .openPlay && $0.share >= 0.3 }) { return false }
        if minCourts > 0 && (f.defaultPickleballCourts ?? f.totalPhysicalCourts ?? 0) < minCourts { return false }
        if let maxMiles, let origin, GeoMath.distanceMeters(origin, f.coordinate) / 1609.34 > maxMiles { return false }
        return true
    }

    func includes(_ r: FacilityRecommendation) -> Bool {
        if likelyAvailableOnly && (r.eligibility.status != .eligible || r.prediction.busyLevel > .moderate) { return false }
        if skillMatchOnly && !(r.fit.skillFit == .great || r.fit.skillFit == .good) { return false }
        return true
    }
}
