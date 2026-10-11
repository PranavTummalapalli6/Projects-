import Foundation
@testable import PickleCore

enum Fixtures {
    static let utc = TimeZone(identifier: "UTC")!
    /// Wednesday 2026-10-07 18:00 UTC
    static let wednesdayEvening: Date = {
        var c = DateComponents(); c.year = 2026; c.month = 10; c.day = 7; c.hour = 18; c.minute = 0
        var cal = Calendar(identifier: .gregorian); cal.timeZone = utc
        return cal.date(from: c)!
    }()

    static func facility(
        name: String = "Hanson Regional Park", courts: Int? = 6, pickleball: Int? = 4,
        play: PlaySystem = .stayUntilFinished, access: AccessType = .publicWalkOn, cost: AccessCostType = .free,
        indoor: IndoorOutdoor = .outdoor, live: [LiveObservation] = [], history: HistoricalBucket? = nil,
        skill: SkillSummary? = nil, hours: [FacilityHours] = [], lat: Double = 38.85, lng: Double = -77.30
    ) -> Facility {
        Facility(name: name, latitude: lat, longitude: lng, timeZone: "UTC",
                 totalPhysicalCourts: courts, defaultPickleballCourts: pickleball,
                 courtType: .dedicatedPickleball, indoorOutdoor: indoor, hasLights: true,
                 playSystem: play, access: FacilityAccess(accessType: access), cost: FacilityCost(costType: cost),
                 hours: hours, skill: skill, historicalNow: history,
                 live: live.isEmpty ? nil : LiveSignals(observations: live))
    }

    static func skill(_ pairs: [(SkillBand, Double)], count: Int = 25) -> SkillSummary {
        SkillSummary(bands: pairs.map { SkillBandWeight(band: $0.0, weight: $0.1) }, observationCount: count, newestDaysAgo: 3)
    }
}
