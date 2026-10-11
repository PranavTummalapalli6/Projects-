//
//  StatsEngine.swift
//  PokerChipApp
//
//  What the nights add up to for the person holding the phone: their results,
//  how long they have played, streaks, and how it breaks down by place, day and
//  stake. Pure functions over the nights on the device — no network, nothing
//  random — so every figure can be checked by hand against a fixture.
//
//  Only closed nights count (the bank balanced and the night was settled), only
//  ones the person was playing in, and only the most recent night's currency,
//  since a total across currencies means nothing.
//

import Foundation

/// One closed night, reduced to what the stats need.
struct PlayedNight: Equatable, Identifiable {
    let id: UUID
    let startedAt: Date
    let timeZone: TimeZone
    let location: String?
    /// The stake: the buy-in everyone started with.
    let stakeMinor: Int
    /// What the person put in over the night (buy-in plus rebuys).
    let totalInMinor: Int
    /// Their result after the bank was reconciled.
    let netMinor: Int
    let playtimeSeconds: Int
    let currency: String

    /// Days, weekdays and months are those of the place the night was played.
    var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar
    }
}

struct StatsReport: Equatable {
    struct Breakdown: Equatable, Identifiable {
        /// Stable identity (the lower-cased place, the weekday number, the stake in cents).
        let key: String
        let label: String
        let nights: Int
        let netMinor: Int
        let seconds: Int

        var id: String { key }
    }

    struct MonthTotal: Equatable, Identifiable {
        let year: Int
        let month: Int
        let nights: Int
        let netMinor: Int

        var id: Int { year * 100 + month }
    }

    struct BankrollPoint: Equatable, Identifiable {
        let night: UUID
        let date: Date
        let cumulativeMinor: Int

        var id: UUID { night }
    }

    /// Fewer nights than this and an hourly rate is mostly luck.
    static let minimumNightsForPerHour = 10

    let currency: String
    let nights: Int
    let totalNetMinor: Int
    let totalInMinor: Int
    let totalSeconds: Int
    let wins: Int
    let losses: Int
    let breakEvens: Int
    let averageBuyInMinor: Int?
    let best: PlayedNight?
    let worst: PlayedNight?
    /// Positive: that many wins in a row up to the latest night; negative: losses; zero: the latest was break-even.
    let currentStreak: Int
    let longestWinStreak: Int
    let longestLossStreak: Int
    /// Net per hour of play, or nil until there are `minimumNightsForPerHour` nights.
    let perHourMinor: Int?
    let bankroll: [BankrollPoint]
    let byMonth: [MonthTotal]
    let byLocation: [Breakdown]
    let byWeekday: [Breakdown]
    let byStake: [Breakdown]

    var winRate: Double? { nights == 0 ? nil : Double(wins) / Double(nights) }
    var hasEnoughForPerHour: Bool { nights >= Self.minimumNightsForPerHour }
    var isEmpty: Bool { nights == 0 }
}

enum StatsEngine {
    /// The nights that count, oldest first.
    static func playedNights(from nights: [GameNight], now: Date = Date()) -> [PlayedNight] {
        let closed = nights
            .filter { $0.isSettled && !$0.isDeleted && $0.me != nil }
            .sorted { $0.startedAt != $1.startedAt ? $0.startedAt < $1.startedAt : $0.id.uuidString < $1.id.uuidString }
        guard let currency = closed.last?.currency else { return [] }

        return closed.filter { $0.currency == currency }.compactMap { night in
            let summary = NightSummary(night: night, now: now)
            guard let net = summary.myNetMinor, let totalIn = summary.myTotalInMinor else { return nil }
            return PlayedNight(
                id: night.id,
                startedAt: night.startedAt,
                timeZone: night.timeZone,
                location: PlayerNaming.trimmedOrNil(night.location),
                stakeMinor: night.defaultBuyInMinor,
                totalInMinor: totalIn,
                netMinor: net,
                playtimeSeconds: summary.playtimeSeconds,
                currency: night.currency
            )
        }
    }

    static func report(for nights: [GameNight], now: Date = Date()) -> StatsReport {
        report(for: playedNights(from: nights, now: now))
    }

    /// `played` must be oldest first, as `playedNights(from:)` returns it.
    static func report(for played: [PlayedNight]) -> StatsReport {
        let totalNet = played.reduce(0) { $0 + $1.netMinor }
        let totalIn = played.reduce(0) { $0 + $1.totalInMinor }
        let totalSeconds = played.reduce(0) { $0 + $1.playtimeSeconds }

        var running = 0
        let bankroll = played.map { night -> StatsReport.BankrollPoint in
            running += night.netMinor
            return StatsReport.BankrollPoint(night: night.id, date: night.startedAt, cumulativeMinor: running)
        }

        let (longestWin, longestLoss, current) = streaks(in: played)

        let perHour: Int?
        if played.count >= StatsReport.minimumNightsForPerHour, totalSeconds > 0 {
            perHour = Int((Double(totalNet) * 3_600 / Double(totalSeconds)).rounded())
        } else {
            perHour = nil
        }

        return StatsReport(
            currency: played.last?.currency ?? Money.defaultCurrencyCode,
            nights: played.count,
            totalNetMinor: totalNet,
            totalInMinor: totalIn,
            totalSeconds: totalSeconds,
            wins: played.filter { $0.netMinor > 0 }.count,
            losses: played.filter { $0.netMinor < 0 }.count,
            breakEvens: played.filter { $0.netMinor == 0 }.count,
            averageBuyInMinor: played.isEmpty ? nil : Int((Double(totalIn) / Double(played.count)).rounded()),
            best: extreme(of: played, by: >),
            worst: extreme(of: played, by: <),
            currentStreak: current,
            longestWinStreak: longestWin,
            longestLossStreak: longestLoss,
            perHourMinor: perHour,
            bankroll: bankroll,
            byMonth: months(of: played),
            byLocation: locations(of: played),
            byWeekday: weekdays(of: played),
            byStake: stakes(of: played)
        )
    }

    // MARK: Pieces

    /// The best or worst night; on a tie, the more recent one.
    private static func extreme(of played: [PlayedNight], by isBetter: (Int, Int) -> Bool) -> PlayedNight? {
        played.reduce(Optional<PlayedNight>.none) { best, night in
            guard let best else { return night }
            return isBetter(night.netMinor, best.netMinor) || night.netMinor == best.netMinor ? night : best
        }
    }

    private static func streaks(in played: [PlayedNight]) -> (longestWin: Int, longestLoss: Int, current: Int) {
        var longestWin = 0, longestLoss = 0, wins = 0, losses = 0
        for night in played {
            if night.netMinor > 0 {
                wins += 1; losses = 0
            } else if night.netMinor < 0 {
                losses += 1; wins = 0
            } else {
                wins = 0; losses = 0
            }
            longestWin = max(longestWin, wins)
            longestLoss = max(longestLoss, losses)
        }
        // After the loop, `wins`/`losses` are the run that ends at the latest night.
        return (longestWin, longestLoss, wins > 0 ? wins : -losses)
    }

    private static func months(of played: [PlayedNight]) -> [StatsReport.MonthTotal] {
        var totals: [Int: (year: Int, month: Int, nights: Int, net: Int)] = [:]
        for night in played {
            let parts = night.calendar.dateComponents([.year, .month], from: night.startedAt)
            guard let year = parts.year, let month = parts.month else { continue }
            var entry = totals[year * 100 + month] ?? (year, month, 0, 0)
            entry.nights += 1
            entry.net += night.netMinor
            totals[year * 100 + month] = entry
        }
        return totals.values
            .sorted { ($0.year, $0.month) < ($1.year, $1.month) }
            .map { StatsReport.MonthTotal(year: $0.year, month: $0.month, nights: $0.nights, netMinor: $0.net) }
    }

    /// Most profitable first; nights with no place recorded are listed last.
    private static func locations(of played: [PlayedNight]) -> [StatsReport.Breakdown] {
        var groups: [String: (label: String, last: Date, nights: Int, net: Int, seconds: Int)] = [:]
        for night in played {
            let key = night.location?.lowercased() ?? ""
            var entry = groups[key] ?? (night.location ?? "", night.startedAt, 0, 0, 0)
            entry.nights += 1
            entry.net += night.netMinor
            entry.seconds += night.playtimeSeconds
            if night.startedAt >= entry.last, let place = night.location { entry.last = night.startedAt; entry.label = place }
            groups[key] = entry
        }
        let named = groups.filter { !$0.key.isEmpty }
            .map { StatsReport.Breakdown(key: $0.key, label: $0.value.label, nights: $0.value.nights, netMinor: $0.value.net, seconds: $0.value.seconds) }
            .sorted { $0.netMinor != $1.netMinor ? $0.netMinor > $1.netMinor : $0.label.localizedCaseInsensitiveCompare($1.label) == .orderedAscending }
        if let none = groups[""] {
            return named + [StatsReport.Breakdown(key: "", label: "No place recorded", nights: none.nights, netMinor: none.net, seconds: none.seconds)]
        }
        return named
    }

    /// Monday first, the way a week of home games is usually thought of.
    private static func weekdays(of played: [PlayedNight]) -> [StatsReport.Breakdown] {
        var groups: [Int: (nights: Int, net: Int, seconds: Int)] = [:]
        for night in played {
            let weekday = night.calendar.component(.weekday, from: night.startedAt)       // 1 = Sunday … 7 = Saturday
            var entry = groups[weekday] ?? (0, 0, 0)
            entry.nights += 1
            entry.net += night.netMinor
            entry.seconds += night.playtimeSeconds
            groups[weekday] = entry
        }
        let symbols = Calendar(identifier: .gregorian).weekdaySymbols
        return [2, 3, 4, 5, 6, 7, 1].compactMap { weekday in
            guard let entry = groups[weekday], symbols.indices.contains(weekday - 1) else { return nil }
            return StatsReport.Breakdown(key: String(weekday), label: symbols[weekday - 1], nights: entry.nights, netMinor: entry.net, seconds: entry.seconds)
        }
    }

    /// Smallest stake first.
    private static func stakes(of played: [PlayedNight]) -> [StatsReport.Breakdown] {
        var groups: [Int: (nights: Int, net: Int, seconds: Int)] = [:]
        for night in played {
            var entry = groups[night.stakeMinor] ?? (0, 0, 0)
            entry.nights += 1
            entry.net += night.netMinor
            entry.seconds += night.playtimeSeconds
            groups[night.stakeMinor] = entry
        }
        let currency = played.last?.currency ?? Money.defaultCurrencyCode
        return groups.keys.sorted().compactMap { stake in
            groups[stake].map {
                StatsReport.Breakdown(key: String(stake), label: Money.format(cents: stake, currencyCode: currency), nights: $0.nights, netMinor: $0.net, seconds: $0.seconds)
            }
        }
    }
}
