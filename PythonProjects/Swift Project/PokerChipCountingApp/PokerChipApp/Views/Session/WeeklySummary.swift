//
//  WeeklySummary.swift
//  PokerChipApp
//

import Foundation

/// Playtime over the last 7 days (today inclusive), plus a per-day breakdown
/// for the "Poker Health" dashboard's bar chart. Worked out on the device from
/// the nights it holds (see `WeeklySummary.make` in Nights/Model/NightStats.swift).
struct WeeklySummary: Codable, Hashable {
    let totalSeconds: Int
    let days: [DaySummary]

    struct DaySummary: Codable, Hashable {
        let date: String
        let seconds: Int
    }
}
