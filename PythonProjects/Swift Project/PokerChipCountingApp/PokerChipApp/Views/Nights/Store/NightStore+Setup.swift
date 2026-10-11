//
//  NightStore+Setup.swift
//  PokerChipApp
//
//  Turning the setup screens' answers into a night that is running.
//

import Foundation

extension NightStore {
    /// Starts a night from a finished setup: everyone in for the buy-in, the
    /// chips as worked out, the clock running from now.
    @discardableResult
    func startNight(
        from setup: GameSetup,
        buyInMinor: Int,
        denominationsMinor: [String: Int],
        startingCounts: [String: Int]?,
        blinds: Blinds? = nil
    ) -> GameNight {
        start(
            GameNight.start(
                buyInMinor: buyInMinor,
                playerNames: setup.namesForTable,
                colors: setup.colors,
                denominationsMinor: denominationsMinor,
                startingCounts: startingCounts,
                blinds: blinds,
                location: setup.location
            )
        )
    }

    /// The most recent night played with exactly these chips (the same colours
    /// at the same buy-in), for "same chips as last time".
    func lastNight(matching setup: GameSetup) -> GameNight? {
        nights.first { $0.usesSameChips(as: setup) }
    }
}

extension GameNight {
    func usesSameChips(as setup: GameSetup) -> Bool {
        defaultBuyInMinor > 0
            && Set(denominationsMinor.keys) == setup.availableColors
            && abs(defaultBuyInMinor - Money.cents(setup.buyIn)) < 5     // the buy-in may have been rounded to a nickel
            && startingCounts != nil
    }
}

// MARK: - Names

extension PlayerNaming {
    /// The names a night would give these entries: tidied, blanks numbered by seat.
    static func finalNames(_ raw: [String]) -> [String] {
        raw.enumerated().map { clean($1, fallbackNumber: $0 + 1) }
    }

    /// Seats whose final name is shared with another seat — payments name
    /// people, so two "Sam"s would make "Sam → Sam" unreadable.
    static func duplicateSeats(in raw: [String]) -> Set<Int> {
        let names = finalNames(raw).map { $0.lowercased() }
        var seats: [String: [Int]] = [:]
        for (index, name) in names.enumerated() { seats[name, default: []].append(index) }
        return Set(seats.values.filter { $0.count > 1 }.flatMap { $0 })
    }
}
