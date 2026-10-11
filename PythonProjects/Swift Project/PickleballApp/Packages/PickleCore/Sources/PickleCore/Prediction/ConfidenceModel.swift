import Foundation

/// Evidence feeding the High / Medium / Low confidence label. No percentages are shown to users.
public struct ConfidenceInputs: Hashable, Sendable {
    /// Σ trust × decay over live observations.
    public var liveEffectiveWeight: Double = 0
    /// Observations younger than 30 minutes with meaningful trust.
    public var freshObservationCount: Int = 0
    /// 0...1, 1 = all live observations agree.
    public var agreement: Double = 1
    /// 0...1 share of live weight that was location-verified.
    public var verifiedShare: Double = 0
    public var historicalSamples: Int = 0
    public var usableCourtsKnown: Bool = false
    public var usesGenericPrior: Bool = false

    public init(liveEffectiveWeight: Double = 0, freshObservationCount: Int = 0, agreement: Double = 1,
                verifiedShare: Double = 0, historicalSamples: Int = 0, usableCourtsKnown: Bool = false,
                usesGenericPrior: Bool = false) {
        self.liveEffectiveWeight = liveEffectiveWeight; self.freshObservationCount = freshObservationCount
        self.agreement = agreement; self.verifiedShare = verifiedShare; self.historicalSamples = historicalSamples
        self.usableCourtsKnown = usableCourtsKnown; self.usesGenericPrior = usesGenericPrior
    }
}

public enum ConfidenceModel {
    public static func evidenceScore(_ i: ConfidenceInputs) -> Double {
        let live = i.liveEffectiveWeight * max(0, min(1, i.agreement)) * (0.5 + 0.5 * max(0, min(1, i.verifiedShare)))
        let historical = min(1, Double(i.historicalSamples) / 30)
        let configuration = i.usableCourtsKnown ? 0.2 : 0
        return live + historical + configuration
    }

    public static func level(_ i: ConfidenceInputs) -> ConfidenceLevel {
        let score = evidenceScore(i)
        if i.usesGenericPrior && i.liveEffectiveWeight < 0.5 { return .low }
        if score >= 2.0 && i.freshObservationCount >= 2 && i.agreement >= 0.6 { return .high }
        if score >= 0.8 { return .medium }
        return .low
    }

    /// Weighted agreement: 1 − 2·(weighted std-dev of occupancy values), clamped to 0...1.
    public static func agreement(values: [Double], weights: [Double]) -> Double {
        let total = weights.reduce(0, +)
        guard values.count >= 2, total > 0 else { return 1 }
        let mean = zip(values, weights).reduce(0) { $0 + $1.0 * $1.1 } / total
        let variance = zip(values, weights).reduce(0) { $0 + $1.1 * pow($1.0 - mean, 2) } / total
        return max(0, min(1, 1 - 2 * sqrt(variance)))
    }
}
