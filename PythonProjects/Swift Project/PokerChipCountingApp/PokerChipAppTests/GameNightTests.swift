//
//  GameNightTests.swift
//  PokerChipAppTests
//
//  The ledger rules: who's in for what, rebuys as events that can be undone,
//  cashing out, the bank check and how a mismatch is resolved, closing the
//  night, and the playtime (with pauses, in the right time zone).
//

import XCTest
@testable import PokerChipApp

private let t0 = Date(timeIntervalSince1970: 1_800_000_000)

private func sampleNight(_ names: [String] = ["Sam", "Alex", "Jo"], buyIn: Int = 2_500) -> GameNight {
    GameNight.start(
        now: t0, buyInMinor: buyIn, playerNames: names,
        colors: ["White", "Red"], denominationsMinor: ["White": 25, "Red": 100]
    )
}

/// Sam +$25.00, Alex −$10.00, Jo −$17.00 — and $2.00 of chips missing from the bank.
private func shortNight() -> GameNight {
    var night = sampleNight()
    night.cashOut(night.players[0].id, amountMinor: 5_000, at: t0)
    night.cashOut(night.players[1].id, amountMinor: 1_500, at: t0)
    night.cashOut(night.players[2].id, amountMinor: 800, at: t0)
    return night
}

final class GameNightTests: XCTestCase {

    // MARK: Starting

    func testEveryoneStartsInForTheBuyIn() {
        let night = sampleNight()
        XCTAssertEqual(night.players.map(\.name), ["Sam", "Alex", "Jo"])
        XCTAssertEqual(night.players.map(\.totalInMinor), [2_500, 2_500, 2_500])
        XCTAssertEqual(night.totalInMinor, 7_500)
        XCTAssertTrue(night.isLive)
        XCTAssertFalse(night.isSettled)
    }

    func testNamesAreTidiedAndBlanksBecomeNumberedPlayers() {
        let night = sampleNight(["  Sam  ", "", "   ", String(repeating: "x", count: 80)])
        XCTAssertEqual(night.players[0].name, "Sam")
        XCTAssertEqual(night.players[1].name, "Player 2")
        XCTAssertEqual(night.players[2].name, "Player 3")
        XCTAssertEqual(night.players[3].name.count, 40)
    }

    func testAnOldNightMissingNewerFieldsStillOpens() throws {
        let json = """
        {"id": "11111111-2222-3333-4444-555555555555", "startedAt": "2026-08-06T19:00:00Z",
         "players": [{"id": "AAAAAAAA-2222-3333-4444-555555555555", "name": "Sam",
                      "buyIns": [{"id": "BBBBBBBB-2222-3333-4444-555555555555", "amountMinor": 2500, "at": "2026-08-06T19:00:00Z"}]}]}
        """
        let night = try NightCoding.makeDecoder().decode(GameNight.self, from: Data(json.utf8))
        XCTAssertEqual(night.pauses, [])
        XCTAssertEqual(night.currency, "USD")
        XCTAssertEqual(night.schemaVersion, GameNight.currentSchemaVersion)
        XCTAssertEqual(night.updatedAt, night.startedAt)
        XCTAssertEqual(night.players.first?.totalInMinor, 2_500)
    }

    // MARK: Rebuys

    func testARebuyIsItsOwnEventAndCanBeUndone() throws {
        var night = sampleNight()
        let sam = night.players[0].id
        let event = try XCTUnwrap(night.rebuy(sam, at: t0.addingTimeInterval(600)))

        XCTAssertEqual(night.players[0].totalInMinor, 5_000)
        XCTAssertEqual(night.players[0].rebuyCount, 1)
        XCTAssertEqual(night.totalInMinor, 10_000)

        XCTAssertTrue(night.undoBuyIn(playerID: sam, eventID: event.id))
        XCTAssertEqual(night.players[0].totalInMinor, 2_500)
        XCTAssertEqual(night.players[0].rebuyCount, 0)
    }

    func testAPlayerAlwaysKeepsTheirFirstBuyIn() {
        var night = sampleNight()
        let sam = night.players[0]
        XCTAssertFalse(night.undoBuyIn(playerID: sam.id, eventID: sam.buyIns[0].id))
        XCTAssertEqual(night.players[0].totalInMinor, 2_500)
    }

    func testARebuyCanBeADifferentAmountButNotZero() {
        var night = sampleNight()
        let sam = night.players[0].id
        XCTAssertNotNil(night.rebuy(sam, amountMinor: 1_000))
        XCTAssertNil(night.rebuy(sam, amountMinor: 0))
        XCTAssertNil(night.rebuy(sam, amountMinor: -500))
        XCTAssertEqual(night.players[0].totalInMinor, 3_500)
    }

    func testNobodyCanRebuyAfterCashingOut() {
        var night = sampleNight()
        let sam = night.players[0].id
        night.cashOut(sam, amountMinor: 1_000, at: t0)
        XCTAssertNil(night.rebuy(sam))
        XCTAssertEqual(night.players[0].totalInMinor, 2_500)
    }

    // MARK: Players

    func testALatePlayerJoinsInForTheDefaultBuyIn() {
        var night = sampleNight()
        let late = night.addPlayer(name: "Kim", at: t0.addingTimeInterval(3_600))
        XCTAssertEqual(night.players.count, 4)
        XCTAssertEqual(late.totalInMinor, 2_500)
        XCTAssertEqual(night.totalInMinor, 10_000)
    }

    func testOnlyAPlayerWhoHasNotCashedOutCanBeRemoved() {
        var night = sampleNight()
        let sam = night.players[0].id, alex = night.players[1].id
        night.cashOut(alex, amountMinor: 0, at: t0)
        XCTAssertFalse(night.removePlayer(alex), "cashed-out money must not vanish")
        XCTAssertTrue(night.removePlayer(sam))
        XCTAssertEqual(night.players.map(\.name), ["Alex", "Jo"])
    }

    func testRenaming() {
        var night = sampleNight()
        night.renamePlayer(night.players[0].id, to: "  Samuel ")
        night.renamePlayer(night.players[1].id, to: "")
        XCTAssertEqual(night.players[0].name, "Samuel")
        XCTAssertEqual(night.players[1].name, "Player 2")
    }

    func testTheRunningBoardPutsTheBiggestStackInFirst() {
        var night = sampleNight(["Sam", "Alex", "Jo"])
        night.rebuy(night.players[2].id)
        night.rebuy(night.players[2].id)
        night.rebuy(night.players[0].id)
        XCTAssertEqual(night.playersByInvested.map(\.name), ["Jo", "Sam", "Alex"])
    }

    // MARK: Cashing out and the bank

    func testNetIsWhatTheyLeftWithMinusWhatTheyPutIn() {
        var night = sampleNight()
        let sam = night.players[0].id
        XCTAssertNil(night.players[0].netMinor, "no net until they cash out")
        night.rebuy(sam)
        night.cashOut(sam, amountMinor: 8_000, at: t0)
        XCTAssertEqual(night.players[0].netMinor, 3_000)   // 80.00 out, 50.00 in
        night.clearCashOut(sam)
        XCTAssertNil(night.players[0].netMinor)
    }

    func testTheBankBalancesOnlyWhenEveryoneIsCashedOutForExactlyWhatWentIn() {
        var night = sampleNight()
        XCTAssertFalse(night.isBalanced, "nobody has cashed out")
        night.cashOut(night.players[0].id, amountMinor: 5_000, at: t0)
        night.cashOut(night.players[1].id, amountMinor: 1_500, at: t0)
        XCTAssertFalse(night.allCashedOut)
        night.cashOut(night.players[2].id, amountMinor: 1_000, at: t0)
        XCTAssertTrue(night.allCashedOut)
        XCTAssertEqual(night.bankDeltaMinor, 0)
        XCTAssertTrue(night.isBalanced)
    }

    func testAShortBankIsNotBalancedUntilItIsResolved() {
        let night = shortNight()
        XCTAssertEqual(night.bankDeltaMinor, -200)
        XCTAssertFalse(night.isBalanced)
        XCTAssertNil(night.settlementEntries())
        XCTAssertNil(night.payments())
    }

    func testAssigningTheDifferenceTreatsThatPlayersCountAsOffByIt() throws {
        var night = shortNight()
        let jo = night.players[2].id
        night.resolveBank(.assign, playerID: jo)

        XCTAssertTrue(night.isBalanced)
        let entries = try XCTUnwrap(night.settlementEntries())
        // Jo cashed out $8.00 against $25.00 in (−$17.00); the missing $2.00 is put down to Jo's count, so Jo owes $15.00.
        XCTAssertEqual(entries.map(\.netMinor), [2_500, -1_000, -1_500])
        XCTAssertEqual(entries.reduce(0) { $0 + $1.netMinor }, 0)
    }

    func testAnOverageAssignedToAPlayerTakesItOffTheirCashOut() throws {
        var night = sampleNight()
        night.cashOut(night.players[0].id, amountMinor: 5_000, at: t0)
        night.cashOut(night.players[1].id, amountMinor: 2_500, at: t0)
        night.cashOut(night.players[2].id, amountMinor: 500, at: t0)     // $5.00 more chips than money in
        XCTAssertEqual(night.bankDeltaMinor, 500)
        night.resolveBank(.assign, playerID: night.players[0].id)

        let entries = try XCTUnwrap(night.settlementEntries())
        XCTAssertEqual(entries.map(\.netMinor), [2_000, 0, -2_000])
    }

    func testSplittingTheDifferenceSharesItOutCentByCent() throws {
        var night = shortNight()          // −$2.00 across three players: −67, −67, −66 cents
        night.resolveBank(.split)
        let entries = try XCTUnwrap(night.settlementEntries())
        XCTAssertEqual(entries.reduce(0) { $0 + $1.netMinor }, 0)
        XCTAssertEqual(entries.map(\.netMinor), [2_500 + 67, -1_000 + 67, -1_700 + 66])
    }

    func testATipOrRakeIsRecordedAsAnEntryForTheHouse() throws {
        var night = shortNight()
        night.resolveBank(.tip)
        let entries = try XCTUnwrap(night.settlementEntries())
        XCTAssertEqual(entries.count, 4)
        XCTAssertEqual(entries.last, NetEntry(id: nil, name: "Tips", netMinor: 200))
        XCTAssertEqual(entries.reduce(0) { $0 + $1.netMinor }, 0)

        let payments = try XCTUnwrap(night.payments())
        XCTAssertTrue(payments.contains { $0.toName == "Tips" && $0.toID == nil && $0.amountMinor == 200 })
    }

    func testAnOverageCannotBeATip() {
        var night = sampleNight()
        night.cashOut(night.players[0].id, amountMinor: 5_000, at: t0)
        night.cashOut(night.players[1].id, amountMinor: 2_500, at: t0)
        night.cashOut(night.players[2].id, amountMinor: 500, at: t0)
        XCTAssertEqual(night.bankDeltaMinor, 500)
        night.resolveBank(.tip)
        XCTAssertFalse(night.isBalanced, "chips can't turn up as a tip")
        night.resolveBank(.split)
        XCTAssertTrue(night.isBalanced)
    }

    func testAResolutionStopsApplyingIfACashOutIsCorrected() {
        var night = shortNight()
        night.resolveBank(.split)
        XCTAssertTrue(night.isBalanced)

        night.cashOut(night.players[2].id, amountMinor: 700, at: t0)       // the difference is now $3.00
        XCTAssertEqual(night.bankDeltaMinor, -300)
        XCTAssertFalse(night.isBalanced, "the old choice was made for a different amount")
        XCTAssertNil(night.activeResolution)
    }

    func testAssigningToAPlayerWhoIsGoneDoesNotApply() {
        var night = shortNight()
        night.resolveBank(.assign, playerID: UUID())
        XCTAssertFalse(night.isBalanced)
    }

    func testResolvingABankThatBalancesClearsAnyChoice() {
        var night = shortNight()
        night.resolveBank(.split)
        night.cashOut(night.players[2].id, amountMinor: 1_000, at: t0)     // now exactly balanced
        XCTAssertEqual(night.bankDeltaMinor, 0)
        night.resolveBank(.split)
        XCTAssertNil(night.resolution)
        XCTAssertTrue(night.isBalanced)
    }

    func testNothingIsResolvedBeforeEveryoneHasCashedOut() {
        var night = sampleNight()
        night.cashOut(night.players[0].id, amountMinor: 5_000, at: t0)
        night.resolveBank(.split)
        XCTAssertNil(night.resolution)
        XCTAssertFalse(night.isBalanced)
    }

    // MARK: Closing the night

    func testANightOnlySettlesOnceItBalances() {
        var night = shortNight()
        XCTAssertFalse(night.settle(at: t0.addingTimeInterval(7_200)))
        XCTAssertNil(night.settledAt)

        night.resolveBank(.split)
        XCTAssertTrue(night.settle(at: t0.addingTimeInterval(7_200)))
        XCTAssertEqual(night.settledAt, t0.addingTimeInterval(7_200))
        XCTAssertEqual(night.endedAt, t0.addingTimeInterval(7_200), "settling ends play if it hadn't been called")
        XCTAssertTrue(night.isSettled)
        XCTAssertFalse(night.isOpen)
    }

    func testASettledNightCanBeReopenedToCorrectIt() {
        var night = shortNight()
        night.resolveBank(.split)
        night.settle(at: t0.addingTimeInterval(7_200))
        night.reopen()
        XCTAssertNil(night.settledAt)
        XCTAssertTrue(night.isOpen)
    }

    func testCallingTheGameStopsTheClockOnce() {
        var night = sampleNight()
        night.endPlay(at: t0.addingTimeInterval(3_600))
        night.endPlay(at: t0.addingTimeInterval(9_999))
        XCTAssertEqual(night.endedAt, t0.addingTimeInterval(3_600))
        XCTAssertFalse(night.isLive)
        XCTAssertTrue(night.isOpen)
    }

    func testTakingTheEndBackCarriesOnPlayingAndForgetsTheBankChoice() {
        var night = shortNight()
        night.resolveBank(.split)
        night.endPlay(at: t0.addingTimeInterval(3_600))
        night.resumePlay()
        XCTAssertNil(night.endedAt)
        XCTAssertNil(night.resolution)
        XCTAssertTrue(night.isLive)
    }

    // MARK: Playtime

    func testPlaytimeIsStartToEnd() {
        var night = sampleNight()
        XCTAssertEqual(night.playtimeSeconds(at: t0.addingTimeInterval(4_364)), 4_364, "still running: measured to now")
        night.endPlay(at: t0.addingTimeInterval(3_600))
        XCTAssertEqual(night.playtimeSeconds(at: t0.addingTimeInterval(99_999)), 3_600, "stopped: it stays stopped")
    }

    func testTimeOnHoldIsNotPlaytime() {
        var night = sampleNight()
        night.pause(at: t0.addingTimeInterval(1_800))
        night.resumeFromPause(at: t0.addingTimeInterval(2_700))          // 15 min break
        XCTAssertEqual(night.playtimeSeconds(at: t0.addingTimeInterval(3_600)), 3_600 - 900)

        night.pause(at: t0.addingTimeInterval(3_600))                    // on hold right now
        XCTAssertTrue(night.hasOpenPause)
        // 5,000 s elapsed − the 900 s break − the 1,400 s the game has now been on hold.
        XCTAssertEqual(night.playtimeSeconds(at: t0.addingTimeInterval(5_000)), 2_700, "the current break doesn't count either")
    }

    func testCallingTheGameEndsABreakWithIt() {
        var night = sampleNight()
        night.pause(at: t0.addingTimeInterval(1_000))
        night.endPlay(at: t0.addingTimeInterval(2_000))
        XCTAssertFalse(night.hasOpenPause)
        XCTAssertEqual(night.playtimeSeconds(), 1_000)
    }

    func testAClockSetBackwardsNeverGivesNegativeTime() {
        XCTAssertEqual(sampleNight().playtimeSeconds(at: t0.addingTimeInterval(-500)), 0)
    }

    func testTheDayAGameCountsForIsTheLocalDayItStartedOn() {
        // 03:30 UTC on 7 August is the evening of the 6th in Los Angeles and the morning of the 7th in Kolkata.
        let late = Date(timeIntervalSince1970: 1_786_073_400)    // 2026-08-07T03:30:00Z
        var night = sampleNight()
        night.startedAt = late

        night.tzIdentifier = "America/Los_Angeles"
        XCTAssertEqual(night.localDay.day, 6)
        night.tzIdentifier = "Asia/Kolkata"
        XCTAssertEqual(night.localDay.day, 7)
        night.tzIdentifier = "UTC"
        XCTAssertEqual(night.localDay.day, 7)
    }
}

// MARK: - Who is me, and who the regulars are

final class RegularsAndIdentityTests: XCTestCase {
    func testTheFirstPlayerIsTheOwnerOfThePhoneUnlessTold() {
        var night = sampleNight(["Sam", "Alex", "Jo"])
        XCTAssertEqual(night.me?.name, "Sam")

        night.setMe(night.players[2].id)
        XCTAssertEqual(night.me?.name, "Jo")

        night.setMe(UUID())                                   // someone who isn't playing
        XCTAssertEqual(night.me?.name, "Jo", "ignored")
        night.setMe(nil)
        XCTAssertNil(night.me)
    }

    func testAPhoneOwnerWhoIsNotPlayingHasNoResult() {
        let night = GameNight.start(
            now: t0, buyInMinor: 2_500, playerNames: ["Sam", "Alex"], colors: ["White"],
            denominationsMinor: ["White": 25], myPlayerIndex: nil
        )
        XCTAssertNil(night.me)
    }

    func testRemovingTheOwnerOfThePhoneLeavesNobodyMarked() {
        var night = sampleNight()
        night.removePlayer(night.players[0].id)
        XCTAssertNil(night.myPlayerID)
    }

    private func night(_ names: [String], on day: TimeInterval, place: String? = nil) -> GameNight {
        GameNight.start(
            now: t0.addingTimeInterval(day * 86_400), buyInMinor: 2_500, playerNames: names,
            colors: ["White"], denominationsMinor: ["White": 25], location: place
        )
    }

    func testRegularsAreTheMostFrequentNamesThenTheMostRecentInTheirLatestSpelling() {
        let history = [
            night(["sam", "Alex", "Jo"], on: 0),
            night(["Sam", "Alex", "Player 3"], on: 1),
            night(["Alex", "Kim", "Sam"], on: 2),
            night(["Pat", "Alex"], on: 3),
        ]
        XCTAssertEqual(Regulars.names(from: history), ["Alex", "Sam", "Pat", "Kim", "Jo"])
        XCTAssertFalse(Regulars.names(from: history).contains("Player 3"), "placeholders are not people")
    }

    func testDeletedNightsDoNotMakeRegulars() {
        var gone = night(["Ghost", "Alex"], on: 0)
        gone.markDeleted(at: t0)
        XCTAssertEqual(Regulars.names(from: [gone]), [])
    }

    func testSuggestionsFollowWhatIsTypedAndSkipPeopleAlreadyAdded() {
        let regulars = ["Alex", "Sam", "Samira", "Pat"]
        XCTAssertEqual(Regulars.suggestions(from: regulars, matching: "", excluding: ["alex"]), ["Sam", "Samira", "Pat"])
        XCTAssertEqual(Regulars.suggestions(from: regulars, matching: " sa", excluding: []), ["Sam", "Samira"])
        XCTAssertEqual(Regulars.suggestions(from: regulars, matching: "zz", excluding: []), [])
        XCTAssertEqual(Regulars.suggestions(from: regulars, matching: "", excluding: [], limit: 2), ["Alex", "Sam"])
    }

    func testPlacesAreMostRecentFirstWithoutRepeats() {
        let history = [
            night(["A", "B"], on: 0, place: "Pat's garage"),
            night(["A", "B"], on: 5, place: "Jo's place"),
            night(["A", "B"], on: 9, place: "pat's garage"),
            night(["A", "B"], on: 10),
        ]
        XCTAssertEqual(Regulars.places(from: history), ["pat's garage", "Jo's place"])
    }
}

// MARK: - What a night means for me

final class NightSummaryTests: XCTestCase {
    func testMyResultIsMyCashOutMinusWhatIPutIn() {
        var night = sampleNight(["Sam", "Alex"])
        night.rebuy(night.players[1].id, amountMinor: 2_500)                  // Alex is in for $50, Sam for $25
        night.cashOut(night.players[0].id, amountMinor: 7_500, at: t0)
        night.cashOut(night.players[1].id, amountMinor: 0, at: t0)
        night.endPlay(at: t0.addingTimeInterval(7_200))

        XCTAssertTrue(night.isBalanced)                                        // $75.00 in, $75.00 out
        let summary = NightSummary(night: night)
        XCTAssertEqual(summary.myNetMinor, 5_000)
        XCTAssertEqual(summary.myTotalInMinor, 2_500)
        XCTAssertEqual(summary.playtimeSeconds, 7_200)
        XCTAssertEqual(summary.perHourMinor, 2_500)                            // +$50.00 in two hours
        XCTAssertEqual(summary.potMinor, 7_500)
    }

    func testMyResultIsAfterTheBankDifferenceWasResolved() {
        var night = sampleNight(["Sam", "Alex"])                               // $50.00 in
        night.cashOut(night.players[0].id, amountMinor: 7_500, at: t0)         // $75.00 of chips cashed out: $25.00 more than the money
        night.cashOut(night.players[1].id, amountMinor: 0, at: t0)
        night.endPlay(at: t0.addingTimeInterval(3_600))
        XCTAssertFalse(night.isBalanced)

        night.resolveBank(.split)                                              // each cash-out is cut by $12.50
        XCTAssertTrue(night.isBalanced)
        XCTAssertEqual(NightSummary(night: night).myNetMinor, 5_000 - 1_250)
    }

    func testAVeryShortNightHasNoPerHourFigure() {
        var night = sampleNight(["Sam", "Alex"])
        night.cashOut(night.players[0].id, amountMinor: 5_000, at: t0)
        night.cashOut(night.players[1].id, amountMinor: 0, at: t0)
        night.endPlay(at: t0.addingTimeInterval(299))
        XCTAssertNil(NightSummary(night: night).perHourMinor)

        night.resumePlay()
        night.endPlay(at: t0.addingTimeInterval(300))
        XCTAssertNotNil(NightSummary(night: night).perHourMinor)
    }

    func testSomeoneNotPlayingHasNoResult() {
        var night = GameNight.start(
            now: t0, buyInMinor: 2_500, playerNames: ["Sam", "Alex"], colors: ["White"],
            denominationsMinor: ["White": 25], myPlayerIndex: nil
        )
        night.cashOut(night.players[0].id, amountMinor: 5_000, at: t0)
        night.cashOut(night.players[1].id, amountMinor: 0, at: t0)
        let summary = NightSummary(night: night)
        XCTAssertNil(summary.myNetMinor)
        XCTAssertNil(summary.perHourMinor)
        XCTAssertEqual(summary.potMinor, 5_000)
    }
}

// MARK: - The week at the table

final class WeeklySummaryTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_786_017_600)          // 2026-08-06T12:00:00Z
    private let losAngeles = TimeZone(identifier: "America/Los_Angeles") ?? .current
    private let kolkata = TimeZone(identifier: "Asia/Kolkata") ?? .current

    private func night(startingAt start: Date, minutes: Int) -> GameNight {
        var night = GameNight.start(now: start, buyInMinor: 2_500, playerNames: ["Sam", "Alex"], colors: ["White"], denominationsMinor: ["White": 25])
        night.endPlay(at: start.addingTimeInterval(TimeInterval(minutes * 60)))
        return night
    }

    func testAnEveningGameCountsForTheLocalDayItStartedOnInEveryZone() {
        // 06:30 UTC on 6 August is 23:30 on the 5th in Los Angeles and 12:00 on the 6th in Kolkata:
        // the same 135 minutes, on different days.
        let game = night(startingAt: Date(timeIntervalSince1970: 1_785_997_800), minutes: 135)

        let la = WeeklySummary.make(from: [game], now: now, timeZone: losAngeles)
        XCTAssertEqual(la.totalSeconds, 135 * 60)
        XCTAssertEqual(la.days.map(\.date), ["2026-07-31", "2026-08-01", "2026-08-02", "2026-08-03", "2026-08-04", "2026-08-05", "2026-08-06"])
        XCTAssertEqual(la.days.map(\.seconds), [0, 0, 0, 0, 0, 8_100, 0], "23:30 on the 5th in Los Angeles")

        let india = WeeklySummary.make(from: [game], now: now, timeZone: kolkata)
        XCTAssertEqual(india.totalSeconds, 135 * 60)
        XCTAssertEqual(india.days.map(\.seconds), [0, 0, 0, 0, 0, 0, 8_100], "12:00 on the 6th in Kolkata")
    }

    func testTheBarsAlwaysAddUpToTheTotal() {
        let games = (0..<20).map { index in
            night(startingAt: now.addingTimeInterval(TimeInterval(-index * 37_000)), minutes: 20 + index * 7)
        }
        for zone in [losAngeles, kolkata, TimeZone(identifier: "UTC") ?? .current] {
            let summary = WeeklySummary.make(from: games, now: now, timeZone: zone)
            XCTAssertEqual(summary.days.count, 7)
            XCTAssertEqual(summary.totalSeconds, summary.days.reduce(0) { $0 + $1.seconds }, zone.identifier)
        }
    }

    func testAGameBeforeTheWindowDoesNotCount() {
        let old = night(startingAt: now.addingTimeInterval(-8 * 86_400), minutes: 90)
        XCTAssertEqual(WeeklySummary.make(from: [old], now: now, timeZone: losAngeles).totalSeconds, 0)
    }

    func testAGamePastMidnightIsNotSplitAcrossTwoDays() {
        // Starts 22:00 on the 5th in Los Angeles (05:00 UTC on the 6th) and runs four hours, past midnight.
        let game = night(startingAt: Date(timeIntervalSince1970: 1_785_992_400), minutes: 240)
        let summary = WeeklySummary.make(from: [game], now: now, timeZone: losAngeles)
        XCTAssertEqual(summary.days.map(\.seconds), [0, 0, 0, 0, 0, 14_400, 0])
    }

    func testABreakIsNotPlaytime() {
        let start = now.addingTimeInterval(-3 * 3_600)
        var game = GameNight.start(now: start, buyInMinor: 2_500, playerNames: ["Sam", "Alex"], colors: ["White"], denominationsMinor: ["White": 25])
        game.pause(at: start.addingTimeInterval(3_600))
        game.resumeFromPause(at: start.addingTimeInterval(3_600 + 900))
        game.endPlay(at: start.addingTimeInterval(2 * 3_600))
        XCTAssertEqual(WeeklySummary.make(from: [game], now: now, timeZone: .gmt).totalSeconds, 2 * 3_600 - 900)
    }

    func testADeletedNightIsNotCounted() {
        var game = night(startingAt: now.addingTimeInterval(-3_600), minutes: 30)
        game.markDeleted(at: now)
        XCTAssertEqual(WeeklySummary.make(from: [game], now: now, timeZone: .gmt).totalSeconds, 0)
    }

    func testAGameStillBeingPlayedCountsUpToNow() {
        let live = GameNight.start(now: now.addingTimeInterval(-5_400), buyInMinor: 2_500, playerNames: ["Sam", "Alex"], colors: ["White"], denominationsMinor: ["White": 25])
        XCTAssertEqual(WeeklySummary.make(from: [live], now: now, timeZone: .gmt).totalSeconds, 5_400)
    }
}

// MARK: - Names

final class PlayerNamingTests: XCTestCase {
    func testBlankSeatsAreNumberedBySeat() {
        XCTAssertEqual(PlayerNaming.finalNames(["Pranav", "", "  ", "Jo"]), ["Pranav", "Player 2", "Player 3", "Jo"])
    }

    func testTwoPeopleWithTheSameNameAreFlaggedWhateverTheCase() {
        XCTAssertEqual(PlayerNaming.duplicateSeats(in: ["Sam", "Alex", "sam ", ""]), [0, 2])
        XCTAssertEqual(PlayerNaming.duplicateSeats(in: ["Sam", "Alex", "Jo"]), [])
    }

    func testBlankSeatsNeverCollideWithEachOtherOrWithAnAutoName() {
        XCTAssertEqual(PlayerNaming.duplicateSeats(in: ["", "", ""]), [])
        XCTAssertEqual(PlayerNaming.duplicateSeats(in: ["Player 2", ""]), [0, 1], "a typed “Player 2” would clash with the auto name for seat 2")
    }
}

// MARK: - Starting a night from the setup screens

@MainActor
final class StartNightTests: XCTestCase {
    func testTheNightIsBuiltFromTheSetupAndTheChosenChips() async throws {
        let store = NightStore(repository: MemoryNightRepository())
        await store.load()
        let setup = GameSetup(buyIn: 25, players: 4, availableColors: ["White", "Red"], playerNames: ["Pranav", "Sam"], location: " Pat's garage ")

        let night = store.startNight(
            from: setup, buyInMinor: 2_500,
            denominationsMinor: ["White": 25, "Red": 100], startingCounts: ["White": 40, "Red": 15]
        )

        XCTAssertEqual(night.players.map(\.name), ["Pranav", "Sam", "Player 3", "Player 4"])
        XCTAssertEqual(night.me?.name, "Pranav", "the first seat is the person holding the phone")
        XCTAssertEqual(night.location, "Pat's garage")
        XCTAssertEqual(night.colors, ["White", "Red"])
        XCTAssertEqual(night.defaultBuyInMinor, 2_500)
        XCTAssertEqual(night.totalInMinor, 10_000)
        XCTAssertTrue(night.isLive)
        XCTAssertEqual(store.openNight?.id, night.id)
        XCTAssertEqual(store.pending.map(\.id), [night.id])
    }

    func testTheLastNightWithTheSameChipsCanBeReused() async throws {
        let store = NightStore(repository: MemoryNightRepository())
        await store.load()
        let setup = GameSetup(buyIn: 25, players: 4, availableColors: ["White", "Red"])
        XCTAssertNil(store.lastNight(matching: setup))

        let first = store.startNight(from: setup, buyInMinor: 2_500, denominationsMinor: ["White": 25, "Red": 100], startingCounts: ["White": 40, "Red": 15])
        XCTAssertEqual(store.lastNight(matching: setup)?.id, first.id)
        XCTAssertEqual(store.lastNight(matching: GameSetup(buyIn: 25.02, players: 6, availableColors: ["White", "Red"]))?.id, first.id, "a buy-in rounded to a nickel is still the same chips")
        XCTAssertNil(store.lastNight(matching: GameSetup(buyIn: 50, players: 4, availableColors: ["White", "Red"])))
        XCTAssertNil(store.lastNight(matching: GameSetup(buyIn: 25, players: 4, availableColors: ["White", "Red", "Blue"])))
    }
}
