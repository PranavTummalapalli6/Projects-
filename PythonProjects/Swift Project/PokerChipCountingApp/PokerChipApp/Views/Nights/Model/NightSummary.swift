//
//  NightSummary.swift
//  PokerChipApp
//
//  What a closed night means for the person holding the phone: their result
//  after the bank was reconciled, how long they played, and what that works out
//  to per hour.
//

import Foundation

struct NightSummary: Equatable {
    /// Your result after any bank resolution — what you actually pay or receive.
    /// Nil if you weren't playing, or the night doesn't balance yet.
    let myNetMinor: Int?
    let myTotalInMinor: Int?
    let playtimeSeconds: Int
    /// Net per hour of play, or nil for a night too short for the figure to mean anything.
    let perHourMinor: Int?
    let potMinor: Int

    /// Under five minutes the per-hour figure is noise.
    static let minimumSecondsForPerHour = 300

    init(night: GameNight, now: Date = Date()) {
        potMinor = night.totalInMinor
        playtimeSeconds = night.playtimeSeconds(at: now)

        if let me = night.me {
            myTotalInMinor = me.totalInMinor
            myNetMinor = night.settlementEntries()?.first { $0.id == me.id }?.netMinor ?? me.netMinor
        } else {
            myTotalInMinor = nil
            myNetMinor = nil
        }

        if let net = myNetMinor, playtimeSeconds >= Self.minimumSecondsForPerHour {
            perHourMinor = Int((Double(net) * 3_600 / Double(playtimeSeconds)).rounded())
        } else {
            perHourMinor = nil
        }
    }
}
