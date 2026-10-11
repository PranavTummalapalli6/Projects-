//
//  ChipPlannerTests.swift
//  PokerChipAppTests
//
//  Suggestions that respect what a person owns: never more chips of a colour
//  than the set holds, values that can be locked or are printed on the chips,
//  other ways to deal the same buy-in, and — when it can't be done — a plain
//  reason and something that would work. Every invariant of the solver still
//  holds under all of it.
//

import XCTest
@testable import PokerChipApp

private func assertSound(_ option: ChipOption, buyInCents: Int, colors: [String], file: StaticString = #filePath, line: UInt = #line) {
    XCTAssertEqual(option.totalCents, buyInCents, "adds up exactly: \(option)", file: file, line: line)
    let ordered = allChipColors.filter { colors.contains($0) }
    XCTAssertEqual(Set(option.counts.keys), Set(ordered), file: file, line: line)
    let values = ordered.map { option.valuesCents[$0] ?? 0 }
    let counts = ordered.map { option.counts[$0] ?? 0 }
    XCTAssertTrue(zip(values, values.dropFirst()).allSatisfy { $0 < $1 }, "values rise with rank: \(values)", file: file, line: line)
    XCTAssertTrue(zip(counts, counts.dropFirst()).allSatisfy { $0 > $1 }, "counts fall with rank: \(counts)", file: file, line: line)
    XCTAssertTrue(counts.allSatisfy { $0 >= 1 }, file: file, line: line)
    XCTAssertTrue(values.allSatisfy { $0 % 5 == 0 }, "every chip is worth a whole number of nickels", file: file, line: line)
}

final class ChipPlannerTests: XCTestCase {
    private let all = Set(allChipColors)

    // MARK: Without any limits it is the solver it always was

    func testWithNoLimitsTheRecommendedStackIsExactlyWhatTheSolverAlwaysGave() {
        var rng = SplitMix64(seed: 4_242)
        for _ in 0..<300 {
            let buyIn = Double(Int.random(in: 5...20_000, using: &rng)) / 100
            let players = Int.random(in: 2...10, using: &rng)
            let colors = Set(allChipColors.filter { _ in Bool.random(using: &rng) })
            let plan = ChipPlanner.plan(buyIn: buyIn, players: players, colors: colors)
            let (counts, values) = calculateFlexibleChipDistribution(buyIn: buyIn, players: players, availableColors: colors)

            if let counts {
                XCTAssertEqual(plan.recommended?.counts, counts, "\(buyIn) \(players) \(colors)")
                XCTAssertEqual(plan.recommended?.valuesCents, values.mapValues { Int(($0 * 100).rounded()) })
                XCTAssertNil(plan.failure)
            } else {
                XCTAssertTrue(plan.options.isEmpty, "\(buyIn) \(players) \(colors)")
                XCTAssertNotNil(plan.failure)
            }
        }
    }

    func testEveryOptionOnOfferKeepsEveryRuleOfASound() {
        var rng = SplitMix64(seed: 99)
        var optionsSeen = 0
        for _ in 0..<200 {
            let buyIn = Double(Int.random(in: 500...10_000, using: &rng)) / 100
            let players = Int.random(in: 2...10, using: &rng)
            let colors = allChipColors.filter { _ in Int.random(in: 0...3, using: &rng) > 0 }
            guard colors.count >= 2 else { continue }
            let plan = ChipPlanner.plan(buyIn: buyIn, players: players, colors: Set(colors))
            for option in plan.options {
                assertSound(option, buyInCents: plan.buyInCents, colors: colors)
                optionsSeen += 1
            }
            XCTAssertEqual(Set(plan.options.map(\.id)).count, plan.options.count, "no option is offered twice")
            XCTAssertEqual(plan.options.first?.kind, plan.options.isEmpty ? nil : .recommended)
        }
        XCTAssertGreaterThan(optionsSeen, 200)
    }

    func testAnotherOptionReallyIsDifferentInTheWayItSays() {
        var fewer = 0, finer = 0
        for buyIn in stride(from: 10.0, through: 200.0, by: 5.0) {
            let plan = ChipPlanner.plan(buyIn: buyIn, players: 6, colors: all)
            guard let recommended = plan.recommended else { continue }
            for option in plan.options.dropFirst() {
                switch option.kind {
                case .fewerChips:
                    XCTAssertLessThan(option.totalChips, recommended.totalChips)
                    fewer += 1
                case .finerChips:
                    XCTAssertLessThan(option.smallestChipCents, recommended.smallestChipCents)
                    finer += 1
                case .recommended:
                    XCTFail("only one recommended stack")
                }
            }
        }
        XCTAssertGreaterThan(fewer, 0, "some buy-ins can be dealt with fewer chips")
        XCTAssertGreaterThan(finer, 0, "and some with a smaller smallest chip")
    }

    // MARK: What is owned

    func testASetNeverGivesAPlayerMoreChipsOfAColourThanTheSetHasForTheTable() {
        let set = ChipInventory.preset(.fiveHundred, colors: allChipColors)
        XCTAssertEqual(set.owned, ["White": 100, "Red": 100, "Blue": 100, "Green": 100, "Black": 100])
        var rng = SplitMix64(seed: 7)
        for _ in 0..<150 {
            let players = Int.random(in: 2...10, using: &rng)
            let buyIn = Double(Int.random(in: 500...20_000, using: &rng)) / 100
            let plan = ChipPlanner.plan(buyIn: buyIn, players: players, colors: all, inventory: set)
            for option in plan.options {
                assertSound(option, buyInCents: plan.buyInCents, colors: allChipColors)
                for (color, count) in option.counts {
                    XCTAssertLessThanOrEqual(count * players, set.owned[color] ?? 0, "\(color): \(count) × \(players) players > owned")
                }
            }
        }
    }

    func testPresetsSplitTheSetAcrossTheColoursInUse() {
        XCTAssertEqual(ChipInventory.preset(.hundred, colors: ["White", "Red", "Blue"]).owned, ["White": 34, "Red": 33, "Blue": 33])
        XCTAssertEqual(ChipInventory.preset(.twoHundred, colors: allChipColors).totalOwned, 200)
        XCTAssertEqual(ChipInventory.preset(.threeHundred, colors: ["Black", "White"]).owned, ["White": 150, "Black": 150])
        XCTAssertEqual(ChipInventory.preset(.fiveHundred, colors: []).owned, [:])
        XCTAssertEqual(ChipInventory.SetSize.allCases.map(\.rawValue), [100, 200, 300, 500])
    }

    func testTheLimitPerPlayerIsTheSetDividedByThePlayers() {
        XCTAssertEqual(ChipInventory(owned: ["White": 100, "Red": 50], printedValues: nil).maxPerPlayer(players: 6), ["White": 16, "Red": 8])
    }

    func testASetTooSmallForTheTableSaysSoAndOffersWhatWouldWork() throws {
        let small = ChipInventory.preset(.hundred, colors: allChipColors)                 // 20 of each
        let plan = ChipPlanner.plan(buyIn: 25, players: 8, colors: all, inventory: small)  // 2 of each per player

        XCTAssertTrue(plan.options.isEmpty)
        XCTAssertEqual(plan.failure, .setTooSmall)
        XCTAssertFalse(plan.alternatives.isEmpty, "never a dead end")

        // Every alternative offered really does work.
        for alternative in plan.alternatives {
            switch alternative.kind {
            case .fewerPlayers(let players):
                XCTAssertLessThan(players, 8)
                XCTAssertFalse(ChipPlanner.plan(buyIn: 25, players: players, colors: all, inventory: small).options.isEmpty)
            case .lowerBuyIn(let cents):
                XCTAssertLessThan(cents, 2_500)
                XCTAssertFalse(ChipPlanner.plan(buyIn: Double(cents) / 100, players: 8, colors: all, inventory: small).options.isEmpty)
            case .dropColor(let color):
                XCTAssertFalse(ChipPlanner.plan(buyIn: 25, players: 8, colors: all.subtracting([color]), inventory: small).options.isEmpty)
            }
        }
    }

    func testTheSameTableOnABiggerSetIsFine() {
        let big = ChipInventory.preset(.fiveHundred, colors: allChipColors)
        let plan = ChipPlanner.plan(buyIn: 25, players: 8, colors: all, inventory: big)
        XCTAssertNil(plan.failure)
        XCTAssertNotNil(plan.recommended)
    }

    func testABuyInTheColoursThemselvesCantSplitIsStillTooSmallNotAProblemWithTheSet() {
        let big = ChipInventory.preset(.fiveHundred, colors: allChipColors)
        let plan = ChipPlanner.plan(buyIn: 1, players: 6, colors: all, inventory: big)
        guard case .tooSmall(let next) = plan.failure else { return XCTFail("expected tooSmall, got \(String(describing: plan.failure))") }
        XCTAssertEqual(next, 315, "five colours need $3.15 at the least")
    }

    func testNoColoursIsAPlainAnswerNotACrash() {
        XCTAssertEqual(ChipPlanner.plan(buyIn: 25, players: 6, colors: []).failure, .noColors)
    }

    func testOneColourUsesTheCleanValueNearestTheUsualChipCountWithinTheSet() throws {
        let plain = try XCTUnwrap(ChipPlanner.plan(buyIn: 25, players: 6, colors: ["White"]).recommended)
        XCTAssertEqual(plain.totalCents, 2_500)
        let (count, _) = (plain.counts["White"] ?? 0, 0)
        XCTAssertTrue((20...30).contains(count))

        let limited = ChipInventory(owned: ["White": 60], printedValues: nil)                // 10 each for six players
        let capped = ChipPlanner.plan(buyIn: 25, players: 6, colors: ["White"], inventory: limited)
        let option = try XCTUnwrap(capped.recommended)
        XCTAssertLessThanOrEqual(option.counts["White"] ?? 99, 10)
        XCTAssertEqual(option.totalCents, 2_500)

        let tiny = ChipInventory(owned: ["White": 12], printedValues: nil)                   // 2 each for six players
        XCTAssertEqual(ChipPlanner.plan(buyIn: 25, players: 6, colors: ["White"], inventory: tiny).failure, .setTooSmall)
    }

    // MARK: Locking a value

    func testALockedValueStaysPutWhileTheRestIsWorkedOutAroundIt() throws {
        let unlocked = try XCTUnwrap(ChipPlanner.plan(buyIn: 25, players: 6, colors: all).recommended)
        var any = false
        for color in allChipColors {
            for value in [25, 50, 100, 250, 500] {
                let plan = ChipPlanner.plan(buyIn: 25, players: 6, colors: all, lockedValues: [color: value])
                guard let option = plan.recommended else { continue }
                any = true
                XCTAssertEqual(option.valuesCents[color], value, "\(color) kept its \(value)")
                assertSound(option, buyInCents: 2_500, colors: allChipColors)
            }
        }
        XCTAssertTrue(any)
        XCTAssertEqual(unlocked.valuesCents.count, 5)
    }

    func testValuesThatCantBeOrderedLowToHighAreSaidToConflict() {
        let plan = ChipPlanner.plan(buyIn: 25, players: 6, colors: ["White", "Red", "Blue"], lockedValues: ["White": 500, "Red": 100])
        XCTAssertTrue(plan.options.isEmpty)
        XCTAssertEqual(plan.failure, .valuesConflict)
    }

    // MARK: Chips with values printed on them

    func testChipsWithPrintedValuesAreOnlyDealtCountsNeverNewValues() throws {
        let printed = ChipInventory(
            owned: ["White": 200, "Red": 100, "Blue": 100, "Green": 100],
            printedValues: ["White": 100, "Red": 500, "Blue": 2_500, "Green": 10_000]           // $1, $5, $25, $100
        )
        let plan = ChipPlanner.plan(buyIn: 200, players: 6, colors: ["White", "Red", "Blue", "Green"], inventory: printed)
        let option = try XCTUnwrap(plan.recommended)
        XCTAssertEqual(option.valuesCents, ["White": 100, "Red": 500, "Blue": 2_500, "Green": 10_000])
        assertSound(option, buyInCents: 20_000, colors: ["White", "Red", "Blue", "Green"])
        for (color, count) in option.counts { XCTAssertLessThanOrEqual(count * 6, printed.owned[color] ?? 0) }
    }

    func testAnAmountPrintedChipsCantMakeSaysWhatNearbyAmountsCan() throws {
        let printed = ChipInventory(owned: ["White": 200, "Red": 100], printedValues: ["White": 100, "Red": 500])      // $1 and $5
        let plan = ChipPlanner.plan(buyIn: 2.50, players: 4, colors: ["White", "Red"], inventory: printed)
        guard case .noExactSplit(let nearby) = plan.failure else { return XCTFail("expected noExactSplit, got \(String(describing: plan.failure))") }
        XCTAssertTrue(plan.options.isEmpty)
        XCTAssertFalse(nearby.isEmpty)
        for cents in nearby {
            XCTAssertFalse(ChipPlanner.plan(buyIn: Double(cents) / 100, players: 4, colors: ["White", "Red"], inventory: printed).options.isEmpty, "$\(cents) should work")
        }
    }

    func testPrintedValuesOutOfOrderAreAConflictNotAGuess() {
        let backwards = ChipInventory(owned: ["White": 100, "Red": 100], printedValues: ["White": 500, "Red": 100])
        XCTAssertEqual(ChipPlanner.plan(buyIn: 50, players: 4, colors: ["White", "Red"], inventory: backwards).failure, .valuesConflict)
    }
}

final class BlindsPlannerTests: XCTestCase {
    func testTheStackComesOutNearAHundredBigBlinds() {
        XCTAssertEqual(BlindsPlanner.suggested(stackCents: 10_000, smallestChipCents: 25), Blinds(smallMinor: 50, bigMinor: 100))
        XCTAssertEqual(BlindsPlanner.suggested(stackCents: 5_000, smallestChipCents: 25), Blinds(smallMinor: 25, bigMinor: 50))
        XCTAssertEqual(BlindsPlanner.suggested(stackCents: 2_500, smallestChipCents: 5), Blinds(smallMinor: 15, bigMinor: 30), "83 big blinds is nearer 100 than 125 is")
    }

    func testTheSmallestChipLimitsHowFineTheBlindsGet() {
        // $25 with a smallest chip of 25¢: the smallest big blind is 50¢ — 50 big blinds, not 100.
        let blinds = BlindsPlanner.suggested(stackCents: 2_500, smallestChipCents: 25)
        XCTAssertEqual(blinds, Blinds(smallMinor: 25, bigMinor: 50))
        XCTAssertEqual(BlindsPlanner.bigBlinds(inStackCents: 2_500, blinds: blinds ?? Blinds(smallMinor: 1, bigMinor: 2)), 50)
    }

    func testTheBlindsCanAlwaysBePaidWithTheSmallestChip() {
        var rng = SplitMix64(seed: 31)
        for _ in 0..<500 {
            let unit = [5, 10, 25, 50, 100].randomElement(using: &rng) ?? 25
            let stack = Int.random(in: unit * 4...2_000_000, using: &rng)
            guard let blinds = BlindsPlanner.suggested(stackCents: stack, smallestChipCents: unit) else { return XCTFail("no blinds") }
            XCTAssertEqual(blinds.smallMinor % unit, 0)
            XCTAssertEqual(blinds.bigMinor, 2 * blinds.smallMinor)
            XCTAssertGreaterThan(blinds.smallMinor, 0)
            let bigBlinds = Double(stack) / Double(blinds.bigMinor)
            XCTAssertTrue((25...400).contains(bigBlinds) || blinds.smallMinor == unit, "\(stack) / \(unit): \(bigBlinds) big blinds")
        }
    }

    func testStepsMoveByOneSmallestChipAndNeverBelowOne() {
        let start = Blinds(smallMinor: 50, bigMinor: 100)
        XCTAssertEqual(BlindsPlanner.stepped(start, by: 1, smallestChipCents: 25), Blinds(smallMinor: 75, bigMinor: 150))
        XCTAssertEqual(BlindsPlanner.stepped(start, by: -1, smallestChipCents: 25), Blinds(smallMinor: 25, bigMinor: 50))
        XCTAssertEqual(BlindsPlanner.stepped(Blinds(smallMinor: 25, bigMinor: 50), by: -1, smallestChipCents: 25), Blinds(smallMinor: 25, bigMinor: 50))
    }

    func testNothingToSuggestWithoutAStackOrAChip() {
        XCTAssertNil(BlindsPlanner.suggested(stackCents: 0, smallestChipCents: 25))
        XCTAssertNil(BlindsPlanner.suggested(stackCents: 2_500, smallestChipCents: 0))
    }
}
