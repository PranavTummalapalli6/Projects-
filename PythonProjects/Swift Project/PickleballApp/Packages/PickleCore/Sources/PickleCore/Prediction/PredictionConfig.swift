import Foundation

/// All tunable constants for Prediction V1. Defaults are documented in docs/ARCHITECTURE.md §9;
/// production values can be overridden from the server's `app_config` table.
public struct PredictionConfig: Codable, Hashable, Sendable {
    /// Live observations lose half their weight every `halfLifeMinutes`.
    public var halfLifeMinutes: Double = 25
    /// Observations older than this are ignored entirely.
    public var liveMaxAgeMinutes: Double = 180
    /// Historical bucket reaches full weight at this many samples.
    public var historicalFullWeightSamples: Double = 20
    public var historicalMaxWeight: Double = 1.5
    /// Weight of the generic population prior when a facility has no history.
    public var priorWeight: Double = 0.3
    public var defaultGameMinutes: Double = 13
    public var playersPerGame: Double = 4
    /// Minimum override confidence to replace the default pickleball court count.
    public var usableCourtsOverrideMinConfidence: Double = 0.5
    public var assumedCourtsWhenUnknown: Int = 2

    public var rainDemandMultiplier: Double = 0.4
    public var veryWindyDemandMultiplier: Double = 0.7
    public var windyDemandMultiplier: Double = 0.85
    public var extremeHeatDemandMultiplier: Double = 0.75

    public var wind = WindThresholds()

    public init() {}

    public var decayLambda: Double { log(2) / halfLifeMinutes }

    public func decay(ageMinutes: Double) -> Double {
        guard ageMinutes >= 0 else { return 1 }
        return exp(-decayLambda * ageMinutes)
    }

    public static let `default` = PredictionConfig()
}

/// Configurable wind categories — there is no universal "unplayable" threshold.
public struct WindThresholds: Codable, Hashable, Sendable {
    public var breezyMph: Double = 8
    public var windyMph: Double = 13
    public var veryWindyMph: Double = 20
    /// Gusts count at this fraction toward the effective wind speed.
    public var gustFactor: Double = 0.75
    public init() {}
}
