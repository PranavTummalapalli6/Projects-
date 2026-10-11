//
//  DenominationEngine.swift
//  PokerChipApp
//
//  The chip-value solver behind "Suggested" denominations. Pure logic with no
//  UI dependencies, so it can be unit-tested directly (see DenominationEngineTests).
//

import Foundation

// MARK: - Suggested Denominations
//
// Chip values are drawn from a "clean" ladder — 0.05, 0.10, then every
// multiple of 0.25 (0.25, 0.50, 0.75, 1.00, 1.25, ...) — so players can check
// their stacks with easy mental math instead of odd values like $0.35 or
// $2.35. Counts follow a strictly decreasing negative-exponential shape by
// rank (White-ish/lowest-value colors always end up with *more* chips than
// Red-ish, which always has more than Blue-ish, and so on — never a tie,
// never inverted) and total chip count targets the 20-30 range — shifted
// toward 20 as `players` grows and toward 30 as it shrinks, since more
// players means less felt per player.
//
// Priority when these pull against each other: the exact-sum match is never
// negotiable; below that, keeping every color's count strictly below the
// one ranked before it matters more than landing the 20-30 window — a
// solution that hits 20-30 chips but ties or inverts two colors' counts is
// rejected in favor of one that keeps the shape correct even if the total
// lands outside the window. Every color's value is fixed from its natural
// multiple of the average chip value (buyInCents/targetTotal — see
// assignCleanValues) *except* the two lowest-value present colors, whose
// values/counts are searched jointly to close the exact remaining gap to
// the buy-in: one free color alone is too coarse against a ladder spaced in
// quarters to reliably land an exact sum, a strict shape, and a 20-30
// total all at once, but two free counts (plus, as a last resort, a few
// rungs of flex on the second-lowest color's value, and a few different
// scalings of the higher-ranked colors' natural counts) find one in the
// vast majority of cases. If no shape-correct, in-range solution exists
// using only clean values (rare — only when a buy-in's cents don't land on
// a quarter for any split), the lowest color's value falls back to any
// nickel-safe divisor, same as a real chip set would: everything else stays
// clean, only the finest chip
// absorbs the odd remainder.

private func niceNickelCents(_ raw: Double) -> Int {
    max(5, Int((raw / 5).rounded()) * 5)
}

/// Snaps to the clean ladder: 5 or 10 cents below the crossover, otherwise
/// the nearest multiple of 25 cents (quarters) — "1/2, 1/4, 3/4, and 1 of
/// value" above a dollar.
private func cleanValueCents(near raw: Double) -> Int {
    let raw = max(raw, 5)
    if raw <= 17.5 {
        return [5, 10].min(by: { abs(Double($0) - raw) < abs(Double($1) - raw) })!
    }
    let rounded = Int((raw / 25).rounded()) * 25
    return max(25, rounded)
}

/// The next rung up the clean ladder from an existing clean value — used to
/// bump a color's value up when its natural snap collides with (or falls
/// below) the color ranked just below it.
private func nextCleanValueCents(after valueCents: Int) -> Int {
    if valueCents < 10 { return 10 }
    if valueCents < 25 { return 25 }
    return valueCents + 25
}

/// The rung just below a clean value, or nil at the bottom of the ladder.
private func previousCleanValueCents(before valueCents: Int) -> Int? {
    if valueCents <= 5 { return nil }
    if valueCents <= 10 { return 5 }
    if valueCents <= 25 { return 10 }
    return valueCents - 25
}

/// What the person's own chips and choices impose on a suggestion. Everything
/// else about the solver — exact sum, a clean ladder, values rising and counts
/// falling at every step — stays exactly as it is without any of this.
struct ChipConstraints: Equatable {
    /// The most chips of a colour one player can be dealt: what is owned, divided
    /// by the players. A colour not listed has no limit.
    var maxPerPlayer: [String: Int] = [:]
    /// Values (in cents) held fixed: chosen by the person, or printed on the chips.
    var lockedValues: [String: Int] = [:]

    var isEmpty: Bool { maxPerPlayer.isEmpty && lockedValues.isEmpty }
}

/// A stack the solver found, before it is dressed up for the screen.
struct ChipCandidate: Equatable {
    let counts: [String: Int]
    let valuesCents: [String: Int]

    var totalChips: Int { counts.values.reduce(0, +) }
    var totalCents: Int { counts.reduce(0) { $0 + $1.value * (valuesCents[$1.key] ?? 0) } }
    var smallestChipCents: Int { valuesCents.values.min() ?? 0 }
}

/// Every clean-ladder value up to and including `cap`.
private func cleanLadder(upTo cap: Int) -> [Int] {
    guard cap >= 5 else { return [] }
    var ladder = [5]
    if cap >= 10 { ladder.append(10) }
    var v = 25
    while v <= cap {
        ladder.append(v)
        v += 25
    }
    return ladder
}

/// Each color's natural value as a multiple of the *average* chip value
/// (buy-in / target chip count) rather than of the buy-in directly — White
/// smallest, Black largest, matching how a real set is normally racked.
/// Scaling off the average (not the raw buy-in) is what keeps this sane at
/// both ends: for a small buy-in split across 5 colors, avgCents is already
/// small, so Black's 4x multiplier still lands on a small, affordable clean
/// value instead of eating the whole budget on its own.
private let naturalColorMultiplier: [String: Double] = [
    "White": 0.3, "Red": 0.6, "Blue": 1.1, "Green": 2.0, "Black": 4.0
]

/// One clean value per present color, strictly increasing low-to-high —
/// each snapped from its own natural average-chip-value multiple, bumped up
/// to the next clean rung on any collision so strict ordering always holds
/// even for small buy-ins where several colors' natural values land close
/// together.
private func assignCleanValues(presentColors: [String], avgCents: Double, locked: [String: Int] = [:]) -> [String: Int]? {
    var values: [String: Int] = [:]
    var previous = 0
    for color in presentColors {
        if let fixed = locked[color] {
            guard fixed > previous else { return nil }
            values[color] = fixed
            previous = fixed
            continue
        }
        let multiplier = naturalColorMultiplier[color] ?? 1.0
        var value = cleanValueCents(near: avgCents * multiplier)
        while value <= previous {
            value = nextCleanValueCents(after: value)
        }
        values[color] = value
        previous = value
    }
    guard !locked.isEmpty else { return values }

    // A colour whose natural value now sits at or above a locked colour above it
    // is brought down below it, one rung at a time, so the order still holds.
    for index in presentColors.indices.reversed().dropFirst() {
        let color = presentColors[index], above = presentColors[index + 1]
        guard let aboveValue = values[above], let value = values[color], value >= aboveValue else { continue }
        guard locked[color] == nil, let lower = previousCleanValueCents(before: aboveValue) else { return nil }
        values[color] = lower
    }
    // Bringing one down can push it below the colour beneath it: that can't be satisfied.
    for (below, color) in zip(presentColors, presentColors.dropFirst()) {
        guard let lowerValue = values[below], let value = values[color], value > lowerValue else { return nil }
    }
    return values
}

/// A single rank's weight on the negative-exponential curve — rank 0 (the
/// lowest-value color) weighted heaviest (1.0), decaying by `decay` per
/// rank, so lower-value colors always end up with noticeably more chips
/// than higher-value ones. Takes a *true* rank (position among all present
/// colors), not a position within some subset, so a color's weight reflects
/// where it actually sits in the lineup.
private func negativeExponentialWeight(rank: Int, decay: Double = 0.55) -> Double {
    exp(-decay * Double(rank))
}

/// More players at the table means less felt per player, so fewer chips stay
/// in circulation (down to 20); fewer players means more (up to 30).
private func targetTotalChipCount(players: Int) -> Int {
    let clampedPlayers = Double(min(max(players, 2), 10))
    let t = (clampedPlayers - 2) / 8
    return Int((30 - 10 * t).rounded())
}

/// All divisors of `valueCents` that are themselves nickel-safe (multiples of
/// 5) and no larger than `cap`, found by factoring valueCents/5 up to its
/// square root — brute-force stepping by 5 up to a six-figure buy-in's worth
/// of cents would mean tens of thousands of iterations; this keeps it fast
/// regardless of buy-in size. Used only as the tier-2 fallback below, when no
/// clean-ladder value closes the gap.
private func nickelSafeDivisors(of valueCents: Int, upTo cap: Int) -> [Int] {
    guard valueCents > 0 else { return [] }
    let fifths = valueCents / 5
    guard fifths > 0 else { return [] }

    var found = Set<Int>()
    var d = 1
    while d * d <= fifths {
        if fifths % d == 0 {
            found.insert(d)
            found.insert(fifths / d)
        }
        d += 1
    }
    return found.map { $0 * 5 }.filter { $0 <= cap }.sorted()
}

/// The single-present-color case: every chip is the same value, so this just
/// searches for a value/count pair whose product is exactly `buyInCents`,
/// preferring a clean-ladder value and a count within 20-30, and otherwise
/// falling back to whichever nickel-safe value/count lands closest to that.
private func solveSingleColor(buyInCents: Int, targetTotal: Int) -> (count: Int, valueCents: Int)? {
    var best: (inRange: Bool, distance: Int, count: Int, valueCents: Int)?

    func consider(count: Int, value: Int) {
        guard count >= 1 else { return }
        let inRange = (20...30).contains(count)
        let distance = abs(count - targetTotal)
        if let current = best {
            if inRange && !current.inRange {
                best = (inRange, distance, count, value)
            } else if inRange == current.inRange && distance < current.distance {
                best = (inRange, distance, count, value)
            }
        } else {
            best = (inRange, distance, count, value)
        }
    }

    for value in cleanLadder(upTo: buyInCents) where buyInCents % value == 0 {
        consider(count: buyInCents / value, value: value)
    }

    if best == nil || !best!.inRange {
        var radius = 0
        while radius < 4000 {
            for count in Set([targetTotal - radius, targetTotal + radius]) {
                guard count > 0, buyInCents % count == 0 else { continue }
                let value = buyInCents / count
                guard value > 0, value % 5 == 0 else { continue }
                consider(count: count, value: value)
            }
            if let best, best.inRange { break }
            radius += 1
        }
    }

    guard let result = best else { return nil }
    return (result.count, result.valueCents)
}

/// The 2-or-more-present-colors case. Every color gets a fixed clean-ladder
/// value (see assignCleanValues). Colors ranked 3rd and above get a fixed
/// count from a negative-exponential share of the chip-count budget
/// (pricier colors get fewer chips, with the drop-off accelerating);
/// `presentColors[0]` and `presentColors[1]` (the two lowest-value colors)
/// both stay free, searched jointly, to close the exact remaining gap to
/// the buy-in — one free color alone is too coarse against a ladder spaced
/// in quarters, but two free counts admit an exact match in the vast
/// majority of cases. Several different higher-rank count splits are tried
/// so a solution within the 20-30 chip window can be found for both very
/// small and very large buy-ins.
private func solveMultiColor(
    buyInCents: Int,
    players: Int,
    presentColors: [String],
    constraints: ChipConstraints = ChipConstraints(),
    pool: ((ChipCandidate) -> Void)? = nil
) -> ([String: Int], [String: Double])? {
    let targetTotal = targetTotalChipCount(players: players)
    let avgCents = Double(buyInCents) / Double(targetTotal)
    let rank1 = presentColors[0]
    let rank2 = presentColors[1]
    let higherRanks = Array(presentColors.dropFirst(2))
    guard let baseValues = assignCleanValues(presentColors: presentColors, avgCents: avgCents, locked: constraints.lockedValues) else { return nil }
    let naturalV2 = baseValues[rank2] ?? 10
    let cap1 = constraints.maxPerPlayer[rank1] ?? Int.max
    let cap2 = constraints.maxPerPlayer[rank2] ?? Int.max

    // A few rungs up from rank2's natural value, tried only if the natural
    // one doesn't yield an in-range solution on its own — rank1's value is
    // capped below rank2's, so when rank2 is small (e.g. only 2 colors
    // present and rank2 lands near the bottom of the ladder), rank1 barely
    // has room to maneuver; letting rank2 range a little higher gives rank1
    // more headroom. Capped below the next fixed-value color (if any) so a
    // bumped rank2 can never collide with or exceed it.
    let v2Ceiling = higherRanks.first.flatMap { baseValues[$0] } ?? Int.max
    var v2Candidates = [naturalV2]
    var bumped = naturalV2
    for _ in 0..<4 where constraints.lockedValues[rank2] == nil {
        bumped = nextCleanValueCents(after: bumped)
        guard bumped < v2Ceiling else { break }
        v2Candidates.append(bumped)
    }

    // Weights for every present color by its *true* rank (0 = rank1), so a
    // color's expected count reflects its actual position in the lineup
    // rather than its position within just the higher-ranks slice — with
    // only one higher-rank color (e.g. 3 colors total), that color would
    // otherwise inherit rank1's weight of 1.0 and claim most of the chip
    // budget, when it should get the smallest share.
    let allWeights = presentColors.indices.map { negativeExponentialWeight(rank: $0) }
    let weightSumAll = allWeights.reduce(0, +)
    let baseUnit = Double(targetTotal) / weightSumAll

    struct Candidate {
        let score: Double
        let shapeOK: Bool
        let inRange: Bool
        let v1: Int
        let v2: Int
        let count1: Int
        let count2: Int
        let higherCounts: [String: Int]
    }
    var globalBest: Candidate?

    func higherCounts(unitScale: Double) -> (counts: [String: Int], known: Int, valueCents: Int, strictlyDecreasing: Bool) {
        guard !higherRanks.isEmpty else { return ([:], 0, 0, true) }
        let unit = baseUnit * unitScale
        var counts: [String: Int] = [:]
        // Strictly decreasing rank-to-rank: with a decay curve this coarse,
        // two adjacent ranks can round to the same raw count, so each
        // subsequent color is clamped below the previous one (floor 1) to
        // guarantee a real drop rather than a tie — except at the floor
        // itself, where two ranks both wanting count 1 genuinely can't both
        // drop further; `strictlyDecreasing` flags that so the candidate
        // scoring below can prefer a different unitScale instead of quietly
        // accepting the tie.
        var previous = Int.max
        var strictlyDecreasing = true
        for (idx, color) in higherRanks.enumerated() {
            let trueRank = idx + 2
            var count = max(1, Int((allWeights[trueRank] * unit).rounded()))
            if count >= previous {
                count = max(1, previous - 1)
                if count >= previous { strictlyDecreasing = false }
            }
            // Chips the person doesn't own can't be dealt: a count over the limit
            // is capped (and a cap that forces a tie is flagged like any other).
            if let limit = constraints.maxPerPlayer[color], count > limit {
                if limit < 1 {
                    strictlyDecreasing = false                    // none of this colour to deal
                } else {
                    count = limit
                    if count >= previous { strictlyDecreasing = false }
                }
            }
            counts[color] = count
            previous = count
        }
        let known = counts.values.reduce(0, +)
        let valueCents = higherRanks.reduce(0) { $0 + (counts[$1] ?? 0) * (baseValues[$1] ?? 5) }
        return (counts, known, valueCents, strictlyDecreasing)
    }

    // Priority: keeping the negative-exponential shape (lower value = more
    // chips) intact matters more than hitting the 20-30 window exactly — a
    // solution that's in range but inverts White/Red's counts isn't what was
    // asked for, so shape-correct candidates are preferred over merely
    // in-range ones, and only the best score breaks a further tie.
    func consider(_ candidate: Candidate) {
        if let pool, candidate.shapeOK {
            var counts = candidate.higherCounts
            counts[rank1] = candidate.count1
            counts[rank2] = candidate.count2
            var values: [String: Int] = [rank1: candidate.v1, rank2: candidate.v2]
            for color in higherRanks { values[color] = baseValues[color] ?? 5 }
            pool(ChipCandidate(counts: counts, valuesCents: values))
        }
        guard let current = globalBest else {
            globalBest = candidate
            return
        }
        if candidate.shapeOK != current.shapeOK {
            if candidate.shapeOK { globalBest = candidate }
            return
        }
        if candidate.inRange != current.inRange {
            if candidate.inRange { globalBest = candidate }
            return
        }
        if candidate.score < current.score {
            globalBest = candidate
        }
    }

    // For each scaling of the higher (fixed-count) ranks' natural counts,
    // jointly search rank1's value (from the clean ladder, always kept below
    // rank2's so the ordering stays strictly increasing) and rank2's count
    // (free) for a pair that makes rank1's count come out to an exact,
    // positive integer. Bounding the ladder/divisor search to just below v2
    // (rather than the full remaining amount) is what keeps this fast even
    // for large buy-ins — remaining can be huge, but rank1's value never
    // needs to be.
    func search(
        v2: Int,
        unitScales: [Double] = [0.6, 0.75, 0.9, 1.0, 1.1, 1.25, 1.4],
        v1Candidates: (Int, Int) -> [Int]
    ) {
        for unitScale in unitScales {
            let (counts, known, higherValueCents, higherStrictlyDecreasing) = higherCounts(unitScale: unitScale)
            let firstHigherCount = higherRanks.first.flatMap { counts[$0] } ?? 0
            let leftover = buyInCents - higherValueCents
            guard leftover > 0 else { continue }

            let count2Max = min(40, leftover / v2, cap2)
            guard count2Max >= 1 else { continue }
            for count2 in 1...count2Max {
                let remaining = leftover - count2 * v2
                guard remaining > 0 else { continue }
                for v1 in v1Candidates(remaining, v2 - 5) {
                    let count1 = remaining / v1
                    guard count1 >= 1, count1 <= cap1 else { continue }
                    let total = count1 + count2 + known
                    let inRange = (20...30).contains(total)
                    // The negative-exponential shape: count1 (rank1) must be
                    // strictly greater than count2 (rank2), which must be
                    // strictly greater than the first higher-ranked color's
                    // count — a real drop at every step, not a tie — and the
                    // higher ranks themselves (Blue>Green>Black, etc.) must
                    // hold that same strict drop with no floor-collision tie.
                    let shapeOK = higherStrictlyDecreasing
                        && count1 > count2
                        && (firstHigherCount == 0 || count2 > firstHigherCount)
                    let rangePenalty = inRange ? 0 : Double(min(abs(total - 20), abs(total - 30)))
                    // Mildly prefer rank2 staying close to its natural
                    // value — bumping it up is a last resort, not the norm.
                    let score = rangePenalty * 10
                        + 0.05 * abs(Double(total - targetTotal))
                        + 0.02 * abs(log(Double(v2)) - log(Double(naturalV2)))
                    consider(Candidate(score: score, shapeOK: shapeOK, inRange: inRange, v1: v1, v2: v2, count1: count1, count2: count2, higherCounts: counts))
                }
            }
        }
    }

    // Try rank2's natural value first; only reach for a bumped-up rank2 (see
    // v2Candidates above) if no shape-correct, in-range solution was found
    // yet — the natural value is right the vast majority of the time, so
    // this keeps the common case fast instead of always paying for every
    // candidate.
    let lockedV1 = constraints.lockedValues[rank1]
    func ladderDivisors(_ remaining: Int, _ cap: Int) -> [Int] {
        if let lockedV1 { return lockedV1 <= cap && remaining % lockedV1 == 0 ? [lockedV1] : [] }
        return cleanLadder(upTo: min(remaining, cap)).filter { remaining % $0 == 0 }
    }
    func looseDivisors(_ remaining: Int, _ cap: Int) -> [Int] {
        if let lockedV1 { return lockedV1 <= cap && remaining % lockedV1 == 0 ? [lockedV1] : [] }
        return nickelSafeDivisors(of: remaining, upTo: min(remaining, cap))
    }

    for v2 in v2Candidates {
        guard globalBest == nil || !globalBest!.shapeOK || !globalBest!.inRange else { break }
        search(v2: v2, v1Candidates: ladderDivisors)
    }

    // Tier 2: only if no shape-correct, in-range pure-clean-ladder solution
    // exists — widen rank1's value to any nickel-safe divisor, matching how
    // a real chip set would handle a buy-in whose cents don't land on a
    // quarter for any split. Every other color's value is still clean.
    if globalBest == nil || !globalBest!.shapeOK || !globalBest!.inRange {
        for v2 in v2Candidates {
            guard globalBest == nil || !globalBest!.shapeOK || !globalBest!.inRange else { break }
            search(v2: v2, v1Candidates: looseDivisors)
        }
    }

    // Tier 3: tiny buy-ins. The usual scalings hand the pricier colors more
    // chips than a few dollars can pay for, which can leave no correctly
    // shaped stack even though one exists (e.g. $1.35 over White/Green/Black:
    // 18 x 0.05, 2 x 0.10, 1 x 0.25). Only when nothing correctly shaped has
    // been found yet, try much smaller counts for them — so ordinary buy-ins,
    // which never get here, are unaffected.
    let thinUnitScales = [0.45, 0.3, 0.2, 0.12, 0.06]
    if globalBest == nil || !globalBest!.shapeOK {
        for v2 in v2Candidates {
            guard globalBest == nil || !globalBest!.shapeOK else { break }
            search(v2: v2, unitScales: thinUnitScales, v1Candidates: ladderDivisors)
            if globalBest == nil || !globalBest!.shapeOK {
                search(v2: v2, unitScales: thinUnitScales, v1Candidates: looseDivisors)
            }
        }
    }

    // Strict: a stack whose counts tie or invert isn't offered at all. "Too
    // small to split" is a better answer than chips that don't follow the rule.
    guard let best = globalBest, best.shapeOK else { return nil }

    var counts = best.higherCounts
    counts[rank1] = best.count1
    counts[rank2] = best.count2

    var values: [String: Double] = [rank1: Double(best.v1) / 100, rank2: Double(best.v2) / 100]
    for color in higherRanks {
        values[color] = Double(baseValues[color] ?? 5) / 100
    }

    return (counts, values)
}

/// Computes suggested chip values and counts for whichever chip colors the
/// user actually has (`availableColors`). Returns `(nil, [:])` if
/// `availableColors` is empty, or when a buy-in is too small to support a
/// correctly shaped stack of every selected color (values rising and counts
/// falling at every step). It never returns a stack that ties or inverts.
///
/// The total value always sums to exactly the buy-in (the buy-in is first
/// rounded to the nearest nickel, since an exact match to a non-nickel
/// buy-in like $19.99 isn't otherwise possible — no physical chip set has
/// penny granularity either). Every value is drawn from the clean ladder —
/// 0.05, 0.10, then every multiple of 0.25 — except in the rare case a
/// buy-in's cents can't be split across clean values no matter how the chip
/// counts are divided, where the single lowest-value color falls back to a
/// plain nickel-safe value so the sum still lands exactly on the buy-in.
/// Chip counts follow a negative-exponential decay by value rank (lower
/// value = more chips) and total chip count targets the 20-30 range,
/// shifted toward 20 as `players` grows and toward 30 as it shrinks (more
/// players means less felt per player) — falling back to whatever total is
/// closest to that range if hitting it exactly isn't possible.
func calculateFlexibleChipDistribution(
    buyIn: Double,
    players: Int,
    availableColors: Set<String>
) -> ([String: Int]?, [String: Double]) {
    let presentColors = allChipColors.filter { availableColors.contains($0) }
    guard !presentColors.isEmpty else { return (nil, [:]) }

    let buyInCents = niceNickelCents(buyIn * 100)

    if presentColors.count == 1 {
        guard let (count, valueCents) = solveSingleColor(buyInCents: buyInCents, targetTotal: targetTotalChipCount(players: players)) else {
            return (nil, [:])
        }
        return ([presentColors[0]: count], [presentColors[0]: Double(valueCents) / 100])
    }

    guard let (counts, values) = solveMultiColor(buyInCents: buyInCents, players: players, presentColors: presentColors) else {
        return (nil, [:])
    }
    return (counts, values)
}

// MARK: - Planning with the person's own chips

/// What a person owns, so a suggestion never deals more chips of a colour than
/// exist, and — if the chips have values printed on them — never invents values.
struct ChipInventory: Codable, Hashable {
    /// How many chips of each colour are owned.
    var owned: [String: Int]
    /// Values printed on the chips, in cents; nil for plain chips.
    var printedValues: [String: Int]?

    enum SetSize: Int, CaseIterable, Identifiable {
        case hundred = 100
        case twoHundred = 200
        case threeHundred = 300
        case fiveHundred = 500

        var id: Int { rawValue }
        var title: String { "\(rawValue)-piece set" }
    }

    /// A common set split evenly across the colours in use (the remainder goes to
    /// the lowest-value colours, which sets have the most of). Every count is editable.
    static func preset(_ size: SetSize, colors: [String]) -> ChipInventory {
        let ordered = allChipColors.filter { colors.contains($0) }
        guard !ordered.isEmpty else { return ChipInventory(owned: [:], printedValues: nil) }
        let base = size.rawValue / ordered.count
        let extra = size.rawValue % ordered.count
        var owned: [String: Int] = [:]
        for (index, color) in ordered.enumerated() { owned[color] = base + (index < extra ? 1 : 0) }
        return ChipInventory(owned: owned, printedValues: nil)
    }

    var totalOwned: Int { owned.values.reduce(0, +) }

    /// The most of a colour one player can be dealt when `players` share the set.
    func maxPerPlayer(players: Int) -> [String: Int] {
        owned.mapValues { $0 / max(players, 1) }
    }
}

/// One way to deal the chips.
struct ChipOption: Hashable, Identifiable {
    enum Kind: String {
        /// The balanced stack — what you'd get without asking for anything else.
        case recommended
        /// The same buy-in with fewer chips to count and rack.
        case fewerChips
        /// A smaller smallest chip, for finer blinds and betting.
        case finerChips
    }

    let kind: Kind
    let counts: [String: Int]
    let valuesCents: [String: Int]

    var id: String {
        allChipColors.compactMap { color in counts[color].map { "\(color):\(valuesCents[color] ?? 0)x\($0)" } }.joined(separator: ",")
    }

    var totalChips: Int { counts.values.reduce(0, +) }
    var totalCents: Int { counts.reduce(0) { $0 + $1.value * (valuesCents[$1.key] ?? 0) } }
    var smallestChipCents: Int { valuesCents.values.min() ?? 0 }
}

/// What to try when the chips can't do what was asked.
struct ChipAlternative: Hashable, Identifiable {
    enum Kind: Hashable {
        case fewerPlayers(Int)
        case lowerBuyIn(cents: Int)
        case dropColor(String)
    }

    let kind: Kind
    var id: String {
        switch kind {
        case .fewerPlayers(let players): return "players-\(players)"
        case .lowerBuyIn(let cents): return "buyin-\(cents)"
        case .dropColor(let color): return "drop-\(color)"
        }
    }
}

enum ChipPlanFailure: Equatable {
    case noColors
    /// The buy-in is too small to split across these colours with real chip values.
    case tooSmall(nextWorkingCents: Int?)
    /// The chips owned can't cover it. `alternatives` are things that would work.
    case setTooSmall
    /// Chips with printed values can't add up to exactly this amount.
    case noExactSplit(nearbyCents: [Int])
    /// The values locked in can't be ordered low to high down the colours.
    case valuesConflict
}

struct ChipPlan: Equatable {
    var options: [ChipOption] = []
    var failure: ChipPlanFailure?
    var alternatives: [ChipAlternative] = []
    /// The buy-in the stack adds up to: the typed amount rounded to the nearest nickel.
    var buyInCents = 0

    var recommended: ChipOption? { options.first }
}

enum ChipPlanner {
    /// The fewest chips a one-colour stack can have and still make change.
    static let minimumSingleColourStack = 5

    /// Suggests how to deal `buyIn` to each of `players`, using these colours,
    /// within what is owned and with any values locked. With no inventory and no
    /// locks, the recommended stack is exactly `calculateFlexibleChipDistribution`'s.
    static func plan(
        buyIn: Double,
        players: Int,
        colors: Set<String>,
        inventory: ChipInventory? = nil,
        lockedValues: [String: Int] = [:]
    ) -> ChipPlan {
        let present = allChipColors.filter { colors.contains($0) }
        let buyInCents = niceNickelCents(buyIn * 100)
        guard !present.isEmpty else { return ChipPlan(failure: .noColors, buyInCents: buyInCents) }

        var locked = lockedValues.filter { present.contains($0.key) }
        var caps: [String: Int] = [:]
        if let inventory {
            caps = inventory.maxPerPlayer(players: players).filter { present.contains($0.key) }
            if let printed = inventory.printedValues {
                for color in present { if let value = printed[color] { locked[color] = value } }
            }
        }
        let constraints = ChipConstraints(maxPerPlayer: caps, lockedValues: locked)

        var plan = solve(buyInCents: buyInCents, players: players, present: present, constraints: constraints)
        plan.buyInCents = buyInCents
        guard plan.options.isEmpty else { return plan }

        // Failed. Say why: if it works without the person's limits, it's their set;
        // if not, the set isn't the problem and the reason is the unlimited one.
        if !caps.isEmpty {
            let unlimited = solve(buyInCents: buyInCents, players: players, present: present, constraints: ChipConstraints(maxPerPlayer: [:], lockedValues: locked))
            if !unlimited.options.isEmpty {
                return ChipPlan(
                    failure: .setTooSmall,
                    alternatives: alternatives(buyInCents: buyInCents, players: players, present: present, inventory: inventory, locked: locked),
                    buyInCents: buyInCents
                )
            }
            return ChipPlan(failure: unlimited.failure, buyInCents: buyInCents)
        }
        return ChipPlan(failure: plan.failure, buyInCents: buyInCents)
    }

    // MARK: Solving

    private static func solve(buyInCents: Int, players: Int, present: [String], constraints: ChipConstraints) -> ChipPlan {
        if present.count == 1 {
            return solveOneColor(buyInCents: buyInCents, players: players, color: present[0], constraints: constraints)
        }
        // Every colour has a fixed value (printed chips, or all locked): only counts are left to find.
        if present.allSatisfy({ constraints.lockedValues[$0] != nil }) {
            return solveFixed(buyInCents: buyInCents, players: players, present: present, constraints: constraints)
        }

        var pool: [ChipCandidate] = []
        let best = solveMultiColor(
            buyInCents: buyInCents, players: players, presentColors: present, constraints: constraints,
            pool: { pool.append($0) }
        )
        guard let (counts, values) = best else {
            if constraints.lockedValues.isEmpty && constraints.maxPerPlayer.isEmpty {
                return ChipPlan(failure: .tooSmall(nextWorkingCents: nextWorkingBuyIn(from: buyInCents, players: players, present: present)))
            }
            return ChipPlan(failure: constraints.lockedValues.isEmpty ? .setTooSmall : .valuesConflict)
        }

        let recommended = ChipOption(kind: .recommended, counts: counts, valuesCents: values.mapValues { Int(($0 * 100).rounded()) })
        var options = [recommended]

        // Alternatives come from the clean-ladder stacks the search already visited.
        let distinct = Dictionary(grouping: pool, by: { ChipOption(kind: .recommended, counts: $0.counts, valuesCents: $0.valuesCents).id })
            .values.compactMap(\.first)
            .filter { $0.totalChips >= 8 }
        if let fewer = distinct
            .filter({ $0.totalChips < recommended.totalChips })
            .min(by: { ($0.totalChips, -$0.smallestChipCents) < ($1.totalChips, -$1.smallestChipCents) }) {
            options.append(ChipOption(kind: .fewerChips, counts: fewer.counts, valuesCents: fewer.valuesCents))
        }
        if let finer = distinct
            .filter({ $0.smallestChipCents < recommended.smallestChipCents })
            .min(by: { ($0.smallestChipCents, abs($0.totalChips - 25)) < ($1.smallestChipCents, abs($1.totalChips - 25)) }) {
            let option = ChipOption(kind: .finerChips, counts: finer.counts, valuesCents: finer.valuesCents)
            if !options.contains(where: { $0.id == option.id }) { options.append(option) }
        }
        return ChipPlan(options: options)
    }

    private static func solveOneColor(buyInCents: Int, players: Int, color: String, constraints: ChipConstraints) -> ChipPlan {
        let cap = constraints.maxPerPlayer[color] ?? Int.max
        let target = targetTotalChipCount(players: players)
        if let value = constraints.lockedValues[color] {
            guard buyInCents % value == 0, buyInCents / value <= cap else { return ChipPlan(failure: cap == Int.max ? .noExactSplit(nearbyCents: []) : .setTooSmall) }
            return ChipPlan(options: [ChipOption(kind: .recommended, counts: [color: buyInCents / value], valuesCents: [color: value])])
        }
        if cap == Int.max {
            guard let (count, value) = solveSingleColor(buyInCents: buyInCents, targetTotal: target) else { return ChipPlan(failure: .tooSmall(nextWorkingCents: nil)) }
            return ChipPlan(options: [ChipOption(kind: .recommended, counts: [color: count], valuesCents: [color: value])])
        }
        // Within what is owned: the clean value that comes closest to the usual number of chips.
        // Fewer than five chips can't make change, so a set that only allows that is too small.
        let candidates = cleanLadder(upTo: buyInCents).filter {
            buyInCents % $0 == 0 && buyInCents / $0 <= cap && buyInCents / $0 >= minimumSingleColourStack
        }
        guard let value = candidates.min(by: { abs(buyInCents / $0 - target) < abs(buyInCents / $1 - target) }) else {
            return ChipPlan(failure: .setTooSmall)
        }
        return ChipPlan(options: [ChipOption(kind: .recommended, counts: [color: buyInCents / value], valuesCents: [color: value])])
    }

    /// Chips with a fixed value each: find every exact way to deal them with strictly
    /// more of each cheaper colour, then pick the one nearest the usual chip count.
    private static func solveFixed(buyInCents: Int, players: Int, present: [String], constraints: ChipConstraints) -> ChipPlan {
        let values = present.compactMap { constraints.lockedValues[$0] }
        guard values.count == present.count, zip(values, values.dropFirst()).allSatisfy({ $0 < $1 }) else {
            return ChipPlan(failure: .valuesConflict)
        }
        let caps = present.map { constraints.maxPerPlayer[$0] ?? 100 }
        let found = fixedDeals(buyInCents: buyInCents, values: values, caps: caps)

        let target = targetTotalChipCount(players: players)
        let ranked = found.sorted { lhs, rhs in
            let l = lhs.reduce(0, +), r = rhs.reduce(0, +)
            let lIn = (20...30).contains(l), rIn = (20...30).contains(r)
            if lIn != rIn { return lIn }
            if abs(l - target) != abs(r - target) { return abs(l - target) < abs(r - target) }
            return lhs.lexicographicallyPrecedes(rhs, by: >)
        }
        guard let best = ranked.first else {
            return ChipPlan(failure: .noExactSplit(nearbyCents: nearbyAmounts(buyInCents: buyInCents, players: players, present: present, constraints: constraints)))
        }
        func option(_ counts: [Int], _ kind: ChipOption.Kind) -> ChipOption {
            ChipOption(kind: kind, counts: Dictionary(uniqueKeysWithValues: zip(present, counts)), valuesCents: Dictionary(uniqueKeysWithValues: zip(present, values)))
        }
        var options = [option(best, .recommended)]
        if let fewer = ranked.filter({ $0.reduce(0, +) < best.reduce(0, +) && $0.reduce(0, +) >= 8 }).min(by: { $0.reduce(0, +) < $1.reduce(0, +) }) {
            options.append(option(fewer, .fewerChips))
        }
        return ChipPlan(options: options)
    }

    /// Every exact way to deal chips of fixed `values` (lowest first) that gives strictly
    /// more of each cheaper colour than the one above it, within `caps` per colour.
    /// Each answer lists the counts in the same order as `values`.
    private static func fixedDeals(buyInCents: Int, values: [Int], caps: [Int]) -> [[Int]] {
        var found: [[Int]] = []
        var budget = 2_000_000

        // Dearest colour first (it gets the fewest chips); the cheapest takes whatever is left.
        func descend(_ index: Int, remaining: Int, fewerThan: Int, chosen: [Int]) {
            guard budget > 0 else { return }
            budget -= 1
            if index == 0 {
                guard remaining > 0, remaining % values[0] == 0 else { return }
                let count = remaining / values[0]
                if count > fewerThan && count <= caps[0] { found.append([count] + chosen) }
                return
            }
            let least = fewerThan + 1
            let most = min(caps[index], remaining / values[index], 100)
            guard least <= most else { return }
            for count in least...most {
                descend(index - 1, remaining: remaining - count * values[index], fewerThan: count, chosen: [count] + chosen)
            }
        }
        descend(values.count - 1, remaining: buyInCents, fewerThan: 0, chosen: [])
        return found
    }

    // MARK: When it doesn't work

    /// The next buy-in up, in nickel steps up to $10, that these colours can split.
    private static func nextWorkingBuyIn(from buyInCents: Int, players: Int, present: [String]) -> Int? {
        let start = max((buyInCents / 5 + 1) * 5, 5)
        for cents in stride(from: start, through: 1_000, by: 5) where cents > buyInCents {
            if solveMultiColor(buyInCents: cents, players: players, presentColors: present) != nil { return cents }
        }
        return nil
    }

    /// The nearest amounts below and above that printed-value chips *can* make.
    private static func nearbyAmounts(buyInCents: Int, players: Int, present: [String], constraints: ChipConstraints) -> [Int] {
        let values = present.compactMap { constraints.lockedValues[$0] }
        guard !values.isEmpty, values.count == present.count else { return [] }
        let caps = present.map { constraints.maxPerPlayer[$0] ?? 100 }
        func works(_ cents: Int) -> Bool {
            !fixedDeals(buyInCents: cents, values: values, caps: caps).isEmpty
        }
        // Only multiples of what the chips share can be made, so look along that grid.
        func gcd(_ a: Int, _ b: Int) -> Int { b == 0 ? a : gcd(b, a % b) }
        let step = max(1, values.reduce(0, gcd))

        var result: [Int] = []
        var below = (buyInCents - 1) / step * step                 // the multiple just under
        for _ in 0..<200 where below >= step {
            if works(below) { result.append(below); break }
            below -= step
        }
        var above = (buyInCents / step + 1) * step                 // the multiple just over
        for _ in 0..<200 {
            if works(above) { result.append(above); break }
            above += step
        }
        return result.sorted()
    }

    /// Things that would let a set too small for this table work: fewer players, a lower
    /// buy-in, or one colour fewer. At most one of each, nearest to what was asked.
    private static func alternatives(
        buyInCents: Int, players: Int, present: [String], inventory: ChipInventory?, locked: [String: Int]
    ) -> [ChipAlternative] {
        guard let inventory else { return [] }
        func works(buyIn: Int, players: Int, colors: [String]) -> Bool {
            let caps = inventory.maxPerPlayer(players: players).filter { colors.contains($0.key) }
            let constraints = ChipConstraints(maxPerPlayer: caps, lockedValues: locked.filter { colors.contains($0.key) })
            return !solve(buyInCents: buyIn, players: players, present: colors, constraints: constraints).options.isEmpty
        }
        var result: [ChipAlternative] = []

        if players > 2, let fewer = stride(from: players - 1, through: 2, by: -1).first(where: { works(buyIn: buyInCents, players: $0, colors: present) }) {
            result.append(ChipAlternative(kind: .fewerPlayers(fewer)))
        }
        for percent in [90, 80, 70, 60, 50] {
            let raw = Double(buyInCents) * Double(percent) / 100
            let rounded = max(25, Int((raw / 25).rounded()) * 25)
            if rounded < buyInCents, works(buyIn: rounded, players: players, colors: present) {
                result.append(ChipAlternative(kind: .lowerBuyIn(cents: rounded)))
                break
            }
        }
        if present.count > 1 {
            for color in present.reversed() {
                let rest = present.filter { $0 != color }
                if works(buyIn: buyInCents, players: players, colors: rest) {
                    result.append(ChipAlternative(kind: .dropColor(color)))
                    break
                }
            }
        }
        return result
    }
}
