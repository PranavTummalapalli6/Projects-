//
//  StatsTests.swift
//  PokerChipAppTests
//
//  The figures on the Stats tab, checked against a fixture worked out by hand,
//  and the spreadsheet export, checked by writing it and reading it back.
//

import XCTest
@testable import PokerChipApp

private let la = TimeZone(identifier: "America/Los_Angeles") ?? .current

/// A local time in Los Angeles.
private func local(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 19, _ minute: Int = 0) -> Date {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = la
    return calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute)) ?? Date(timeIntervalSince1970: 0)
}

/// A closed two-person night — "Me" and "Alex" — in which my result is exactly
/// `net` cents. Alex takes the other side so the bank balances to the cent.
private func closedNight(
    on start: Date, place: String?, stake: Int, myIn: Int, net: Int, hours: Int,
    currency: String = "USD", notes: String? = nil
) -> GameNight {
    var night = GameNight.start(
        now: start, timeZone: la, currency: currency, buyInMinor: stake, playerNames: ["Me", "Alex"],
        colors: ["White"], denominationsMinor: ["White": 25], location: place
    )
    if myIn > stake { night.rebuy(night.players[0].id, amountMinor: myIn - stake, at: start) }
    let alexIn = max(stake, net)
    if alexIn > stake { night.rebuy(night.players[1].id, amountMinor: alexIn - stake, at: start) }
    night.cashOut(night.players[0].id, amountMinor: myIn + net, at: start)
    night.cashOut(night.players[1].id, amountMinor: alexIn - net, at: start)
    night.endPlay(at: start.addingTimeInterval(TimeInterval(hours * 3_600)))
    night.notes = notes
    night.settle(at: start.addingTimeInterval(TimeInterval(hours * 3_600 + 60)))
    XCTAssertTrue(night.isSettled, "a fixture night must be closed (a player can't lose more than they put in)")
    return night
}

/// Eight nights, every figure below worked out by hand:
///
///     #  date (Los Angeles)   place    stake   in      net      time
///     1  Sat 6 Jun   19:00    Pat's    $25     $25     +$30     3 h
///     2  Fri 19 Jun  20:00    Jo's     $25     $50     −$50     4 h
///     3  Sat 27 Jun  19:00    Pat's    $25     $25     −$10     2 h
///     4  Fri 10 Jul  19:00    Pat's    $50     $50     +$75     3 h
///     5  Sat 18 Jul  19:00    Jo's     $50     $100    $0       5 h
///     6  Sun 26 Jul  14:00    Pat's    $25     $25     +$15     2 h
///     7  Fri 7 Aug   19:00    pat's    $25     $25     +$20     3 h
///     8  Sat 15 Aug  19:00    —        $25     $25     −$20     1 h
private func fixture() -> [GameNight] {
    [
        closedNight(on: local(2026, 6, 6), place: "Pat's", stake: 2_500, myIn: 2_500, net: 3_000, hours: 3),
        closedNight(on: local(2026, 6, 19, 20), place: "Jo's", stake: 2_500, myIn: 5_000, net: -5_000, hours: 4),
        closedNight(on: local(2026, 6, 27), place: "Pat's", stake: 2_500, myIn: 2_500, net: -1_000, hours: 2),
        closedNight(on: local(2026, 7, 10), place: "Pat's", stake: 5_000, myIn: 5_000, net: 7_500, hours: 3),
        closedNight(on: local(2026, 7, 18), place: "Jo's", stake: 5_000, myIn: 10_000, net: 0, hours: 5),
        closedNight(on: local(2026, 7, 26, 14), place: "Pat's", stake: 2_500, myIn: 2_500, net: 1_500, hours: 2),
        closedNight(on: local(2026, 8, 7), place: "pat's", stake: 2_500, myIn: 2_500, net: 2_000, hours: 3),
        closedNight(on: local(2026, 8, 15), place: nil, stake: 2_500, myIn: 2_500, net: -2_000, hours: 1),
    ]
}

final class StatsEngineTests: XCTestCase {
    private let now = local(2026, 9, 1)

    func testTheFixtureNightsAreAllClosedAndBalanced() {
        for night in fixture() {
            XCTAssertTrue(night.isSettled)
            XCTAssertEqual(night.bankDeltaMinor, 0)
        }
    }

    func testTheHeadlineFigures() {
        let report = StatsEngine.report(for: fixture(), now: now)

        XCTAssertEqual(report.nights, 8)
        XCTAssertEqual(report.totalNetMinor, 6_000)                      // 30 − 50 − 10 + 75 + 0 + 15 + 20 − 20
        XCTAssertEqual(report.totalInMinor, 32_500)                      // 25 + 50 + 25 + 50 + 100 + 25 + 25 + 25
        XCTAssertEqual(report.totalSeconds, 23 * 3_600)                  // 3 + 4 + 2 + 3 + 5 + 2 + 3 + 1 hours
        XCTAssertEqual(report.wins, 4)
        XCTAssertEqual(report.losses, 3)
        XCTAssertEqual(report.breakEvens, 1)
        XCTAssertEqual(report.winRate, 0.5)
        XCTAssertEqual(report.averageBuyInMinor, 4_063)                  // 32,500 ÷ 8 = 4,062.5, rounded up
        XCTAssertEqual(report.currency, "USD")
        XCTAssertFalse(report.isEmpty)
    }

    func testTheBestAndWorstNights() {
        let report = StatsEngine.report(for: fixture(), now: now)
        XCTAssertEqual(report.best?.netMinor, 7_500)
        XCTAssertEqual(report.best?.location, "Pat's")
        XCTAssertEqual(report.worst?.netMinor, -5_000)
        XCTAssertEqual(report.worst?.location, "Jo's")
    }

    func testStreaks() {
        // Results in order: + − − + 0 + + −
        let report = StatsEngine.report(for: fixture(), now: now)
        XCTAssertEqual(report.longestWinStreak, 2)                       // nights 6 and 7
        XCTAssertEqual(report.longestLossStreak, 2)                      // nights 2 and 3
        XCTAssertEqual(report.currentStreak, -1)                         // night 8 lost, night 7 won
    }

    func testTheCurrentStreakCountsTheRunEndingAtTheLatestNight() {
        let nights = fixture().dropLast()                                // … + + : the run now ends on a win
        XCTAssertEqual(StatsEngine.report(for: Array(nights), now: now).currentStreak, 2)

        let evenLast = Array(fixture().dropLast()) + [closedNight(on: local(2026, 8, 15), place: nil, stake: 2_500, myIn: 2_500, net: 0, hours: 1)]
        XCTAssertEqual(StatsEngine.report(for: evenLast, now: now).currentStreak, 0, "a break-even night ends any run")
    }

    func testTheBankrollIsTheRunningTotalOfTheResults() {
        let report = StatsEngine.report(for: fixture(), now: now)
        XCTAssertEqual(report.bankroll.map(\.cumulativeMinor), [3_000, -2_000, -3_000, 4_500, 4_500, 6_000, 8_000, 6_000])
        XCTAssertEqual(report.bankroll.last?.cumulativeMinor, report.totalNetMinor)
        XCTAssertEqual(report.bankroll.map(\.date), report.bankroll.map(\.date).sorted(), "oldest first")
    }

    func testNetByMonthUsesTheMonthItWasPlayedIn() {
        let report = StatsEngine.report(for: fixture(), now: now)
        XCTAssertEqual(report.byMonth.map(\.id), [202_606, 202_607, 202_608])
        XCTAssertEqual(report.byMonth.map(\.netMinor), [-3_000, 9_000, 0])
        XCTAssertEqual(report.byMonth.map(\.nights), [3, 3, 2])
    }

    func testANightAfterMidnightUTCStillBelongsToTheMonthItWasPlayedIn() {
        // 23:30 on 31 July in Los Angeles is already 1 August in UTC.
        let late = closedNight(on: local(2026, 7, 31, 23, 30), place: nil, stake: 2_500, myIn: 2_500, net: 500, hours: 2)
        let report = StatsEngine.report(for: [late], now: now)
        XCTAssertEqual(report.byMonth.map(\.id), [202_607])
    }

    func testByPlaceMostProfitableFirstAndCaseDoesNotSplitAPlace() {
        let places = StatsEngine.report(for: fixture(), now: now).byLocation
        XCTAssertEqual(places.map(\.key), ["pat's", "jo's", ""])
        XCTAssertEqual(places.map(\.label), ["pat's", "Jo's", "No place recorded"], "the latest spelling, and nights with no place last")
        XCTAssertEqual(places.map(\.nights), [5, 2, 1])
        XCTAssertEqual(places.map(\.netMinor), [13_000, -5_000, -2_000])
        XCTAssertEqual(places.map(\.seconds), [13 * 3_600, 9 * 3_600, 3_600])
    }

    func testByWeekdayStartsOnMonday() {
        let days = StatsEngine.report(for: fixture(), now: now).byWeekday
        XCTAssertEqual(days.map(\.key), ["6", "7", "1"], "Friday, Saturday, Sunday (Calendar numbers: Sunday is 1)")
        XCTAssertEqual(days.map(\.nights), [3, 4, 1])
        XCTAssertEqual(days.map(\.netMinor), [4_500, 0, 1_500])
        XCTAssertEqual(days.map(\.seconds), [10 * 3_600, 11 * 3_600, 2 * 3_600])
    }

    func testByStakeSmallestFirst() {
        let stakes = StatsEngine.report(for: fixture(), now: now).byStake
        XCTAssertEqual(stakes.map(\.key), ["2500", "5000"])
        XCTAssertEqual(stakes.map(\.nights), [6, 2])
        XCTAssertEqual(stakes.map(\.netMinor), [-1_500, 7_500])
        XCTAssertEqual(stakes.map(\.seconds), [15 * 3_600, 8 * 3_600])
    }

    // MARK: Dollars per hour needs enough nights to mean something

    func testNoHourlyRateUntilTenNights() {
        let report = StatsEngine.report(for: fixture(), now: now)
        XCTAssertNil(report.perHourMinor)
        XCTAssertFalse(report.hasEnoughForPerHour)
    }

    func testTheHourlyRateIsTotalNetOverTotalTime() {
        let ten = fixture() + [
            closedNight(on: local(2026, 8, 22), place: "Pat's", stake: 2_500, myIn: 2_500, net: 1_000, hours: 2),
            closedNight(on: local(2026, 8, 30), place: "Pat's", stake: 2_500, myIn: 2_500, net: 1_000, hours: 2),
        ]
        let report = StatsEngine.report(for: ten, now: now)
        XCTAssertTrue(report.hasEnoughForPerHour)
        // +$80.00 over 27 hours = $2.963… an hour
        XCTAssertEqual(report.perHourMinor, 296)
    }

    // MARK: What does not count

    func testEmptyHistory() {
        let report = StatsEngine.report(for: [GameNight](), now: now)
        XCTAssertTrue(report.isEmpty)
        XCTAssertNil(report.winRate)
        XCTAssertNil(report.averageBuyInMinor)
        XCTAssertNil(report.best)
        XCTAssertEqual(report.currentStreak, 0)
        XCTAssertEqual(report.bankroll, [])
        XCTAssertEqual(report.byLocation, [])
    }

    func testOnlyClosedNightsTheyPlayedInCount() {
        var open = closedNight(on: local(2026, 8, 20), place: nil, stake: 2_500, myIn: 2_500, net: 900, hours: 1)
        open.reopen()                                                                              // not settled any more
        var deleted = closedNight(on: local(2026, 8, 21), place: nil, stake: 2_500, myIn: 2_500, net: 900, hours: 1)
        deleted.markDeleted(at: now)
        var watching = closedNight(on: local(2026, 8, 22), place: nil, stake: 2_500, myIn: 2_500, net: 900, hours: 1)
        watching.setMe(nil)                                                                        // they weren't playing

        let report = StatsEngine.report(for: fixture() + [open, deleted, watching], now: now)
        XCTAssertEqual(report.nights, 8)
        XCTAssertEqual(report.totalNetMinor, 6_000)
    }

    func testOnlyTheLatestNightsCurrencyIsAdded() {
        let euros = closedNight(on: local(2026, 5, 1), place: nil, stake: 2_000, myIn: 2_000, net: 800, hours: 2, currency: "EUR")
        let report = StatsEngine.report(for: [euros] + fixture(), now: now)
        XCTAssertEqual(report.currency, "USD")
        XCTAssertEqual(report.nights, 8, "earlier euro nights aren't mixed into dollar totals")
    }

    func testTiesForBestAndWorstGoToTheLaterNight() {
        let first = closedNight(on: local(2026, 8, 1), place: "A", stake: 2_500, myIn: 2_500, net: 1_000, hours: 1)
        let second = closedNight(on: local(2026, 8, 2), place: "B", stake: 2_500, myIn: 2_500, net: 1_000, hours: 1)
        let report = StatsEngine.report(for: [first, second], now: now)
        XCTAssertEqual(report.best?.location, "B")
        XCTAssertEqual(report.worst?.location, "B")
    }

    func testResultsAfterABankResolutionAreWhatCount() {
        // $50.00 in, $75.00 of chips cashed out: $25.00 too many. Split two ways,
        // each cash-out is cut by $12.50, so Me finishes +$50.00 − $12.50 = +$37.50.
        var night = GameNight.start(now: local(2026, 8, 3), timeZone: la, buyInMinor: 2_500, playerNames: ["Me", "Alex"], colors: ["White"], denominationsMinor: ["White": 25])
        night.cashOut(night.players[0].id, amountMinor: 7_500, at: night.startedAt)
        night.cashOut(night.players[1].id, amountMinor: 0, at: night.startedAt)
        night.endPlay(at: night.startedAt.addingTimeInterval(3_600))
        night.resolveBank(.split)
        night.settle(at: night.startedAt.addingTimeInterval(3_700))

        XCTAssertEqual(StatsEngine.report(for: [night], now: now).totalNetMinor, 3_750)
    }
}

// MARK: - Weeks of play

final class WeeklyTotalsTests: XCTestCase {
    private func night(_ start: Date, minutes: Int) -> GameNight {
        var night = GameNight.start(now: start, timeZone: la, buyInMinor: 2_500, playerNames: ["Me", "Alex"], colors: ["White"], denominationsMinor: ["White": 25])
        night.endPlay(at: start.addingTimeInterval(TimeInterval(minutes * 60)))
        return night
    }

    func testFourWeeksOfPlayOldestFirstEndingWithThisWeek() {
        let now = local(2026, 8, 31, 12)                       // Monday: this week is 25–31 August
        let nights = [
            night(local(2026, 8, 3), minutes: 60),             // the day before the first window starts: counts for nothing
            night(local(2026, 8, 12), minutes: 120),
            night(local(2026, 8, 20), minutes: 180),
            night(local(2026, 8, 26), minutes: 90),
            night(local(2026, 8, 30), minutes: 30),
        ]
        // Windows of seven local days ending on the 31st: Aug 4–10, 11–17, 18–24, 25–31.
        XCTAssertEqual(WeeklySummary.weeklyTotals(from: nights, weeks: 4, now: now, timeZone: la), [0, 120 * 60, 180 * 60, 120 * 60])
    }

    func testThisWeeksFigureIsTheSameOneThePokerHealthChipUses() {
        let now = local(2026, 8, 31, 12)
        let nights = [night(local(2026, 8, 29), minutes: 75), night(local(2026, 8, 20), minutes: 45)]
        let totals = WeeklySummary.weeklyTotals(from: nights, weeks: 4, now: now, timeZone: la)
        XCTAssertEqual(totals.last, WeeklySummary.make(from: nights, now: now, timeZone: la).totalSeconds)
    }
}

// MARK: - The spreadsheet export

final class CSVTests: XCTestCase {
    func testPlainAndAwkwardFields() {
        XCTAssertEqual(CSV.encode([["a", "b,c", "d\"e", "f\ng"]]), "a,\"b,c\",\"d\"\"e\",\"f\ng\"\r\n")
        XCTAssertEqual(CSV.encode([[" lead", "trail ", ""]]), "\" lead\",\"trail \",\r\n")
        XCTAssertEqual(CSV.encode([[""]]), "\"\"\r\n", "a lone empty field must not look like a blank line")
    }

    func testEitherKindOfLineEndingIsRead() {
        XCTAssertEqual(CSV.parse("a,b\r\nc,d\r\n"), [["a", "b"], ["c", "d"]])
        XCTAssertEqual(CSV.parse("a,b\nc,d"), [["a", "b"], ["c", "d"]])
        XCTAssertEqual(CSV.parse("a,\n,b\n"), [["a", ""], ["", "b"]])
        XCTAssertEqual(CSV.parse(""), [])
    }

    func testMalformedInputIsRefusedRatherThanGuessedAt() {
        XCTAssertNil(CSV.parse("\"never closed"))
        XCTAssertNil(CSV.parse("a\"b,c"))
        XCTAssertNil(CSV.parse("\"a\"b,c"))
    }

    func testAnyTableComesBackExactlyAsWritten() {
        var rng = SplitMix64(seed: 0xC5C5)
        let pieces = ["a", "Z", "0", " ", ",", "\"", "\n", "\r\n", "\r", "é", "😀", "=", "-5.00", "'", "\t", "日本"]
        for trial in 0..<500 {
            let rowCount = Int.random(in: 1...6, using: &rng)
            let columnCount = Int.random(in: 2...5, using: &rng)
            let table = (0..<rowCount).map { _ in
                (0..<columnCount).map { _ in
                    (0..<Int.random(in: 0...6, using: &rng)).map { _ in pieces.randomElement(using: &rng) ?? "" }.joined()
                }
            }
            XCTAssertEqual(CSV.parse(CSV.encode(table)), table, "trial \(trial): \(table)")
        }
    }
}

final class NightCSVTests: XCTestCase {
    private func nightsForExport() -> [GameNight] {
        // Closed and balanced, with a place and notes that need quoting in a CSV.
        var closed = GameNight.start(
            now: local(2026, 7, 31, 23, 30), timeZone: la, buyInMinor: 2_500, playerNames: ["Me", "Alex, \"Al\""],
            colors: ["White"], denominationsMinor: ["White": 25], location: "Pat's, upstairs"
        )
        closed.cashOut(closed.players[0].id, amountMinor: 4_500, at: closed.startedAt)
        closed.cashOut(closed.players[1].id, amountMinor: 500, at: closed.startedAt)       // $50.00 in, $50.00 out
        closed.endPlay(at: closed.startedAt.addingTimeInterval(7_200))
        closed.notes = "Rain delay\nsecond line, with a comma"
        closed.settle(at: closed.startedAt.addingTimeInterval(7_300))

        var open = GameNight.start(now: local(2026, 8, 5), timeZone: la, buyInMinor: 1_000, playerNames: ["Me", "Kim"], colors: ["White"], denominationsMinor: ["White": 25])
        open.cashOut(open.players[1].id, amountMinor: 1_250, at: open.startedAt)

        var short = GameNight.start(now: local(2026, 8, 6), timeZone: la, buyInMinor: 2_500, playerNames: ["Me", "Sam"], colors: ["White"], denominationsMinor: ["White": 25])
        short.cashOut(short.players[0].id, amountMinor: 4_800, at: short.startedAt)
        short.cashOut(short.players[1].id, amountMinor: 0, at: short.startedAt)             // $48.00 out of $50.00 in
        short.resolveBank(.tip)
        short.endPlay(at: short.startedAt.addingTimeInterval(3_600))
        short.settle(at: short.startedAt.addingTimeInterval(3_700))

        return [open, short, closed]                                                         // deliberately out of order
    }

    func testAmountsAreWrittenWithAPointWhateverThePhonesLanguage() {
        XCTAssertEqual(NightCSV.amount(2_500), "25.00")
        XCTAssertEqual(NightCSV.amount(-1_250), "-12.50")
        XCTAssertEqual(NightCSV.amount(5), "0.05")
        XCTAssertEqual(NightCSV.amount(-5), "-0.05")
        XCTAssertEqual(NightCSV.amount(0), "0.00")
        XCTAssertEqual(NightCSV.amount(123_456_789), "1234567.89")
    }

    func testOneRowPerPlayerOldestNightFirstWithAHouseRowForTips() {
        let rows = NightCSV.rows(for: nightsForExport())
        XCTAssertEqual(rows.map(\.player), ["Me", "Alex, \"Al\"", "Me", "Kim", "Me", "Sam", "(house)"])
        XCTAssertEqual(rows.map(\.localDate), ["2026-07-31", "2026-07-31", "2026-08-05", "2026-08-05", "2026-08-06", "2026-08-06", "2026-08-06"],
                       "the day it was played in Los Angeles, not the UTC date")
        XCTAssertEqual(rows[0].startedUTC, "2026-08-01T06:30:00.000Z")
        XCTAssertEqual(rows.map(\.isMe), [true, false, true, false, true, false, false])
    }

    func testMoneyColumnsAndWhatIsNotKnownYet() {
        let rows = NightCSV.rows(for: nightsForExport())
        // The closed night with an awkward place name.
        XCTAssertEqual(rows[0].totalIn, "25.00"); XCTAssertEqual(rows[0].cashOut, "45.00"); XCTAssertEqual(rows[0].result, "20.00")
        XCTAssertEqual(rows[1].totalIn, "25.00"); XCTAssertEqual(rows[1].cashOut, "5.00"); XCTAssertEqual(rows[1].result, "-20.00")
        // The night still open: Kim has cashed out, nobody's result is known.
        XCTAssertEqual(rows[2].cashOut, ""); XCTAssertEqual(rows[2].result, "")
        XCTAssertEqual(rows[3].cashOut, "12.50"); XCTAssertEqual(rows[3].result, "")
        // The shortfall recorded as tips: Me +$23.00, Sam −$25.00, house +$2.00 — adding up to nothing.
        XCTAssertEqual(rows[4].result, "23.00"); XCTAssertEqual(rows[5].result, "-25.00"); XCTAssertEqual(rows[6].result, "2.00")
    }

    func testEveryClosedNightsResultsAddUpToZero() {
        let rows = NightCSV.rows(for: nightsForExport())
        for night in Set(rows.map(\.nightID)) {
            let results = rows.filter { $0.nightID == night }.map(\.result)
            guard !results.contains("") else { continue }                                    // still open
            let cents = results.compactMap { Double($0) }.reduce(0) { $0 + Int(($1 * 100).rounded()) }
            XCTAssertEqual(cents, 0, night)
        }
    }

    func testWhatIsWrittenCanBeReadBackExactly() throws {
        let nights = nightsForExport()
        let text = NightCSV.text(for: nights)
        XCTAssertTrue(text.hasPrefix(NightCSV.columns.joined(separator: ",") + "\r\n"))

        let parsed = try XCTUnwrap(NightCSV.parse(text))
        XCTAssertEqual(parsed, NightCSV.rows(for: nights))
        XCTAssertEqual(parsed.first?.place, "Pat's, upstairs")
        XCTAssertEqual(parsed.first?.notes, "Rain delay\nsecond line, with a comma")
        XCTAssertEqual(parsed.first?.player, "Me")
    }

    func testAFileThatIsNotThisExportIsRefused() {
        XCTAssertNil(NightCSV.parse("name,amount\r\nSam,5\r\n"))
        XCTAssertNil(NightCSV.parse(NightCSV.columns.joined(separator: ",") + "\r\nonly,two\r\n"))
    }

    func testMyResultsInTheExportAddUpToTheStatsTotal() throws {
        let nights = fixture()
        let mine = NightCSV.rows(for: nights).filter(\.isMe)
        let cents = mine.compactMap { Double($0.result) }.reduce(0) { $0 + Int(($1 * 100).rounded()) }
        XCTAssertEqual(cents, StatsEngine.report(for: nights).totalNetMinor)
        XCTAssertEqual(mine.count, 8)
    }

    func testDeletedNightsAreNotExported() {
        var gone = closedNight(on: local(2026, 8, 1), place: nil, stake: 2_500, myIn: 2_500, net: 100, hours: 1)
        gone.markDeleted(at: gone.startedAt)
        XCTAssertEqual(NightCSV.rows(for: [gone]), [])
        XCTAssertEqual(NightCSV.text(for: [gone]), NightCSV.columns.joined(separator: ",") + "\r\n", "just the header")
    }

    func testTheFileIsNamedForTheDay() {
        XCTAssertEqual(NightCSV.fileName(now: local(2026, 10, 9, 12)), "chip-counter-nights-2026-10-09.csv")
    }
}

// MARK: - Finding a night

final class HistoryFilterTests: XCTestCase {
    private let english = Locale(identifier: "en_US")
    private let now = local(2026, 8, 20, 12)

    private func night(_ start: Date, place: String?, stake: Int = 2_500, names: [String] = ["Me", "Alex"], notes: String? = nil) -> GameNight {
        var night = GameNight.start(now: start, timeZone: la, buyInMinor: stake, playerNames: names, colors: ["White"], denominationsMinor: ["White": 25], location: place)
        night.notes = notes
        return night
    }

    private lazy var nights: [GameNight] = [
        night(local(2026, 8, 7), place: "Pat's garage", names: ["Me", "José", "Kim"], notes: "Rain delay"),     // this month
        night(local(2026, 7, 25), place: "Jo's", stake: 5_000, names: ["Me", "Sam"]),                          // within 30 days, last month
        night(local(2026, 5, 2), place: "pat's garage", names: ["Me", "Alex"]),                                // this year
        night(local(2025, 12, 12), place: nil, stake: 1_000, names: ["Me", "Robin"], notes: "First night"),    // last year
    ]

    private func found(_ filter: HistoryFilter) -> [Int] {
        let all = filter.apply(to: nights, now: now, calendar: Calendar(identifier: .gregorian).withZone(la), locale: english)
        return all.compactMap { match in nights.firstIndex { $0.id == match.id } }
    }

    func testNoFilterShowsEverythingInTheOrderGiven() {
        XCTAssertEqual(found(HistoryFilter()), [0, 1, 2, 3])
        XCTAssertFalse(HistoryFilter().isActive)
    }

    func testSearchLooksAtPlacePeopleNotesAndTheDate() {
        XCTAssertEqual(found(HistoryFilter(query: "garage")), [0, 2], "the place, whatever its capitalisation")
        XCTAssertEqual(found(HistoryFilter(query: "robin")), [3], "a player")
        XCTAssertEqual(found(HistoryFilter(query: "rain")), [0], "the notes")
        XCTAssertEqual(found(HistoryFilter(query: "august")), [0], "the month, as it reads")
        XCTAssertEqual(found(HistoryFilter(query: "friday")), [0, 3], "the weekday: 7 Aug 2026 and 12 Dec 2025 were Fridays")
        XCTAssertEqual(found(HistoryFilter(query: "2025")), [3])
    }

    func testSearchIgnoresAccentsAndCase() {
        XCTAssertEqual(found(HistoryFilter(query: "JOSE")), [0])
        XCTAssertEqual(found(HistoryFilter(query: "josé")), [0])
    }

    func testEveryWordMustMatchSomething() {
        XCTAssertEqual(found(HistoryFilter(query: "pat's kim")), [0], "Pat's garage and Kim: only the first night")
        XCTAssertEqual(found(HistoryFilter(query: "  garage   rain  ")), [0])
        XCTAssertEqual(found(HistoryFilter(query: "garage zebra")), [])
    }

    func testDateRanges() {
        XCTAssertEqual(found(HistoryFilter(range: .thisMonth)), [0])
        XCTAssertEqual(found(HistoryFilter(range: .last30Days)), [0, 1], "since 21 July")
        XCTAssertEqual(found(HistoryFilter(range: .thisYear)), [0, 1, 2])
        XCTAssertEqual(found(HistoryFilter(range: .all)), [0, 1, 2, 3])
    }

    func testPlaceAndStakeFiltersCombineWithSearch() {
        XCTAssertEqual(found(HistoryFilter(place: "PAT'S GARAGE")), [0, 2], "a place, any capitalisation")
        XCTAssertEqual(found(HistoryFilter(stakeMinor: 5_000)), [1])
        XCTAssertEqual(found(HistoryFilter(range: .thisYear, place: "pat's garage")), [0, 2])
        XCTAssertEqual(found(HistoryFilter(query: "alex", place: "pat's garage")), [2])
        XCTAssertTrue(HistoryFilter(place: "Jo's").hasFilters)
    }

    func testClearingPutsEverythingBack() {
        var filter = HistoryFilter(query: "x", range: .thisYear, place: "Jo's", stakeMinor: 5_000)
        XCTAssertTrue(filter.isActive)
        filter.clear()
        XCTAssertEqual(filter, HistoryFilter())
    }

    func testTheFilterChoicesComeFromTheNightsThemselves() {
        XCTAssertEqual(HistoryFilter.places(in: nights), ["Pat's garage", "Jo's"], "most recent first, one spelling each")
        XCTAssertEqual(HistoryFilter.stakes(in: nights), [1_000, 2_500, 5_000])
    }
}

final class HistorySectionsTests: XCTestCase {
    private func settled(_ start: Date, net: Int) -> GameNight {
        closedNight(on: start, place: nil, stake: 2_500, myIn: 2_500, net: net, hours: 2)
    }

    func testNewestMonthFirstWithAMonthlyNetForClosedNights() {
        let nights = [
            settled(local(2026, 6, 6), net: 3_000),
            settled(local(2026, 8, 7), net: 2_000),
            settled(local(2026, 6, 19), net: -1_000),
            GameNight.start(now: local(2026, 8, 20), timeZone: la, buyInMinor: 2_500, playerNames: ["Me", "Alex"], colors: ["White"], denominationsMinor: ["White": 25]),
        ]
        let sections = HistorySections.group(nights, calendar: Calendar(identifier: .gregorian).withZone(la))
        XCTAssertEqual(sections.count, 2)
        XCTAssertEqual(sections[0].nights.count, 2, "August: the closed one and the one still open")
        XCTAssertEqual(sections[0].netMinor, 2_000, "only closed nights are added up")
        XCTAssertEqual(sections[1].nights.map(\.startedAt), [local(2026, 6, 19), local(2026, 6, 6)], "newest first")
        XCTAssertEqual(sections[1].netMinor, 2_000)
        XCTAssertGreaterThan(sections[0].monthStart, sections[1].monthStart)
    }

    func testAMonthWithNothingClosedHasNoNet() {
        let open = GameNight.start(now: local(2026, 8, 20), timeZone: la, buyInMinor: 2_500, playerNames: ["Me", "Alex"], colors: ["White"], denominationsMinor: ["White": 25])
        XCTAssertNil(HistorySections.group([open], calendar: Calendar(identifier: .gregorian).withZone(la)).first?.netMinor)
    }

    func testANightLateOnTheLastDayStaysInItsMonth() {
        let late = settled(local(2026, 7, 31, 23, 30), net: 100)      // already August in UTC
        let sections = HistorySections.group([late], calendar: Calendar(identifier: .gregorian).withZone(la))
        XCTAssertEqual(sections.count, 1)
        XCTAssertEqual(Calendar(identifier: .gregorian).withZone(la).component(.month, from: sections[0].monthStart), 7)
    }
}

private extension Calendar {
    func withZone(_ zone: TimeZone) -> Calendar {
        var copy = self
        copy.timeZone = zone
        return copy
    }
}

// MARK: - This week against last

final class WeekTrendTests: XCTestCase {
    func testTheComparisonIsPlainAndNeverAScolding() {
        XCTAssertEqual(WeekTrend(weeks: [0, 0, 0, 0]).comparison, "No games this week or last.")
        XCTAssertEqual(WeekTrend(weeks: [0, 0, 0, 3_600]).comparison, "Nothing played last week.")
        XCTAssertEqual(WeekTrend(weeks: [0, 0, 7_200, 7_200]).comparison, "The same as last week.")
        XCTAssertEqual(WeekTrend(weeks: [0, 0, 7_200, 12_000]).comparison, "1h 20m more than last week.")
        XCTAssertEqual(WeekTrend(weeks: [0, 0, 12_000, 7_200]).comparison, "1h 20m less than last week.")
        XCTAssertEqual(WeekTrend(weeks: [0, 0, 7_200, 0]).comparison, "2h 0m less than last week.")
    }

    func testTheSpokenFormAvoidsAbbreviations() {
        XCTAssertTrue(WeekTrend(weeks: [0, 0, 7_200, 12_000]).spokenComparison.contains("hour"))
        XCTAssertFalse(WeekTrend(weeks: [0, 0, 7_200, 12_000]).spokenComparison.contains("1h"))
    }

    func testTheFourBarsAreNamedOldestFirst() {
        XCTAssertEqual(WeekTrend.labels, ["3 weeks ago", "2 weeks ago", "Last week", "This week"])
        XCTAssertEqual(WeekTrend(weeks: [1, 2, 3, 4]).thisWeek, 4)
        XCTAssertEqual(WeekTrend(weeks: [1, 2, 3, 4]).lastWeek, 3)
        XCTAssertTrue(WeekTrend(weeks: [0, 0, 0, 5]).hasAnyPlay)
        XCTAssertFalse(WeekTrend(weeks: [0, 0, 0, 0]).hasAnyPlay)
    }

    func testItIsWorkedOutFromTheNightsOnThePhone() {
        let now = local(2026, 8, 31, 12)
        func night(_ start: Date, minutes: Int) -> GameNight {
            var night = GameNight.start(now: start, timeZone: la, buyInMinor: 2_500, playerNames: ["Me", "Alex"], colors: ["White"], denominationsMinor: ["White": 25])
            night.endPlay(at: start.addingTimeInterval(TimeInterval(minutes * 60)))
            return night
        }
        let trend = WeekTrend(nights: [night(local(2026, 8, 20), minutes: 180), night(local(2026, 8, 27), minutes: 120)], now: now, timeZone: la)
        XCTAssertEqual(trend.weeks, [0, 0, 180 * 60, 120 * 60])
        XCTAssertEqual(trend.comparison, "1h 0m less than last week.")
    }
}

// MARK: - Healthy play

final class HealthyPlayTests: XCTestCase {
    private let now = local(2026, 8, 20, 23, 30)

    /// Seven evenings in the last seven days, `hours` long each, my result `net` each.
    private func week(hours: Int, net: Int = 0) -> [GameNight] {
        (14...20).map { day in
            closedNight(on: local(2026, 8, day), place: nil, stake: 2_500, myIn: 2_500, net: net, hours: hours)
        }
    }

    // MARK: Time

    func testNothingIsSaidAboutALightWeek() {
        XCTAssertNil(HealthyPlay.nudge(nights: week(hours: 1), limits: PlayLimits(), now: now, timeZone: la))
        XCTAssertNil(HealthyPlay.nudge(nights: [], limits: PlayLimits(), now: now, timeZone: la))
    }

    func testAWordWhenTheWeekIsPastTheTimeLimitTheyChose() throws {
        let nudge = try XCTUnwrap(HealthyPlay.nudge(nights: week(hours: 3), limits: PlayLimits(weeklyHours: 20), now: now, timeZone: la))   // 21 hours
        XCTAssertEqual(nudge.reason, .time)
        XCTAssertTrue(nudge.message.contains("21h 0m"))
        XCTAssertTrue(nudge.message.contains("20-hour limit you set"))
        XCTAssertFalse(nudge.message.localizedCaseInsensitiveContains("addict"))
        XCTAssertFalse(nudge.message.contains("!"), "no shouting")
    }

    func testAHeadsUpWhenTheyAreCloseToTheLimit() throws {
        let nudge = try XCTUnwrap(HealthyPlay.nudge(nights: week(hours: 3), limits: PlayLimits(weeklyHours: 25), now: now, timeZone: la))   // 21 of 25
        XCTAssertTrue(nudge.message.contains("close to the 25-hour limit"))
        XCTAssertNil(HealthyPlay.nudge(nights: week(hours: 3), limits: PlayLimits(weeklyHours: 30), now: now, timeZone: la), "21 of 30 is well inside it")
    }

    // MARK: Money

    func testAWordWhenTheWeeksLossPassesTheLimitTheyChose() throws {
        let limits = PlayLimits(weeklyHours: 100, weeklyLoss: 100)
        let nights = [
            closedNight(on: local(2026, 8, 16), place: nil, stake: 2_500, myIn: 7_500, net: -6_000, hours: 2),
            closedNight(on: local(2026, 8, 19), place: nil, stake: 2_500, myIn: 7_500, net: -5_000, hours: 2),
        ]
        XCTAssertEqual(HealthyPlay.weeklyNetMinor(nights: nights, now: now, timeZone: la), -11_000)
        let nudge = try XCTUnwrap(HealthyPlay.nudge(nights: nights, limits: limits, now: now, timeZone: la))
        XCTAssertEqual(nudge.reason, .loss)
        XCTAssertTrue(nudge.message.contains("$110.00") && nudge.message.contains("$100.00"))
    }

    func testAWinningNightAgainstALossCancelsItOut() {
        let limits = PlayLimits(weeklyHours: 100, weeklyLoss: 100)
        let nights = [
            closedNight(on: local(2026, 8, 16), place: nil, stake: 2_500, myIn: 7_500, net: -6_000, hours: 2),
            closedNight(on: local(2026, 8, 18), place: nil, stake: 2_500, myIn: 2_500, net: 4_000, hours: 2),
            closedNight(on: local(2026, 8, 19), place: nil, stake: 2_500, myIn: 7_500, net: -5_000, hours: 2),
        ]
        XCTAssertNil(HealthyPlay.nudge(nights: nights, limits: limits, now: now, timeZone: la), "down $70 of a $100 limit")
    }

    func testNoLossLimitMeansNoWordAboutLosses() {
        let nights = [closedNight(on: local(2026, 8, 19), place: nil, stake: 2_500, myIn: 52_500, net: -50_000, hours: 2)]
        XCTAssertNil(HealthyPlay.nudge(nights: nights, limits: PlayLimits(weeklyHours: 100, weeklyLoss: nil), now: now, timeZone: la))
    }

    func testOnlyTheLastSevenDaysAndOnlyClosedNightsCountTowardsTheWeeksResult() {
        let old = closedNight(on: local(2026, 8, 10), place: nil, stake: 2_500, myIn: 12_500, net: -9_000, hours: 2)
        var open = closedNight(on: local(2026, 8, 19), place: nil, stake: 2_500, myIn: 12_500, net: -9_000, hours: 2)
        open.reopen()
        XCTAssertEqual(HealthyPlay.weeklyNetMinor(nights: [old, open], now: now, timeZone: la), 0)
    }

    // MARK: Once is enough

    func testADismissedWordStaysDismissedForTheRestOfTheWeek() throws {
        let heavy = week(hours: 3)
        let first = try XCTUnwrap(HealthyPlay.nudge(nights: heavy, limits: PlayLimits(), now: now, timeZone: la))
        XCTAssertFalse(first.isHidden(byDismissed: ""), "nothing dismissed yet")
        XCTAssertTrue(first.isHidden(byDismissed: first.id))

        // An hour later the window has moved and the same week reads milder: still hidden, not a second word.
        let later = try XCTUnwrap(HealthyPlay.nudge(nights: heavy, limits: PlayLimits(), now: now.addingTimeInterval(3_600), timeZone: la))
        XCTAssertLessThan(later.level, first.level)
        XCTAssertTrue(later.isHidden(byDismissed: first.id))
    }

    func testAMilderWordDismissedDoesNotHideAStrongerOneOrALaterWeeksWord() throws {
        let close = try XCTUnwrap(HealthyPlay.nudge(nights: week(hours: 3), limits: PlayLimits(weeklyHours: 25), now: now, timeZone: la))
        XCTAssertEqual(close.level, 1)
        let past = try XCTUnwrap(HealthyPlay.nudge(nights: week(hours: 3), limits: PlayLimits(weeklyHours: 20), now: now, timeZone: la))
        XCTAssertEqual(past.level, 2)
        XCTAssertFalse(past.isHidden(byDismissed: close.id), "going past the limit after being told you were close is worth saying")

        let nextWeek = local(2026, 8, 27, 12)
        let more = (21...27).map { closedNight(on: local(2026, 8, $0), place: nil, stake: 2_500, myIn: 2_500, net: 0, hours: 3) }
        let next = try XCTUnwrap(HealthyPlay.nudge(nights: more, limits: PlayLimits(), now: nextWeek, timeZone: la))
        XCTAssertNotEqual(past.week, next.week)
        XCTAssertFalse(next.isHidden(byDismissed: past.id), "a new week starts clean")
        XCTAssertFalse(past.isHidden(byDismissed: "garbage"))
        XCTAssertFalse(past.isHidden(byDismissed: "\(past.week)|loss|2"), "a loss word doesn't hide a time word")
    }

    // MARK: A break they chose

    func testABreakRunsItsCourseAndThenEnds() {
        let end = HealthyPlay.coolOffEnd(for: .threeDays, from: now)
        XCTAssertEqual(end.timeIntervalSince(now), 3 * 86_400)
        let limits = PlayLimits(coolOffUntil: end)
        XCTAssertTrue(HealthyPlay.isCoolingOff(limits, now: now))
        XCTAssertTrue(HealthyPlay.isCoolingOff(limits, now: end.addingTimeInterval(-1)))
        XCTAssertFalse(HealthyPlay.isCoolingOff(limits, now: end))
        XCTAssertFalse(HealthyPlay.isCoolingOff(PlayLimits(), now: now))
        XCTAssertEqual(HealthyPlay.Break.allCases.map(\.title), ["24 hours", "3 days", "7 days"])
    }

    // MARK: A reminder during a long night

    private func liveNight(startedMinutesAgo: Int) -> GameNight {
        GameNight.start(now: now.addingTimeInterval(TimeInterval(-startedMinutesAgo * 60)), timeZone: la, buyInMinor: 2_500, playerNames: ["Me", "Alex"], colors: ["White"], denominationsMinor: ["White": 25])
    }

    func testTheReminderIsDueHoursOfPlayIntoTheNight() {
        XCTAssertEqual(HealthyPlay.reminderPlan(for: liveNight(startedMinutesAgo: 30), hours: 2, now: now), .schedule(after: 5_400))
        XCTAssertEqual(HealthyPlay.reminderPlan(for: liveNight(startedMinutesAgo: 0), hours: 3, now: now), .schedule(after: 10_800))
    }

    func testThereIsNoNaggingAfterTheMarkOrWhenItIsOff() {
        XCTAssertEqual(HealthyPlay.reminderPlan(for: liveNight(startedMinutesAgo: 121), hours: 2, now: now), .cancel)
        XCTAssertEqual(HealthyPlay.reminderPlan(for: liveNight(startedMinutesAgo: 10), hours: nil, now: now), .cancel)
        XCTAssertEqual(HealthyPlay.reminderPlan(for: liveNight(startedMinutesAgo: 10), hours: 0, now: now), .cancel)
        XCTAssertEqual(HealthyPlay.reminderPlan(for: nil, hours: 2, now: now), .cancel)
    }

    func testANightThatIsOverOrOnABreakGetsNoReminder() {
        var over = liveNight(startedMinutesAgo: 30)
        over.endPlay(at: now)
        XCTAssertEqual(HealthyPlay.reminderPlan(for: over, hours: 2, now: now), .cancel)

        var paused = liveNight(startedMinutesAgo: 30)
        paused.pause(at: now)
        XCTAssertEqual(HealthyPlay.reminderPlan(for: paused, hours: 2, now: now), .cancel)
    }

    func testTimeOnABreakDoesNotBringTheReminderForward() {
        var night = liveNight(startedMinutesAgo: 120)
        night.pause(at: now.addingTimeInterval(-3_600))
        night.resumeFromPause(at: now.addingTimeInterval(-1_800))        // 30 minutes on a break: 90 minutes of play
        XCTAssertEqual(HealthyPlay.reminderPlan(for: night, hours: 2, now: now), .schedule(after: 1_800))
    }

    func testTheReminderIsKindAndSpecific() {
        XCTAssertEqual(HealthyPlay.reminderBody(hours: 3), "You've been playing for about 3 hours. Everything is saved — step away for a few minutes if you like.")
        XCTAssertTrue(HealthyPlay.reminderBody(hours: 1).contains("1 hour."))
        XCTAssertTrue(HealthyPlay.reminderBody(hours: 2.5).contains("2.5 hours"))
    }

    // MARK: Settings

    func testLimitsAreReadFromTheSettingsKeys() {
        let suite = "tests.limits.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suite) else { return XCTFail("no defaults suite") }
        defer { defaults.removePersistentDomain(forName: suite) }

        XCTAssertEqual(PlayLimits.stored(defaults: defaults), PlayLimits(), "nothing set: 20 hours, no other limits")

        defaults.set(12.0, forKey: PrefKey.weeklyHoursCap)
        defaults.set(150.0, forKey: PrefKey.weeklyLossLimit)
        defaults.set(3.0, forKey: PrefKey.sessionReminderHours)
        defaults.set(1_800_000_000.0, forKey: PrefKey.coolOffUntil)
        XCTAssertEqual(
            PlayLimits.stored(defaults: defaults),
            PlayLimits(weeklyHours: 12, weeklyLoss: 150, reminderHours: 3, coolOffUntil: Date(timeIntervalSince1970: 1_800_000_000))
        )
    }
}

final class HelplineDirectoryTests: XCTestCase {
    func testTheUSLineIsTheOneTheNationalCouncilAdoptedInJanuary2026() throws {
        let us = try XCTUnwrap(HelplineDirectory.helplines(for: "US").first)
        XCTAssertEqual(us.phoneDigits, "18006973738", "1-800-MY-RESET")
        XCTAssertTrue(us.phoneDisplay?.contains("1-800-MY-RESET") == true)
        XCTAssertEqual(us.callURL?.absoluteString, "tel:18006973738")
        XCTAssertEqual(us.textURL?.absoluteString, "sms:18006973738")
        XCTAssertEqual(us.websiteURL?.absoluteString, "https://1800myreset.org")
        XCTAssertFalse(HelplineDirectory.helplines(for: "US").contains { ($0.phoneDisplay ?? "").contains("GAMBLER") }, "the old 1-800-GAMBLER number is no longer the national line")
    }

    func testOtherCountriesGetTheirOwnLines() throws {
        XCTAssertEqual(HelplineDirectory.helplines(for: "GB").first?.phoneDigits, "08088020133")
        XCTAssertEqual(HelplineDirectory.helplines(for: "AU").first?.phoneDigits, "1800858858")
        let canada = HelplineDirectory.helplines(for: "CA")
        XCTAssertNil(canada.first?.phoneDigits, "Canada has no single national line, so none is invented")
        XCTAssertTrue(canada.contains { $0.id == "world" })
    }

    func testAnyOtherPlaceGetsTheInternationalDirectoryAndRegionsAreCaseInsensitive() {
        XCTAssertEqual(HelplineDirectory.helplines(for: "NZ").map(\.id), ["world"])
        XCTAssertEqual(HelplineDirectory.helplines(for: nil).map(\.id), ["world"])
        XCTAssertEqual(HelplineDirectory.helplines(for: "us").map(\.id), ["us"])
    }

    func testEveryEntryIsUsable() {
        for region in ["US", "GB", "AU", "CA", "FR", nil] {
            for line in HelplineDirectory.helplines(for: region) {
                XCTAssertEqual(line.websiteURL?.scheme, "https", line.id)
                XCTAssertFalse(line.name.isEmpty)
                XCTAssertFalse(line.detail.isEmpty)
                if line.phoneDigits != nil { XCTAssertNotNil(line.callURL, line.id); XCTAssertNotNil(line.phoneDisplay, line.id) }
                XCTAssertTrue(line.phoneDigits?.allSatisfy(\.isNumber) ?? true, line.id)
            }
        }
        XCTAssertFalse(HelplineDirectory.verifiedOn.isEmpty)
    }
}

// MARK: - Scheduling the reminder

@MainActor
final class SessionRemindersTests: XCTestCase {
    private final class FakeCenter: ReminderCenter {
        var allowed = true
        private(set) var scheduled: [(id: String, body: String, after: TimeInterval)] = []
        private(set) var cancelled: [String] = []
        private(set) var asked = 0

        func requestAuthorization() async -> Bool { asked += 1; return allowed }
        func isAuthorized() async -> Bool { allowed }
        func schedule(id: String, title: String, body: String, after seconds: TimeInterval) async { scheduled.append((id, body, seconds)) }
        func cancel(id: String) { cancelled.append(id) }
    }

    private let now = Date(timeIntervalSince1970: 1_786_042_800)

    private func night(startedMinutesAgo: Int) -> GameNight {
        GameNight.start(now: now.addingTimeInterval(TimeInterval(-startedMinutesAgo * 60)), buyInMinor: 2_500, playerNames: ["Me", "Alex"], colors: ["White"], denominationsMinor: ["White": 25])
    }

    func testALiveNightGetsOneReminderAtTheRightTime() async {
        let center = FakeCenter()
        await SessionReminders(center: center).update(night: night(startedMinutesAgo: 20), hours: 2, now: now)
        XCTAssertEqual(center.scheduled.count, 1)
        XCTAssertEqual(center.scheduled.first?.id, SessionReminders.identifier)
        XCTAssertEqual(center.scheduled.first?.after, 6_000)
        XCTAssertTrue(center.scheduled.first?.body.contains("2 hours") == true)
    }

    func testTurningItOffOrEndingTheNightTakesItBack() async {
        let center = FakeCenter()
        let reminders = SessionReminders(center: center)
        await reminders.update(night: night(startedMinutesAgo: 20), hours: nil, now: now)
        var over = night(startedMinutesAgo: 20)
        over.endPlay(at: now)
        await reminders.update(night: over, hours: 2, now: now)
        await reminders.update(night: nil, hours: 2, now: now)
        XCTAssertEqual(center.cancelled, [SessionReminders.identifier, SessionReminders.identifier, SessionReminders.identifier])
        XCTAssertTrue(center.scheduled.isEmpty)
    }

    func testNothingIsScheduledWithoutPermission() async {
        let center = FakeCenter()
        center.allowed = false
        await SessionReminders(center: center).update(night: night(startedMinutesAgo: 20), hours: 2, now: now)
        XCTAssertTrue(center.scheduled.isEmpty)
        XCTAssertEqual(center.cancelled, [SessionReminders.identifier], "and any earlier one is cleared")
    }

    func testPermissionIsAskedForOnlyWhenTheyTurnTheReminderOn() async {
        let center = FakeCenter()
        let reminders = SessionReminders(center: center)
        await reminders.update(night: night(startedMinutesAgo: 20), hours: nil, now: now)
        XCTAssertEqual(center.asked, 0, "an update never asks")
        let granted = await reminders.requestPermission()
        XCTAssertTrue(granted)
        XCTAssertEqual(center.asked, 1)
    }
}
