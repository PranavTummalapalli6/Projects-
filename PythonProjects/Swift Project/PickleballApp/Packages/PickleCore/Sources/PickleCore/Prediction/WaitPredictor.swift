import Foundation

/// Honest wait range. `high == nil` means open-ended ("60+ min").
public struct WaitRange: Hashable, Sendable, Codable {
    public var low: Int
    public var high: Int?

    public init(low: Int, high: Int?) { self.low = low; self.high = high }

    public var midpoint: Double {
        guard let high else { return Double(low) + 20 }
        return Double(low + high) / 2
    }
    /// Upper bound used for time-to-play arithmetic (open-ended treated as +30 min).
    public var effectiveHigh: Int { high ?? low + 30 }

    public var label: String {
        guard let high else { return "\(low)+ min" }
        return "\(low)–\(high) min"
    }

    static let ladder: [(threshold: Double, range: WaitRange)] = [
        (4, WaitRange(low: 0, high: 5)),
        (10, WaitRange(low: 5, high: 15)),
        (15, WaitRange(low: 10, high: 20)),
        (22, WaitRange(low: 15, high: 30)),
        (32, WaitRange(low: 20, high: 40)),
        (40, WaitRange(low: 30, high: 45)),
        (55, WaitRange(low: 45, high: 60)),
        (.infinity, WaitRange(low: 60, high: nil)),
    ]

    /// Snaps a raw estimate to the nearest honest bucket; low confidence widens it.
    public static func snapped(rawLow: Double, rawHigh: Double, confidence: ConfidenceLevel) -> WaitRange {
        let mid = max(0, (rawLow + rawHigh) / 2)
        let index = ladder.firstIndex { mid < $0.threshold } ?? ladder.count - 1
        var range = ladder[index].range
        if confidence == .low, index + 1 < ladder.count {
            range = WaitRange(low: range.low, high: ladder[index + 1].range.high)
        }
        return range
    }
}

public enum BusyLevel: Int, Hashable, Sendable, Codable, Comparable {
    case quiet = 0, moderate, busy, veryBusy
    public static func < (l: Self, r: Self) -> Bool { l.rawValue < r.rawValue }

    public var displayName: String {
        switch self {
        case .quiet: "Likely available"
        case .moderate: "Moderate"
        case .busy: "Busy"
        case .veryBusy: "Very busy"
        }
    }

    public static func from(occupancy: Double, queuePerCourt: Double) -> BusyLevel {
        if queuePerCourt >= 0.5 { return .veryBusy }
        if occupancy >= 0.9 { return .busy }
        if occupancy >= 0.7 { return .moderate }
        return .quiet
    }
}

public enum PredictionBasis: String, Hashable, Sendable, Codable {
    /// Recent community reports dominate.
    case live
    /// Facility's own historical pattern.
    case historical
    /// Generic population prior (no facility data).
    case prior
    case blended

    public var displayName: String {
        switch self {
        case .live: "Live reports"
        case .historical: "Historical pattern"
        case .prior: "General estimate"
        case .blended: "Recent reports + history"
        }
    }
}

public enum UsableCourtsSource: String, Hashable, Sendable, Codable {
    case reported, configured, physical, assumed
}

public struct WaitPrediction: Hashable, Sendable {
    public var facilityID: UUID
    public var usableCourts: Int
    public var usableCourtsSource: UsableCourtsSource
    public var occupancy: Double
    public var queuePerCourt: Double
    public var wait: WaitRange
    public var rawWaitLow: Double
    public var rawWaitHigh: Double
    public var confidence: ConfidenceLevel
    public var basis: PredictionBasis
    public var busyLevel: BusyLevel
    public var paddleStack: PaddleStackLevel?
    public var newestLiveAgeMinutes: Double?
    public var explanation: [String]

    public var hasLiveData: Bool { newestLiveAgeMinutes != nil }
}

/// Prediction V1: explainable statistical blend of history, live reports, paddle stack,
/// facility configuration and weather. Pure and deterministic — see docs §9.
public struct WaitPredictor: Sendable {
    public var config: PredictionConfig

    public init(config: PredictionConfig = .default) { self.config = config }

    public func usableCourts(for facility: Facility, at now: Date) -> (Int, UsableCourtsSource) {
        var count: Int
        var source: UsableCourtsSource
        let reported = facility.overrides
            .filter { $0.kind == .usableCourts && $0.isActive(at: now) && $0.confidence >= config.usableCourtsOverrideMinConfidence }
            .max { $0.startsAt < $1.startsAt }
        if let reported, let value = reported.value {
            count = value; source = .reported
        } else if let d = facility.defaultPickleballCourts {
            count = d; source = .configured
        } else if let t = facility.totalPhysicalCourts {
            count = t; source = .physical
        } else {
            count = config.assumedCourtsWhenUnknown; source = .assumed
        }
        // Partial blackouts (e.g. 2 courts reserved for a lesson) reduce what's usable.
        let removed = facility.blackouts
            .filter { $0.isActive(at: now) && $0.isConfirmed }
            .compactMap(\.courtsAffected).reduce(0, +)
        count = max(0, count - removed)
        return (count, source)
    }

    public func predict(facility: Facility, now: Date = Date(), weather: WeatherConditions? = nil) -> WaitPrediction {
        let tz = facility.timeZone.flatMap(TimeZone.init(identifier:)) ?? .current
        let (dow, bucket) = TimeBuckets.bucket(for: now, timeZone: tz)
        let (usable, courtsSource) = usableCourts(for: facility, at: now)
        var explanation: [String] = []

        // 1. Historical or prior signal.
        var histOcc: Double
        var histWeight: Double
        var histSamples = 0
        var usesPrior = false
        if let h = facility.historicalNow, h.sampleCount > 0 {
            histOcc = h.avgOccupancy
            histSamples = h.sampleCount
            histWeight = min(config.historicalMaxWeight, Double(h.sampleCount) / config.historicalFullWeightSamples)
            explanation.append("Usually \(Self.describe(occupancy: histOcc)) at this time")
        } else {
            histOcc = OccupancyPrior.occupancy(dayOfWeek: dow, bucket: bucket, indoor: facility.indoorOutdoor == .indoor)
            histWeight = config.priorWeight
            usesPrior = true
        }
        let weatherAssessment = WeatherAssessor.assess(weather, isOutdoor: facility.indoorOutdoor != .indoor, config: config)
        histOcc *= weatherAssessment.demandMultiplier
        let histQueue = max(0, histOcc - 0.85) * 4

        // 2. Live observations (decayed, trust-weighted by the server).
        var occValues: [Double] = [], occWeights: [Double] = [], queueValues: [Double] = []
        var verifiedWeight = 0.0, fresh = 0
        var paddleSum = 0.0, paddleWeight = 0.0
        var newestAge: Double?
        for o in facility.live?.observations ?? [] where o.ageMinutes <= config.liveMaxAgeMinutes {
            let w = max(0, o.weight) * config.decay(ageMinutes: o.ageMinutes)
            guard w > 0.001 else { continue }
            newestAge = min(newestAge ?? .infinity, o.ageMinutes)
            if o.ageMinutes <= 30 && o.weight >= 0.3 { fresh += 1 }
            if o.locationVerified { verifiedWeight += w }
            switch o.kind {
            case .paddleStack:
                if let p = o.paddles { paddleSum += p * w; paddleWeight += w }
            case .occupancy, .unknown:
                var occ: Double?
                var queue: Double?
                if let implied = o.status?.implied { occ = implied.occupancy; queue = implied.queuePerCourt }
                if let occupied = o.occupiedCourts, usable > 0 { occ = min(1, Double(occupied) / Double(usable)) }
                if let groups = o.groupsWaiting, usable > 0 { queue = Double(groups) / Double(usable) }
                if let p = o.paddles { paddleSum += p * w; paddleWeight += w }
                guard let occ else { continue }
                occValues.append(occ); occWeights.append(w); queueValues.append(queue ?? 0)
            }
        }
        let liveWeight = occWeights.reduce(0, +) + paddleWeight
        let liveOccWeight = occWeights.reduce(0, +)

        // 3. Blend.
        let occupancy: Double
        let queue: Double
        if liveOccWeight > 0 {
            let wSum = histWeight + liveOccWeight
            occupancy = (histOcc * histWeight + zip(occValues, occWeights).reduce(0) { $0 + $1.0 * $1.1 }) / wSum
            queue = (histQueue * histWeight + zip(queueValues, occWeights).reduce(0) { $0 + $1.0 * $1.1 }) / wSum
        } else {
            occupancy = histOcc
            queue = histQueue
        }
        let paddlesEstimate: Double? = paddleWeight > 0 ? paddleSum / paddleWeight : nil

        let basis: PredictionBasis
        if liveWeight > histWeight * 2 { basis = .live }
        else if liveWeight > 0 { basis = .blended }
        else if usesPrior { basis = .prior }
        else { basis = .historical }

        // 4. Wait estimate.
        var rawLow = 0.0, rawHigh = 0.0
        var paddleLevel: PaddleStackLevel?
        if usable == 0 {
            rawLow = 60; rawHigh = 120
            explanation.append("No courts currently usable for pickleball")
        } else if facility.playSystem.isRotation {
            let perGame = config.playersPerGame
            let paddles = paddlesEstimate ?? queue * Double(usable) * perGame
            paddleLevel = PaddleStackLevel.from(paddles: paddles)
            let gameMinutes = facility.typicalGameMinutes ?? config.defaultGameMinutes
            if paddles < 1 && occupancy < 0.9 {
                rawLow = 0; rawHigh = 4
            } else {
                let gamesAhead = paddles / (perGame * Double(usable))
                rawLow = max(0, gamesAhead - 0.5) * gameMinutes * 0.8
                rawHigh = (gamesAhead + 0.5) * gameMinutes * 1.25
            }
            if paddlesEstimate != nil {
                explanation.append("Paddle stack: \(paddleLevel?.displayName.lowercased() ?? "unknown") across \(usable) courts")
            }
        } else {
            let session = facility.sessionStats ?? .default
            if occupancy < 0.9 {
                rawLow = 0; rawHigh = 5 * max(0.2, occupancy)
            } else {
                let queuedGroups = queue * Double(usable)
                let factor = (queuedGroups + 1) / Double(usable + 1)
                rawLow = factor * session.p25Minutes
                rawHigh = factor * session.p75Minutes
            }
        }

        // 5. Confidence.
        let inputs = ConfidenceInputs(
            liveEffectiveWeight: liveWeight,
            freshObservationCount: fresh,
            agreement: ConfidenceModel.agreement(values: occValues, weights: occWeights),
            verifiedShare: liveWeight > 0 ? verifiedWeight / liveWeight : 0,
            historicalSamples: histSamples,
            usableCourtsKnown: courtsSource == .reported || courtsSource == .configured,
            usesGenericPrior: usesPrior)
        let confidence = ConfidenceModel.level(inputs)
        let wait = WaitRange.snapped(rawLow: rawLow, rawHigh: rawHigh, confidence: confidence)

        if let age = newestAge { explanation.insert("Updated \(Int(age.rounded())) min ago", at: 0) }
        if usesPrior && liveWeight == 0 { explanation.append("Not enough reports yet — general estimate") }
        if let headline = weatherAssessment.headline { explanation.append(headline) }

        return WaitPrediction(
            facilityID: facility.id, usableCourts: usable, usableCourtsSource: courtsSource,
            occupancy: occupancy, queuePerCourt: queue, wait: wait, rawWaitLow: rawLow, rawWaitHigh: rawHigh,
            confidence: confidence, basis: basis,
            busyLevel: BusyLevel.from(occupancy: occupancy, queuePerCourt: queue),
            paddleStack: paddleLevel, newestLiveAgeMinutes: newestAge, explanation: explanation)
    }

    static func describe(occupancy: Double) -> String {
        switch occupancy {
        case ..<0.4: "quiet"
        case ..<0.7: "moderately busy"
        case ..<0.95: "busy"
        default: "very busy"
        }
    }
}
