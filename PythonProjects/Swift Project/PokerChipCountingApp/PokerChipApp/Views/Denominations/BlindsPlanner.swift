//
//  BlindsPlanner.swift
//  PokerChipApp
//
//  Blinds a table can actually pay with its chips: the small blind is a whole
//  number of the smallest chip, the big blind is twice that, and the starting
//  stack comes out near a hundred big blinds — the usual deep-stack home game.
//

import Foundation

enum BlindsPlanner {
    /// The blinds to start from. Never finer than the smallest chip allows, so a
    /// small stack of small chips can end up with fewer than 100 big blinds.
    static func suggested(stackCents: Int, smallestChipCents: Int) -> Blinds? {
        guard stackCents > 0, smallestChipCents > 0 else { return nil }
        let ideal = Double(stackCents) / 100 / Double(2 * smallestChipCents)
        let candidates = Set([max(1, Int(ideal.rounded(.down))), max(1, Int(ideal.rounded(.up)))]).sorted()
        func bigBlinds(_ steps: Int) -> Double { Double(stackCents) / Double(2 * steps * smallestChipCents) }
        guard let steps = candidates.min(by: { abs(bigBlinds($0) - 100) < abs(bigBlinds($1) - 100) }) else { return nil }
        return Blinds(smallMinor: steps * smallestChipCents, bigMinor: 2 * steps * smallestChipCents)
    }

    /// Moves the blinds up or down by one step (one smallest chip on the small blind), never below one.
    static func stepped(_ blinds: Blinds, by delta: Int, smallestChipCents: Int) -> Blinds {
        let unit = max(smallestChipCents, 1)
        let steps = max(1, blinds.smallMinor / unit + delta)
        return Blinds(smallMinor: steps * unit, bigMinor: 2 * steps * unit)
    }

    /// How many big blinds the starting stack is worth, rounded.
    static func bigBlinds(inStackCents stackCents: Int, blinds: Blinds) -> Int {
        guard blinds.bigMinor > 0 else { return 0 }
        return Int((Double(stackCents) / Double(blinds.bigMinor)).rounded())
    }
}
