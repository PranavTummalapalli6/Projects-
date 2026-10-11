import Foundation

public enum SkillFit: Int, Hashable, Sendable, Comparable {
    case great = 0, good, unknown, stretch, mismatch
    public static func < (l: Self, r: Self) -> Bool { l.rawValue < r.rawValue }
}

public struct PlayerFit: Hashable, Sendable {
    public var skillFit: SkillFit
    /// e.g. "Good match for your 3.5 level"
    public var headline: String?
    /// e.g. "Typical play: 3.0–4.0 · Based on 27 reports · Medium confidence"
    public var skillEvidence: String?
    /// Explained trade-off, e.g. "Play here tends to be stronger (4.0–4.5+)"
    public var tradeoff: String?
    public var cultureNotes: [String]
    /// Minutes-equivalent penalty used for ranking; always explained by `tradeoff`.
    public var penaltyMinutes: Double
}

/// Soft suitability (Stage B). Never excludes a facility.
public struct PlayerFitEvaluator: Sendable {
    public var minObservations = 3
    public init() {}

    public func evaluate(_ f: Facility, prefs: UserPreferences) -> PlayerFit {
        var culture: [String] = []
        let notableCulture = f.culture.filter { $0.share >= 0.3 && $0.observationCount >= 2 }.sorted { $0.share > $1.share }
        culture = notableCulture.prefix(3).map(\.tag.displayName)
        if f.courtType == .dedicatedPickleball { culture.append("Dedicated courts") }
        if f.courtType == .convertibleTennis { culture.append("Portable nets") }

        let beginnerFriendly = notableCulture.contains { $0.tag == .beginnerFriendly }
        let competitive = notableCulture.contains { $0.tag == .competitive || $0.tag == .challengeCourt }
        var penalty = 0.0
        var tradeoff: String?

        guard let summary = f.skill, summary.observationCount >= minObservations,
              let range = summary.typicalRange, let label = summary.typicalLabel,
              let lo = range.low.ordinal, let hi = range.high.ordinal else {
            if prefs.wantsBeginnerFriendly && beginnerFriendly { penalty -= 3 }
            return PlayerFit(skillFit: .unknown, headline: nil, skillEvidence: nil, tradeoff: nil,
                             cultureNotes: culture, penaltyMinutes: prefs.skill == .unknown ? 0 : 3 + penalty)
        }
        let evidence = "Typical play: \(label) · Based on \(summary.observationCount) reports · \(summary.confidence.displayName)"

        guard let user = prefs.skill.ordinal else {
            return PlayerFit(skillFit: .unknown, headline: nil, skillEvidence: evidence, tradeoff: nil,
                             cultureNotes: culture, penaltyMinutes: 0)
        }

        let fit: SkillFit
        var headline: String?
        let userLabel = prefs.skill == .beginner ? "beginner" : String(prefs.skill.rawValue.prefix(3))
        if user >= lo && user <= hi {
            fit = summary.confidence >= .medium ? .great : .good
            headline = "Good match for your \(userLabel) level"
        } else {
            let distance = user < lo ? lo - user : user - hi
            fit = distance == 1 ? .stretch : .mismatch
            if user < lo {
                tradeoff = "Play here tends to be stronger (\(label))"
            } else {
                tradeoff = "Play here tends to be more casual (\(label))"
            }
        }

        switch fit {
        case .great, .good: penalty = 0
        case .unknown: penalty = 3
        case .stretch: penalty = 8
        case .mismatch: penalty = 18
        }
        if prefs.wantsBeginnerFriendly || prefs.skill == .beginner {
            if beginnerFriendly { penalty -= 4 } else if competitive { penalty += 5; tradeoff = tradeoff ?? "Competitive play culture" }
        }
        if prefs.prefersCompetitive == true && competitive { penalty -= 3 }
        // Low-confidence skill estimates only move rankings half as much.
        if summary.confidence == .low { penalty *= 0.5 }

        return PlayerFit(skillFit: fit, headline: headline, skillEvidence: evidence, tradeoff: tradeoff,
                         cultureNotes: culture, penaltyMinutes: penalty)
    }
}
