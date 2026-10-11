//
//  NightActivityAttributes.swift
//  PokerChipApp
//
//  Compiled into the app and its widgets. What the Lock Screen and the Dynamic
//  Island show for a night in progress: the clock, the money on the table and the
//  number of players. The clock is not a number the app keeps updating — it is a
//  moment the system counts up from, so it stays right with the app closed.
//

import ActivityKit
import Foundation

struct NightActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        /// The moment the clock would have read zero had it never stopped: the start
        /// of the night plus the time spent on breaks.
        var clockStart: Date
        /// While on a break, how long had been played when it began. Nil while the clock runs.
        var frozenSeconds: Int?
        var players: Int
        var inPlayMinor: Int
        var currencyCode: String

        var isOnBreak: Bool { frozenSeconds != nil }
    }

    var nightID: String
}
