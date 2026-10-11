import Foundation

public enum WindCategory: String, Codable, Hashable, Sendable, CaseIterable {
    case calm, breezy, windy, veryWindy = "very_windy"

    public var displayName: String {
        switch self {
        case .calm: "Calm"
        case .breezy: "Breezy"
        case .windy: "Windy"
        case .veryWindy: "Very windy"
        }
    }
}

public enum PlayabilityImpact: Int, Codable, Hashable, Sendable, Comparable {
    case none = 0, minor, significant
    public static func < (l: Self, r: Self) -> Bool { l.rawValue < r.rawValue }
}

public struct WeatherAssessment: Hashable, Sendable {
    public var windCategory: WindCategory
    public var effectiveWindMph: Double
    public var rainLikely: Bool
    public var recentRain: Bool
    public var extremeHeat: Bool
    public var cold: Bool
    public var isDark: Bool
    public var demandMultiplier: Double
    public var impact: PlayabilityImpact
    /// e.g. "Wind may noticeably affect play"
    public var headline: String?
}

public enum WeatherAssessor {
    public static func windCategory(windMph: Double, gustMph: Double?, thresholds: WindThresholds) -> (WindCategory, Double) {
        let effective = max(windMph, (gustMph ?? 0) * thresholds.gustFactor)
        let category: WindCategory
        switch effective {
        case ..<thresholds.breezyMph: category = .calm
        case ..<thresholds.windyMph: category = .breezy
        case ..<thresholds.veryWindyMph: category = .windy
        default: category = .veryWindy
        }
        return (category, effective)
    }

    /// Indoor facilities are not affected by weather; pass `isOutdoor: false` to get a neutral result.
    public static func assess(_ w: WeatherConditions?, isOutdoor: Bool, config: PredictionConfig = .default) -> WeatherAssessment {
        guard let w, isOutdoor else {
            return WeatherAssessment(windCategory: .calm, effectiveWindMph: 0, rainLikely: false, recentRain: false,
                                     extremeHeat: false, cold: false, isDark: false, demandMultiplier: 1,
                                     impact: .none, headline: nil)
        }
        let (cat, eff) = windCategory(windMph: w.windMph, gustMph: w.gustMph, thresholds: config.wind)
        let rainLikely = w.precipitationChance >= 0.6
        let recentRain = w.precipitationLast3hMm >= 0.5
        let heat = (w.apparentTemperatureF ?? w.temperatureF) >= 95
        let cold = w.temperatureF <= 38

        var multiplier = 1.0
        if rainLikely { multiplier *= config.rainDemandMultiplier }
        if cat == .veryWindy { multiplier *= config.veryWindyDemandMultiplier }
        else if cat == .windy { multiplier *= config.windyDemandMultiplier }
        if heat { multiplier *= config.extremeHeatDemandMultiplier }

        var impact = PlayabilityImpact.none
        var headline: String?
        if rainLikely { impact = .significant; headline = "Rain likely — courts may be wet" }
        else if recentRain { impact = .minor; headline = "Recent rain — courts may be damp" }
        if cat == .veryWindy { impact = max(impact, .significant); headline = headline ?? "Very windy — expect a tough outdoor game" }
        else if cat == .windy { impact = max(impact, .minor); headline = headline ?? "Wind may noticeably affect play" }
        if heat { impact = max(impact, .minor); headline = headline ?? "Extreme heat — bring water" }
        if cold { impact = max(impact, .minor); headline = headline ?? "Cold conditions" }

        return WeatherAssessment(windCategory: cat, effectiveWindMph: eff, rainLikely: rainLikely, recentRain: recentRain,
                                 extremeHeat: heat, cold: cold, isDark: !w.isDaylight, demandMultiplier: multiplier,
                                 impact: impact, headline: headline)
    }
}
