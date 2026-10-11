//
//  DenominationEngineTests.swift
//  PokerChipAppTests
//
//  Locks the invariants of the suggested-chips solver, so a future tweak can't
//  quietly break them:
//
//    1. The stack sums to the buy-in exactly (rounded to the nearest nickel),
//       in integer cents.
//    2. Values come from the clean ladder — 0.05, 0.10, then multiples of
//       0.25 — with at most one nickel-safe exception (the lowest colour).
//    3. Values strictly increase and counts strictly decrease with colour rank
//       (White < Red < Blue < Green < Black).
//    4. 20–30 chips in total is a *soft* goal: it yields to 1–3, so it is
//       measured as a rate, not required for every input.
//

import XCTest
@testable import PokerChipApp

private struct Case: CustomStringConvertible {
    let buyInCents: Int
    let players: Int
    let colors: Set<String>

    var buyIn: Double { Double(buyInCents) / 100 }
    var description: String {
        "buy-in \(Money.format(cents: buyInCents)), \(players) players, \(allChipColors.filter { colors.contains($0) })"
    }
}

private struct Outcome {
    let rows: [(color: String, valueCents: Int, count: Int)]
    var totalChips: Int { rows.reduce(0) { $0 + $1.count } }
    var totalCents: Int { rows.reduce(0) { $0 + $1.valueCents * $1.count } }
}

final class DenominationEngineTests: XCTestCase {

    // MARK: Helpers

    private func solve(_ testCase: Case) -> Outcome? {
        let (counts, values) = calculateFlexibleChipDistribution(
            buyIn: testCase.buyIn,
            players: testCase.players,
            availableColors: testCase.colors
        )
        guard let counts else { return nil }
        let rows = allChipColors.filter { testCase.colors.contains($0) }.compactMap { color -> (String, Int, Int)? in
            guard let value = values[color], let count = counts[color] else { return nil }
            return (color, Money.cents(value), count)
        }
        return Outcome(rows: rows.map { (color: $0.0, valueCents: $0.1, count: $0.2) })
    }

    /// The buy-in the solver actually targets: rounded to the nearest nickel.
    private func nickelRounded(_ cents: Int) -> Int {
        max(5, Int((Double(cents) / 5).rounded()) * 5)
    }

    private func isCleanLadderValue(_ cents: Int) -> Bool {
        cents == 5 || cents == 10 || (cents >= 25 && cents % 25 == 0)
    }

    /// Asserts the hard invariants for one solved case. Returns false if any failed.
    @discardableResult
    private func assertHardInvariants(_ outcome: Outcome, for testCase: Case, file: StaticString = #filePath, line: UInt = #line) -> Bool {
        var ok = true
        func fail(_ message: String) {
            ok = false
            XCTFail("\(testCase): \(message)", file: file, line: line)
        }

        if outcome.totalCents != nickelRounded(testCase.buyInCents) {
            fail("stack is worth \(outcome.totalCents)¢, expected \(nickelRounded(testCase.buyInCents))¢")
        }

        let present = allChipColors.filter { testCase.colors.contains($0) }
        if outcome.rows.map(\.color) != present {
            fail("rows \(outcome.rows.map(\.color)) don't match the colours asked for")
        }

        for row in outcome.rows where row.count < 1 {
            fail("\(row.color) has no chips")
        }

        let notClean = outcome.rows.filter { !isCleanLadderValue($0.valueCents) }
        if notClean.count > 1 {
            fail("more than one value off the clean ladder: \(notClean.map { "\($0.color)=\($0.valueCents)¢" })")
        }
        if let exception = notClean.first, exception.color != present.first {
            fail("only the lowest colour may be off the ladder, but \(exception.color)=\(exception.valueCents)¢ is")
        }

        for (lower, higher) in zip(outcome.rows, outcome.rows.dropFirst()) {
            if !(lower.valueCents < higher.valueCents) {
                fail("values don't strictly increase: \(lower.color)=\(lower.valueCents)¢, \(higher.color)=\(higher.valueCents)¢")
            }
            if !(lower.count > higher.count) {
                fail("counts don't strictly decrease: \(lower.color)×\(lower.count), \(higher.color)×\(higher.count)")
            }
        }
        return ok
    }

    private func randomCases(count: Int, seed: UInt64) -> [Case] {
        var rng = SplitMix64(seed: seed)
        return (0..<count).map { _ in
            // Real buy-ins: whole dollars and nickels most of the time, an
            // occasional odd penny amount to exercise the rounding.
            let style = Int.random(in: 0..<10, using: &rng)
            let buyInCents: Int
            switch style {
            case 0..<6: buyInCents = Int.random(in: 2...400, using: &rng) * 100 / 2   // $1.00 – $200.00 in 50¢ steps
            case 6..<9: buyInCents = Int.random(in: 20...2_000, using: &rng) * 5      // nickels up to $100
            default: buyInCents = Int.random(in: 100...20_000, using: &rng)           // any cent amount up to $200
            }
            let players = Int.random(in: 2...10, using: &rng)
            var colors = Set(allChipColors.filter { _ in Bool.random(using: &rng) })
            if colors.isEmpty { colors = [allChipColors[Int.random(in: 0..<allChipColors.count, using: &rng)]] }
            return Case(buyInCents: buyInCents, players: players, colors: colors)
        }
    }

    // MARK: Hard invariants

    func testHardInvariantsHoldAcrossSeededRandomInputs() {
        let cases = randomCases(count: 700, seed: 20_261_008)
        var solved = 0
        var firstFailure: Case?

        for testCase in cases {
            guard let outcome = solve(testCase) else { continue }
            solved += 1
            if !assertHardInvariants(outcome, for: testCase), firstFailure == nil {
                firstFailure = testCase
            }
        }

        XCTAssertNil(firstFailure, "first failing input: \(String(describing: firstFailure))")
        XCTAssertGreaterThan(solved, cases.count * 8 / 10, "the solver should find an answer for the great majority of inputs")
    }

    func testHardInvariantsHoldForEveryRealisticHomeGame() {
        // $10–$100 in $5 steps, small and large tables, full and partial sets.
        let colorSets: [Set<String>] = [
            Set(allChipColors),
            ["White", "Red", "Blue"],
            ["White", "Red", "Blue", "Green"],
            ["White", "Blue", "Black"],
        ]
        for dollars in stride(from: 10, through: 100, by: 5) {
            for players in [2, 4, 6, 8, 10] {
                for colors in colorSets {
                    let testCase = Case(buyInCents: dollars * 100, players: players, colors: colors)
                    guard let outcome = solve(testCase) else {
                        XCTFail("\(testCase): a realistic home game should always have a suggestion")
                        continue
                    }
                    assertHardInvariants(outcome, for: testCase)
                }
            }
        }
    }

    // MARK: Soft goal

    func testMostRealisticGamesLandInTheTwentyToThirtyChipWindow() {
        var inWindow = 0
        var total = 0
        for dollars in stride(from: 10, through: 100, by: 5) {
            for players in [2, 4, 6, 8, 10] {
                let testCase = Case(buyInCents: dollars * 100, players: players, colors: Set(allChipColors))
                guard let outcome = solve(testCase) else { continue }
                total += 1
                if (20...30).contains(outcome.totalChips) { inWindow += 1 }
            }
        }
        XCTAssertGreaterThan(total, 0)
        XCTAssertGreaterThanOrEqual(Double(inWindow) / Double(total), 0.9, "\(inWindow) of \(total) games were in the 20–30 chip window")
    }

    func testMoreChipsAreSuggestedForFewerPlayers() {
        // The target slides from 30 chips at two players to 20 at ten.
        let few = solve(Case(buyInCents: 5_000, players: 2, colors: Set(allChipColors)))
        let many = solve(Case(buyInCents: 5_000, players: 10, colors: Set(allChipColors)))
        XCTAssertNotNil(few)
        XCTAssertNotNil(many)
        if let few, let many {
            XCTAssertGreaterThanOrEqual(few.totalChips, many.totalChips)
        }
    }

    // MARK: Specific cases

    func testTwentyFiveDollarsSixPlayersNeverBuriesTheTableInWhiteChips() {
        // Regression: this used to suggest 85 white chips.
        let testCase = Case(buyInCents: 2_500, players: 6, colors: Set(allChipColors))
        guard let outcome = solve(testCase) else { return XCTFail("expected a suggestion for \(testCase)") }
        assertHardInvariants(outcome, for: testCase)
        XCTAssertLessThanOrEqual(outcome.totalChips, 30)
        XCTAssertLessThan(outcome.rows.first?.count ?? 0, 30)
    }

    func testABuyInIsRoundedToTheNearestNickel() {
        let testCase = Case(buyInCents: 2_503, players: 6, colors: ["White", "Red", "Blue"])
        guard let outcome = solve(testCase) else { return XCTFail("expected a suggestion") }
        XCTAssertEqual(outcome.totalCents, 2_505)
    }

    func testASingleColourSplitsTheBuyInEvenly() {
        let testCase = Case(buyInCents: 2_500, players: 6, colors: ["Red"])
        guard let outcome = solve(testCase), let row = outcome.rows.first else { return XCTFail("expected a suggestion") }
        XCTAssertEqual(outcome.rows.count, 1)
        XCTAssertEqual(row.valueCents * row.count, 2_500)
    }

    func testNoColoursMeansNoSuggestion() {
        let (counts, values) = calculateFlexibleChipDistribution(buyIn: 25, players: 6, availableColors: [])
        XCTAssertNil(counts)
        XCTAssertTrue(values.isEmpty)
    }

    func testABuyInTooSmallForFiveColoursHasNoSuggestionInsteadOfAWrongOne() {
        let (counts, _) = calculateFlexibleChipDistribution(buyIn: 1, players: 6, availableColors: Set(allChipColors))
        XCTAssertNil(counts, "the answer is 'too small', never a stack that doesn't follow the rules")
    }

    func testTheSmallestBuyInIsTheCheapestStackWhoseCountsStillFallWithValue() {
        // With counts that must fall at every step, the cheapest correct stacks
        // are 3-2-1 at 5¢-10¢-25¢ ($0.60) for three colours, 4-3-2-1 at
        // 5¢-10¢-25¢-50¢ ($1.50) for four, and 5-4-3-2-1 at
        // 5¢-10¢-25¢-50¢-75¢ ($3.15) for five. One nickel less has no answer.
        let floors: [(colors: Set<String>, cents: Int)] = [
            (["White", "Red", "Blue"], 60),
            (["White", "Red", "Blue", "Green"], 150),
            (Set(allChipColors), 315),
        ]
        for (colors, cents) in floors {
            let atFloor = Case(buyInCents: cents, players: 6, colors: colors)
            guard let outcome = solve(atFloor) else { XCTFail("\(atFloor) should have a stack"); continue }
            assertHardInvariants(outcome, for: atFloor)

            let below = Case(buyInCents: cents - 5, players: 6, colors: colors)
            XCTAssertNil(solve(below), "\(below) should be too small")
        }
    }

    func testTinyBuyInsThatUsedToComeBackInvertedAreNowCorrectOrRefused() {
        // Regression: $1.35 over White/Green/Black used to return Green×1,
        // Black×3 — an exact sum, but counts rising with value.
        let testCase = Case(buyInCents: 135, players: 6, colors: ["White", "Green", "Black"])
        guard let outcome = solve(testCase) else { return XCTFail("a correct stack exists: 18 × 5¢, 2 × 10¢, 1 × 25¢") }
        assertHardInvariants(outcome, for: testCase)
    }

    // MARK: Performance

    func testTheSolverStaysFastEnoughToRunWhileTheScreenIsOpening() {
        // The screen computes once, off the main thread, so this is a budget
        // for responsiveness, not a micro-benchmark. Measured on a Debug
        // simulator build, which is several times slower than Release.
        let cases = randomCases(count: 150, seed: 42)
        var slowest: TimeInterval = 0
        var slowestCase: Case?
        for testCase in cases {
            let start = Date()
            _ = calculateFlexibleChipDistribution(buyIn: testCase.buyIn, players: testCase.players, availableColors: testCase.colors)
            let elapsed = Date().timeIntervalSince(start)
            if elapsed > slowest { slowest = elapsed; slowestCase = testCase }
        }
        XCTAssertLessThan(slowest, 0.5, "slowest was \(String(format: "%.0f", slowest * 1000)) ms for \(String(describing: slowestCase))")
    }
}
