import Foundation

public enum SortMode: String, CaseIterable, Hashable, Sendable, Codable, Identifiable {
    case bestOverall = "best_overall"
    case fastestToPlay = "fastest_to_play"
    case closest
    case shortestWait = "shortest_wait"
    case bestSkillMatch = "best_skill_match"
    case mostCourts = "most_courts"

    public var id: String { rawValue }
    public var displayName: String {
        switch self {
        case .bestOverall: "Best overall"
        case .fastestToPlay: "Fastest to play"
        case .closest: "Closest"
        case .shortestWait: "Shortest wait"
        case .bestSkillMatch: "Best skill match"
        case .mostCourts: "Most courts"
        }
    }
}

public enum RecommendationBadge: String, Hashable, Sendable, CaseIterable {
    case bestMatch, fastest, bestFree, reservable

    public var displayName: String {
        switch self {
        case .bestMatch: "BEST MATCH"
        case .fastest: "FASTEST TO PLAY"
        case .bestFree: "BEST FREE OPTION"
        case .reservable: "RESERVABLE OPTION"
        }
    }
}

public enum CostFit: Hashable, Sendable {
    case free, paid(Double?), membership, unknown, outsidePreference

    public var label: String {
        switch self {
        case .free: "Free"
        case .paid(let price): price.map { String(format: "$%.0f", $0) } ?? "Paid"
        case .membership: "Membership"
        case .unknown: "Cost unknown"
        case .outsidePreference: "Paid"
        }
    }
}

/// One explainable ranking component expressed in minutes-equivalent.
public struct ScoreComponent: Hashable, Sendable {
    public var label: String
    public var minutes: Double
}

public struct TimeToPlay: Hashable, Sendable {
    public var lowMinutes: Double
    public var highMinutes: Double
    public var midMinutes: Double { (lowMinutes + highMinutes) / 2 }
    public var label: String { "\(Int(lowMinutes.rounded()))–\(Int(highMinutes.rounded())) min" }
}

public struct FacilityRecommendation: Hashable, Sendable, Identifiable {
    public var facility: Facility
    public var eligibility: Eligibility
    public var fit: PlayerFit
    public var prediction: WaitPrediction
    public var travel: TravelEstimate?
    public var timeToPlay: TimeToPlay?
    public var costFit: CostFit
    public var weather: WeatherAssessment
    public var components: [ScoreComponent]
    public var badges: [RecommendationBadge]
    /// e.g. "Good match for your level. Free public access. Estimated playing in 14–24 minutes."
    public var explanation: String
    public var warnings: [String]

    public var id: UUID { facility.id }
    public var totalScore: Double { components.reduce(0) { $0 + $1.minutes } }
    public var uncertaintyMinutes: Double { components.first { $0.label == ScoreLabels.uncertainty }?.minutes ?? 0 }
}

public enum ScoreLabels {
    public static let travel = "Travel"
    public static let wait = "Expected wait"
    public static let fit = "Player fit"
    public static let cost = "Cost"
    public static let uncertainty = "Uncertain estimate"
    public static let conditions = "Conditions"
}

public struct RecommendationSet: Hashable, Sendable {
    /// Eligible facilities ordered by the requested mode.
    public var ranked: [FacilityRecommendation]
    /// Restricted / unavailable facilities with reasons — shown, but never as top picks.
    public var notAvailable: [FacilityRecommendation]
    /// Labelled picks, unique facilities, in display order.
    public var picks: [FacilityRecommendation]

    public var all: [FacilityRecommendation] { ranked + notAvailable }

    public init(ranked: [FacilityRecommendation], notAvailable: [FacilityRecommendation], picks: [FacilityRecommendation]) {
        self.ranked = ranked; self.notAvailable = notAvailable; self.picks = picks
    }
}

public struct RecommendationInput: Sendable {
    public var facility: Facility
    public var travel: TravelEstimate?
    public var weather: WeatherConditions?
    public init(facility: Facility, travel: TravelEstimate?, weather: WeatherConditions?) {
        self.facility = facility; self.travel = travel; self.weather = weather
    }
}

/// Stage A → B → C → D (docs §10). Each stage contributes explainable reasons; the ranking key is a
/// sum of named minute-equivalent components, never an unexplained score.
public struct RecommendationEngine: Sendable {
    public var predictor: WaitPredictor
    public var eligibility = EligibilityEvaluator()
    public var fit = PlayerFitEvaluator()

    public init(predictor: WaitPredictor = WaitPredictor()) { self.predictor = predictor }

    public func evaluate(_ input: RecommendationInput, prefs: UserPreferences, now: Date) -> FacilityRecommendation {
        let f = input.facility
        let config = predictor.config
        let weather = WeatherAssessor.assess(input.weather, isOutdoor: f.indoorOutdoor != .indoor, config: config)
        let prediction = predictor.predict(facility: f, now: now, weather: input.weather)

        // Stage A
        let elig = eligibility.evaluate(f, now: now, prefs: prefs, weather: weather, usableCourts: prediction.usableCourts)
        // Stage B
        let fitResult = fit.evaluate(f, prefs: prefs)
        // Stage C
        var components: [ScoreComponent] = []
        var ttp: TimeToPlay?
        if let travel = input.travel {
            ttp = TimeToPlay(lowMinutes: travel.minutes + Double(prediction.wait.low),
                             highMinutes: travel.minutes + Double(prediction.wait.effectiveHigh))
            components.append(ScoreComponent(label: ScoreLabels.travel, minutes: travel.minutes))
        }
        components.append(ScoreComponent(label: ScoreLabels.wait, minutes: prediction.wait.midpoint))
        let uncertainty: Double
        switch prediction.confidence {
        case .high: uncertainty = 0
        case .medium: uncertainty = prediction.wait.midpoint * 0.15
        case .low: uncertainty = prediction.wait.midpoint * 0.4 + 5
        }
        components.append(ScoreComponent(label: ScoreLabels.uncertainty, minutes: uncertainty))
        if fitResult.penaltyMinutes != 0 {
            components.append(ScoreComponent(label: ScoreLabels.fit, minutes: fitResult.penaltyMinutes))
        }
        // Stage D
        let costFit = Self.costFit(f.cost, prefs: prefs)
        let costPenalty: Double
        switch costFit {
        case .free: costPenalty = 0
        case .paid(let price):
            let factor = prefs.costPreference == .includePaid ? 0.3 : 0.5
            costPenalty = (price ?? 12) * factor
        case .membership: costPenalty = 10
        case .unknown: costPenalty = 4
        case .outsidePreference: costPenalty = 60
        }
        if costPenalty != 0 { components.append(ScoreComponent(label: ScoreLabels.cost, minutes: costPenalty)) }
        var conditions = 0.0
        if weather.impact == .significant { conditions += 15 } else if weather.impact == .minor { conditions += 5 }
        if elig.warnings.contains(where: { $0.hasPrefix("Surface") }) { conditions += 8 }
        if conditions > 0 { components.append(ScoreComponent(label: ScoreLabels.conditions, minutes: conditions)) }

        var warnings = elig.warnings
        if let h = weather.headline, !warnings.contains(h) { warnings.append(h) }

        return FacilityRecommendation(
            facility: f, eligibility: elig, fit: fitResult, prediction: prediction, travel: input.travel,
            timeToPlay: ttp, costFit: costFit, weather: weather, components: components, badges: [],
            explanation: Self.explain(f, elig: elig, fit: fitResult, prediction: prediction, ttp: ttp, cost: costFit),
            warnings: warnings)
    }

    public func recommend(_ inputs: [RecommendationInput], prefs: UserPreferences, now: Date = Date(),
                          mode: SortMode = .bestOverall) -> RecommendationSet {
        let evaluated = inputs.map { evaluate($0, prefs: prefs, now: now) }
        var eligible = evaluated.filter { $0.eligibility.status == .eligible }
        let others = evaluated.filter { $0.eligibility.status != .eligible }
            .sorted { ($0.eligibility.status, $0.travel?.minutes ?? .infinity) < ($1.eligibility.status, $1.travel?.minutes ?? .infinity) }
        eligible = sort(eligible, by: mode)

        // Picks only from facilities the user can afford under their preference.
        let pickable = eligible.filter { $0.costFit != .outsidePreference }
        var badgeMap: [UUID: [RecommendationBadge]] = [:]
        var order: [UUID] = []
        func award(_ badge: RecommendationBadge, _ rec: FacilityRecommendation?) {
            guard let rec else { return }
            if badgeMap[rec.id] == nil { order.append(rec.id) }
            badgeMap[rec.id, default: []].append(badge)
        }
        award(.bestMatch, pickable.min { $0.totalScore < $1.totalScore })
        award(.fastest, pickable.filter { $0.timeToPlay != nil }
            .min { ($0.timeToPlay!.midMinutes + $0.uncertaintyMinutes) < ($1.timeToPlay!.midMinutes + $1.uncertaintyMinutes) })
        award(.bestFree, pickable.filter { $0.costFit == .free }.min { $0.totalScore < $1.totalScore })
        if prefs.costPreference != .freeOnly {
            award(.reservable, pickable.filter { $0.facility.access.reservationAvailable == true && $0.costFit != .free }
                .min { $0.totalScore < $1.totalScore })
        }

        func withBadges(_ r: FacilityRecommendation) -> FacilityRecommendation {
            var copy = r
            copy.badges = badgeMap[r.id] ?? []
            return copy
        }
        let ranked = eligible.map(withBadges)
        let picks = order.compactMap { id in ranked.first { $0.id == id } }
        return RecommendationSet(ranked: ranked, notAvailable: others, picks: picks)
    }

    public func sort(_ recs: [FacilityRecommendation], by mode: SortMode) -> [FacilityRecommendation] {
        recs.sorted { a, b in
            switch mode {
            case .bestOverall:
                return a.totalScore < b.totalScore
            case .fastestToPlay:
                return (a.timeToPlay?.midMinutes ?? a.prediction.wait.midpoint) + a.uncertaintyMinutes
                    < (b.timeToPlay?.midMinutes ?? b.prediction.wait.midpoint) + b.uncertaintyMinutes
            case .closest:
                return (a.travel?.distanceMeters ?? .infinity) < (b.travel?.distanceMeters ?? .infinity)
            case .shortestWait:
                return a.prediction.wait.midpoint + a.uncertaintyMinutes < b.prediction.wait.midpoint + b.uncertaintyMinutes
            case .bestSkillMatch:
                return (a.fit.skillFit, a.totalScore) < (b.fit.skillFit, b.totalScore)
            case .mostCourts:
                return (a.prediction.usableCourts, -a.totalScore) > (b.prediction.usableCourts, -b.totalScore)
            }
        }
    }

    static func costFit(_ c: FacilityCost, prefs: UserPreferences) -> CostFit {
        switch c.costType {
        case .free: return .free
        case .unknown: return .unknown
        case .membership: return prefs.costPreference == .freeOnly ? .outsidePreference : .membership
        case .paid, .dayPass, .reservationFee:
            return prefs.costPreference == .freeOnly ? .outsidePreference : .paid(c.estimatedVisitCost)
        }
    }

    static func explain(_ f: Facility, elig: Eligibility, fit: PlayerFit, prediction: WaitPrediction,
                        ttp: TimeToPlay?, cost: CostFit) -> String {
        if elig.status != .eligible, let reason = elig.reason { return reason + "." }
        var parts: [String] = []
        if let h = fit.headline { parts.append(h + ".") }
        else if let t = fit.tradeoff { parts.append(t + ".") }
        switch cost {
        case .free:
            parts.append(f.access.accessType == .publicWalkOn ? "Free public access." : "Free.")
        case .paid(let p):
            parts.append(p.map { String(format: "Requires a $%.0f fee.", $0) } ?? "Paid access.")
        case .membership: parts.append("Membership required.")
        case .unknown, .outsidePreference: break
        }
        if let ttp {
            parts.append("Estimated playing in \(ttp.label).")
        } else {
            parts.append("Estimated wait \(prediction.wait.label).")
        }
        return parts.joined(separator: " ")
    }
}
