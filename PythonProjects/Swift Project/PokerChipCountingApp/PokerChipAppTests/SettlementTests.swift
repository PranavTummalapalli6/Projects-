//
//  SettlementTests.swift
//  PokerChipAppTests
//
//  The money rules of a night, held to the standard the brief sets: over
//  thousands of randomized nights — balanced and not, with every way of
//  resolving a mismatch — balances reconcile to the cent, each debtor's payments
//  sum to their debt, each creditor's receipts to their credit, there are no
//  negative or self payments, and the answer is deterministic.
//

import XCTest
@testable import PokerChipApp

private let t0 = Date(timeIntervalSince1970: 1_800_000_000)

// MARK: - Generating nights

private let namePool = ["Sam", "Alex", "Jo", "Pat", "Robin", "Kim", "Lee", "Max", "Ana", "Tom", "Sam", "Alex"]
private let buyInChoices = [500, 1_000, 1_250, 2_000, 2_500, 3_333, 5_000, 10_000]

private func randomNight(_ rng: inout SplitMix64, balanced: Bool) -> GameNight {
    let count = Int.random(in: 2...10, using: &rng)
    var night = GameNight.start(
        now: t0,
        buyInMinor: buyInChoices.randomElement(using: &rng) ?? 2_500,
        playerNames: (0..<count).map { _ in namePool.randomElement(using: &rng) ?? "Sam" },
        colors: ["White", "Red"],
        denominationsMinor: ["White": 25, "Red": 100]
    )
    // Rebuys, of varying size.
    for index in night.players.indices {
        for _ in 0..<Int.random(in: 0...3, using: &rng) {
            night.rebuy(night.players[index].id, amountMinor: buyInChoices.randomElement(using: &rng), at: t0)
        }
    }

    let totalIn = night.totalInMinor
    var totalOut = totalIn
    if !balanced {
        let offset = Int.random(in: 1...5_000, using: &rng)
        totalOut = Bool.random(using: &rng) ? max(0, totalIn - offset) : totalIn + offset
        if totalOut == totalIn { totalOut += 1 }
    }

    // Split totalOut into `count` non-negative parts with random cut points.
    var cuts = (0..<(count - 1)).map { _ in Int.random(in: 0...totalOut, using: &rng) }
    cuts.sort()
    let bounds = [0] + cuts + [totalOut]
    for (index, player) in night.players.enumerated() {
        night.cashOut(player.id, amountMinor: bounds[index + 1] - bounds[index], at: t0)
    }

    let delta = night.bankDeltaMinor
    if delta != 0 {
        var kinds: [BankResolution.Kind] = [.assign, .split]
        if delta < 0 { kinds.append(.tip) }
        let kind = kinds.randomElement(using: &rng) ?? .split
        let target = night.players.randomElement(using: &rng)?.id
        night.resolveBank(kind, playerID: kind == .assign ? target : nil)
    }
    return night
}

/// The party a payment names, as a key that also covers the house (nil id).
private func key(_ id: UUID?) -> String { id?.uuidString ?? "house" }

final class SettlementPropertyTests: XCTestCase {
    private func assertSettlementIsSound(_ night: GameNight, _ description: String, file: StaticString = #filePath, line: UInt = #line) {
        guard let entries = night.settlementEntries() else {
            return XCTFail("\(description): the night should balance", file: file, line: line)
        }
        XCTAssertEqual(entries.reduce(0) { $0 + $1.netMinor }, 0, "\(description): nets must add up to zero", file: file, line: line)

        let outcome = Settlement.payments(for: entries)
        XCTAssertEqual(outcome.unbalancedMinor, 0, description, file: file, line: line)

        var paid: [String: Int] = [:]
        var received: [String: Int] = [:]
        for payment in outcome.payments {
            XCTAssertGreaterThan(payment.amountMinor, 0, "\(description): a payment of \(payment.amountMinor)", file: file, line: line)
            XCTAssertNotEqual(key(payment.fromID), key(payment.toID), "\(description): paying themselves", file: file, line: line)
            paid[key(payment.fromID), default: 0] += payment.amountMinor
            received[key(payment.toID), default: 0] += payment.amountMinor
        }
        for entry in entries {
            if entry.netMinor < 0 {
                XCTAssertEqual(paid[key(entry.id)] ?? 0, -entry.netMinor, "\(description): \(entry.name) owes \(-entry.netMinor)", file: file, line: line)
                XCTAssertNil(received[key(entry.id)], "\(description): a debtor shouldn't also receive", file: file, line: line)
            } else if entry.netMinor > 0 {
                XCTAssertEqual(received[key(entry.id)] ?? 0, entry.netMinor, "\(description): \(entry.name) is owed \(entry.netMinor)", file: file, line: line)
                XCTAssertNil(paid[key(entry.id)], "\(description): a creditor shouldn't also pay", file: file, line: line)
            } else {
                XCTAssertNil(paid[key(entry.id)], file: file, line: line)
                XCTAssertNil(received[key(entry.id)], file: file, line: line)
            }
        }

        let involved = entries.filter { $0.netMinor != 0 }.count
        XCTAssertLessThanOrEqual(outcome.payments.count, max(0, involved - 1), "\(description): too many payments", file: file, line: line)
    }

    func testABalancedNightAlwaysSettlesExactly() {
        var rng = SplitMix64(seed: 2_026_100_9)
        for index in 0..<1_000 {
            let night = randomNight(&rng, balanced: true)
            XCTAssertEqual(night.bankDeltaMinor, 0)
            assertSettlementIsSound(night, "balanced night #\(index)")
        }
    }

    func testAnUnbalancedNightSettlesExactlyOnceItsDifferenceIsResolved() {
        var rng = SplitMix64(seed: 77_001)
        var kindsSeen = Set<BankResolution.Kind>()
        for index in 0..<2_000 {
            let night = randomNight(&rng, balanced: false)
            XCTAssertNotEqual(night.bankDeltaMinor, 0)
            if let kind = night.resolution?.kind { kindsSeen.insert(kind) }
            assertSettlementIsSound(night, "unbalanced night #\(index) (\(night.resolution?.kind.rawValue ?? "none"))")
        }
        XCTAssertEqual(kindsSeen, [.tip, .assign, .split], "every way of resolving should have been exercised")
    }

    func testTheAnswerDoesNotDependOnTheOrderPlayersAreListedIn() {
        var rng = SplitMix64(seed: 5_150)
        for index in 0..<1_000 {
            let night = randomNight(&rng, balanced: true)
            guard let entries = night.settlementEntries() else { return XCTFail("night #\(index) should balance") }
            let expected = Settlement.payments(for: entries)
            var shuffler = SplitMix64(seed: UInt64(index) + 9)
            for _ in 0..<3 {
                let shuffled = entries.shuffled(using: &shuffler)
                XCTAssertEqual(Settlement.payments(for: shuffled), expected, "night #\(index) changed with input order")
            }
            XCTAssertEqual(Settlement.payments(for: entries), expected, "asking twice must give the same answer")
        }
    }

    func testEvenSharesAlwaysAddUpAndNeverDifferByMoreThanACent() {
        var rng = SplitMix64(seed: 31_337)
        for _ in 0..<2_000 {
            let amount = Int.random(in: -100_000...100_000, using: &rng)
            let count = Int.random(in: 1...12, using: &rng)
            let shares = GameNight.evenShares(of: amount, among: count)
            XCTAssertEqual(shares.count, count)
            XCTAssertEqual(shares.reduce(0, +), amount, "\(amount) among \(count): \(shares)")
            XCTAssertLessThanOrEqual((shares.max() ?? 0) - (shares.min() ?? 0), 1)
        }
        XCTAssertEqual(GameNight.evenShares(of: 100, among: 3), [34, 33, 33])
        XCTAssertEqual(GameNight.evenShares(of: -100, among: 3), [-34, -33, -33])
        XCTAssertEqual(GameNight.evenShares(of: 1, among: 5), [1, 0, 0, 0, 0])
        XCTAssertEqual(GameNight.evenShares(of: 0, among: 4), [0, 0, 0, 0])
        XCTAssertEqual(GameNight.evenShares(of: 10, among: 0), [])
    }

    func testANightSurvivesBeingSavedAndLoaded() throws {
        var rng = SplitMix64(seed: 404)
        for index in 0..<200 {
            let night = randomNight(&rng, balanced: index % 2 == 0)
            let data = try NightCoding.makeEncoder().encode(night)
            let restored = try NightCoding.makeDecoder().decode(GameNight.self, from: data)
            XCTAssertEqual(restored, night)
            XCTAssertEqual(try NightCoding.makeEncoder().encode(restored), data, "the same night must produce the same bytes")
        }
    }

    // MARK: A worked example

    func testASmallNightSettlesTheWayYouWouldByHand() {
        // Four players in for $50. Alex +$40, Jo +$20, Pat −$30, Sam −$30.
        var night = GameNight.start(now: t0, buyInMinor: 5_000, playerNames: ["Sam", "Alex", "Jo", "Pat"], colors: ["White"], denominationsMinor: ["White": 25])
        let cashOuts = ["Sam": 2_000, "Alex": 9_000, "Jo": 7_000, "Pat": 2_000]
        for player in night.players { night.cashOut(player.id, amountMinor: cashOuts[player.name] ?? 0, at: t0) }

        XCTAssertTrue(night.isBalanced)
        let payments = night.payments() ?? []
        XCTAssertEqual(
            Settlement.text(for: payments, locale: Locale(identifier: "en_US")),
            "Pat → Alex $30.00\nSam → Jo $20.00\nSam → Alex $10.00",
            "equal debts go to whoever sorts first; the biggest debtor meets the biggest creditor"
        )
        XCTAssertLessThanOrEqual(payments.count, 3)
    }

    func testNobodyOwesAnythingWhenEveryoneBreaksEven() {
        var night = GameNight.start(now: t0, buyInMinor: 2_000, playerNames: ["A", "B", "C"], colors: ["White"], denominationsMinor: ["White": 25])
        for player in night.players { night.cashOut(player.id, amountMinor: 2_000, at: t0) }
        XCTAssertEqual(night.payments(), [])
    }
}
