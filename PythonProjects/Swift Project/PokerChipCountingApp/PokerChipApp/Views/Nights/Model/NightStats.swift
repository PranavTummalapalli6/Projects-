//
//  NightStats.swift
//  PokerChipApp
//
//  Figures worked out from the nights on the device — no network, so they are
//  there in a basement with no signal and agree with what History shows.
//

import Foundation

extension WeeklySummary {
    static let windowDays = 7

    /// Playtime for the last seven local days, oldest first, ending today.
    ///
    /// Two rules the first version of Poker Health got wrong, kept here:
    /// days are the *player's* local calendar days (an 8 pm game is still
    /// "today" even though it is already tomorrow in UTC), and the total is
    /// the sum of the bars so the two can never disagree. A night counts for the
    /// day it *started* on — one that runs past midnight is not split — and
    /// time on a break is not playtime.
    static func make(from nights: [GameNight], now: Date = Date(), timeZone: TimeZone = .current) -> WeeklySummary {
        let calendar = calendar(in: timeZone)
        let days = dailyTotals(from: nights, days: windowDays, now: now, calendar: calendar)
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = timeZone
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"

        let bars = days.map { DaySummary(date: formatter.string(from: $0.day), seconds: $0.seconds) }
        return WeeklySummary(totalSeconds: bars.reduce(0) { $0 + $1.seconds }, days: bars)
    }

    /// Playtime for each of the last `weeks` runs of seven local days, oldest
    /// first — the last entry is the same "this week" `make` reports.
    static func weeklyTotals(from nights: [GameNight], weeks: Int = 4, now: Date = Date(), timeZone: TimeZone = .current) -> [Int] {
        let days = dailyTotals(from: nights, days: weeks * windowDays, now: now, calendar: calendar(in: timeZone))
        return (0..<weeks).map { week in
            days[(week * windowDays)..<((week + 1) * windowDays)].reduce(0) { $0 + $1.seconds }
        }
    }

    private static func calendar(in timeZone: TimeZone) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar
    }

    /// Seconds played on each of the last `days` local days, oldest first.
    private static func dailyTotals(from nights: [GameNight], days count: Int, now: Date, calendar: Calendar) -> [(day: Date, seconds: Int)] {
        let today = calendar.startOfDay(for: now)
        let days = (0..<count).reversed().compactMap { offset in
            calendar.date(byAdding: .day, value: -offset, to: today).map { calendar.startOfDay(for: $0) }
        }
        var seconds: [Date: Int] = Dictionary(uniqueKeysWithValues: days.map { ($0, 0) })
        for night in nights where !night.isDeleted {
            let day = calendar.startOfDay(for: night.startedAt)
            guard let sofar = seconds[day] else { continue }
            seconds[day] = sofar + night.playtimeSeconds(at: now)
        }
        return days.map { ($0, seconds[$0] ?? 0) }
    }
}

// MARK: - This week against the weeks before

/// How this week compares with last week, and the four weeks together. Said
/// plainly — a number and a direction, never a scolding.
struct WeekTrend: Equatable {
    /// Seconds played in each of the last four runs of seven days, oldest first.
    let weeks: [Int]

    init(weeks: [Int]) {
        self.weeks = weeks
    }

    init(nights: [GameNight], now: Date = Date(), timeZone: TimeZone = .current) {
        self.init(weeks: WeeklySummary.weeklyTotals(from: nights, weeks: 4, now: now, timeZone: timeZone))
    }

    var thisWeek: Int { weeks.last ?? 0 }
    var lastWeek: Int { weeks.count >= 2 ? weeks[weeks.count - 2] : 0 }
    var difference: Int { thisWeek - lastWeek }
    var hasAnyPlay: Bool { weeks.contains { $0 > 0 } }

    /// "1h 20m more than last week."
    var comparison: String {
        if thisWeek == 0 && lastWeek == 0 { return "No games this week or last." }
        if lastWeek == 0 { return "Nothing played last week." }
        if difference == 0 { return "The same as last week." }
        let amount = DurationFormat.compact(abs(difference))
        return difference > 0 ? "\(amount) more than last week." : "\(amount) less than last week."
    }

    var spokenComparison: String {
        if thisWeek == 0 && lastWeek == 0 { return comparison }
        if lastWeek == 0 || difference == 0 { return comparison }
        let amount = DurationFormat.spoken(abs(difference))
        return difference > 0 ? "\(amount) more than last week." : "\(amount) less than last week."
    }

    /// Names for the four bars, oldest first.
    static let labels = ["3 weeks ago", "2 weeks ago", "Last week", "This week"]
}
