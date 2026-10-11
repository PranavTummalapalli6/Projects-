//
//  HistoryFilter.swift
//  PokerChipApp
//
//  Finding a night in the list: free-text search over where, who and what was
//  written about it, plus filters for when, where and for how much. Pure, so the
//  rules are tested without a screen.
//

import Foundation

struct HistoryFilter: Equatable {
    enum DateRange: String, CaseIterable, Identifiable {
        case all = "All time"
        case thisMonth = "This month"
        case last30Days = "Last 30 days"
        case thisYear = "This year"

        var id: String { rawValue }
    }

    var query = ""
    var range: DateRange = .all
    /// A place, matched without regard to case.
    var place: String?
    var stakeMinor: Int?

    var trimmedQuery: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }
    /// Whether any of the chips above the list (not the search text) are set.
    var hasFilters: Bool { range != .all || place != nil || stakeMinor != nil }
    var isActive: Bool { hasFilters || !trimmedQuery.isEmpty }

    mutating func clear() { self = HistoryFilter() }

    /// The nights that match, in the order given.
    func apply(to nights: [GameNight], now: Date = Date(), calendar: Calendar = .current, locale: Locale = .current) -> [GameNight] {
        let tokens = trimmedQuery.split(whereSeparator: \.isWhitespace).map(String.init)
        return nights.filter { night in
            guard inRange(night, now: now, calendar: calendar) else { return false }
            if let place, night.location?.lowercased() != place.lowercased() { return false }
            if let stakeMinor, night.defaultBuyInMinor != stakeMinor { return false }
            guard !tokens.isEmpty else { return true }
            let haystack = Self.haystack(for: night, calendar: calendar, locale: locale)
            return tokens.allSatisfy { haystack.contains(token: $0) }
        }
    }

    private func inRange(_ night: GameNight, now: Date, calendar: Calendar) -> Bool {
        switch range {
        case .all:
            return true
        case .thisMonth:
            return calendar.isDate(night.startedAt, equalTo: now, toGranularity: .month)
        case .thisYear:
            return calendar.isDate(night.startedAt, equalTo: now, toGranularity: .year)
        case .last30Days:
            guard let from = calendar.date(byAdding: .day, value: -30, to: now) else { return true }
            return night.startedAt >= from && night.startedAt <= now.addingTimeInterval(86_400)
        }
    }

    /// Everything a person might type to find a night: the place, the people, the
    /// notes, and the date the way it reads ("August", "Friday", "2026").
    private static func haystack(for night: GameNight, calendar: Calendar, locale: Locale) -> [String] {
        let formatter = Date.FormatStyle(date: .complete, time: .omitted, locale: locale, calendar: calendar, timeZone: night.timeZone)
        var texts = night.players.map(\.name)
        if let place = night.location { texts.append(place) }
        if let notes = night.notes { texts.append(notes) }
        texts.append(night.startedAt.formatted(formatter))
        return texts
    }
}

private extension Array where Element == String {
    /// Whether any entry contains the token, ignoring case and accents.
    func contains(token: String) -> Bool {
        contains { $0.range(of: token, options: [.caseInsensitive, .diacriticInsensitive]) != nil }
    }
}

// MARK: - Months

struct HistorySection: Equatable, Identifiable {
    /// The first of the month, in the calendar used to group.
    let monthStart: Date
    let nights: [GameNight]
    /// What the person made or lost over the closed nights of this month; nil if none are closed.
    let netMinor: Int?

    var id: Date { monthStart }
}

enum HistorySections {
    /// Newest month first, newest night first within it. A night belongs to the
    /// month it was played in, wherever it was played.
    static func group(_ nights: [GameNight], calendar: Calendar = .current) -> [HistorySection] {
        var buckets: [Date: [GameNight]] = [:]
        for night in nights {
            var played = Calendar(identifier: .gregorian)
            played.timeZone = night.timeZone
            let parts = played.dateComponents([.year, .month], from: night.startedAt)
            guard let start = calendar.date(from: DateComponents(year: parts.year, month: parts.month, day: 1)) else { continue }
            buckets[start, default: []].append(night)
        }
        return buckets.keys.sorted(by: >).map { start in
            let sorted = (buckets[start] ?? []).sorted { $0.startedAt != $1.startedAt ? $0.startedAt > $1.startedAt : $0.id.uuidString < $1.id.uuidString }
            let nets = sorted.filter { $0.isSettled && $0.me != nil }.compactMap { NightSummary(night: $0).myNetMinor }
            return HistorySection(monthStart: start, nights: sorted, netMinor: nets.isEmpty ? nil : nets.reduce(0, +))
        }
    }
}

extension HistoryFilter {
    /// Places to offer as filters, most recently played first.
    static func places(in nights: [GameNight]) -> [String] { Regulars.places(from: nights) }

    /// Stakes to offer as filters, smallest first.
    static func stakes(in nights: [GameNight]) -> [Int] {
        Array(Set(nights.filter { !$0.isDeleted && $0.defaultBuyInMinor > 0 }.map(\.defaultBuyInMinor))).sorted()
    }
}
