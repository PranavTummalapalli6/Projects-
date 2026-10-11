import Foundation

/// Everything about the user the recommendation pipeline may consider. All fields optional/soft.
public struct UserPreferences: Codable, Hashable, Sendable {
    public var skill: SkillBand
    public var costPreference: CostPreference
    public var prefersCompetitive: Bool?
    public var wantsBeginnerFriendly: Bool
    /// Facilities where the user says they are a member / resident / HOA owner.
    public var accessGrantedFacilityIDs: Set<UUID>

    public init(skill: SkillBand = .unknown, costPreference: CostPreference = .noPreference,
                prefersCompetitive: Bool? = nil, wantsBeginnerFriendly: Bool = false,
                accessGrantedFacilityIDs: Set<UUID> = []) {
        self.skill = skill; self.costPreference = costPreference; self.prefersCompetitive = prefersCompetitive
        self.wantsBeginnerFriendly = wantsBeginnerFriendly; self.accessGrantedFacilityIDs = accessGrantedFacilityIDs
    }
}

/// Travel estimate. `isEstimate` = straight-line heuristic rather than a routed ETA.
public struct TravelEstimate: Codable, Hashable, Sendable {
    public var minutes: Double
    public var distanceMeters: Double
    public var isEstimate: Bool
    public init(minutes: Double, distanceMeters: Double, isEstimate: Bool) {
        self.minutes = minutes; self.distanceMeters = distanceMeters; self.isEstimate = isEstimate
    }

    /// Heuristic for when no routed ETA is available: 1.35× detour factor at ~28 mph urban average,
    /// plus 3 minutes for parking/walking.
    public static func straightLine(meters: Double) -> TravelEstimate {
        let roadMeters = meters * 1.35
        let minutes = roadMeters / 1609.34 / 28 * 60 + 3
        return TravelEstimate(minutes: minutes, distanceMeters: meters, isEstimate: true)
    }
}
