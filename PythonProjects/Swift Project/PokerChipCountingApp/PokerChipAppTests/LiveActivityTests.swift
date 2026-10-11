//
//  LiveActivityTests.swift
//  PokerChipAppTests
//
//  The night in progress on the Lock Screen: what the Live Activity is told, and
//  what the links on it do.
//

import XCTest
@testable import PokerChipApp

final class NightActivityStateTests: XCTestCase {
    private typealias State = NightActivityAttributes.ContentState
    private let start = Date(timeIntervalSince1970: 1_786_042_800)

    private func liveNight() -> GameNight {
        GameNight.start(now: start, buyInMinor: 2_500, playerNames: ["Sam", "Alex", "Jo"], colors: ["White"], denominationsMinor: ["White": 25])
    }

    func testARunningNightShowsWhenItsClockStartedAndTheMoneyOnTheTable() throws {
        let state = try XCTUnwrap(State(night: liveNight(), now: start.addingTimeInterval(3_723)))
        XCTAssertEqual(state.clockStart, start)
        XCTAssertNil(state.frozenSeconds)
        XCTAssertFalse(state.isOnBreak)
        XCTAssertEqual(state.players, 3)
        XCTAssertEqual(state.inPlayMinor, 7_500)
        XCTAssertEqual(state.currencyCode, "USD")
    }

    func testAQuietMinuteChangesNothingItShows() throws {
        let night = liveNight()
        XCTAssertEqual(State(night: night, now: start.addingTimeInterval(100)), State(night: night, now: start.addingTimeInterval(9_000)),
                       "the clock counts up by itself, so a running night is the same state however late it is looked at")
    }

    func testTimeOnAFinishedBreakIsLeftOutOfTheClock() throws {
        var night = liveNight()
        night.pause(at: start.addingTimeInterval(1_800))
        night.resumeFromPause(at: start.addingTimeInterval(2_400))      // ten minutes

        let now = start.addingTimeInterval(3_600)
        let state = try XCTUnwrap(State(night: night, now: now))
        XCTAssertEqual(state.clockStart, start.addingTimeInterval(600))
        XCTAssertEqual(Int(now.timeIntervalSince(state.clockStart)), night.playtimeSeconds(at: now), "what the system counts up is exactly the time played")
        XCTAssertNil(state.frozenSeconds)
    }

    func testOnABreakTheClockStandsStillAtTheTimePlayed() throws {
        var night = liveNight()
        night.pause(at: start.addingTimeInterval(1_800))

        let early = try XCTUnwrap(State(night: night, now: start.addingTimeInterval(2_000)))
        let late = try XCTUnwrap(State(night: night, now: start.addingTimeInterval(5_000)))
        XCTAssertTrue(early.isOnBreak)
        XCTAssertEqual(early.frozenSeconds, 1_800)
        XCTAssertEqual(early, late, "a longer break shows the same thing, so it is not sent again")
    }

    func testARebuyAddsToTheMoneyOnTheTable() throws {
        var night = liveNight()
        let player = try XCTUnwrap(night.players.first)
        night.rebuy(player.id, amountMinor: 2_500, at: start.addingTimeInterval(600))
        XCTAssertEqual(try XCTUnwrap(State(night: night, now: start)).inPlayMinor, 10_000)
    }

    func testNothingIsShownOnceThePlayIsCalledOrTheNightIsClosedOrDeleted() throws {
        var called = liveNight()
        called.endPlay(at: start.addingTimeInterval(3_600))
        XCTAssertNil(State(night: called, now: start.addingTimeInterval(3_700)))

        var deleted = liveNight()
        deleted.markDeleted(at: start.addingTimeInterval(60))
        XCTAssertNil(State(night: deleted, now: start))
    }

    func testTheClockReadsTheWayItDoesOnScreen() {
        XCTAssertEqual(ActivityMoney.clock(seconds: 0), "0:00")
        XCTAssertEqual(ActivityMoney.clock(seconds: 125), "2:05")
        XCTAssertEqual(ActivityMoney.clock(seconds: 3_723), "1:02:03")
        XCTAssertEqual(ActivityMoney.clock(seconds: -5), "0:00")
        XCTAssertEqual(ActivityMoney.format(minor: 7_500, currencyCode: "USD"), "$75.00")
    }
}

@MainActor
final class NightLinkTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_786_042_800)

    private func store(with nights: [GameNight]) async -> NightStore {
        let store = NightStore(repository: MemoryNightRepository(nights: nights), clock: { Date(timeIntervalSince1970: 1_786_042_800) })
        await store.load()
        return store
    }

    private func liveNight() -> GameNight {
        GameNight.start(now: start, buyInMinor: 2_500, playerNames: ["Sam", "Alex"], colors: ["White"], denominationsMinor: ["White": 25])
    }

    func testEveryLinkSurvivesBeingTurnedIntoAnAddressAndBack() {
        for link in [NightLink.openNight, .takeBreak, .resumePlay] {
            XCTAssertEqual(NightLink(url: link.url), link, "\(link.url)")
        }
    }

    func testOnlyTheAppsOwnLinksAreUnderstood() throws {
        for address in ["https://example.com/night", "chipcounter://elsewhere", "chipcounter://night/delete", "otherapp://night/break", "chipcounter://night/break/now"] {
            XCTAssertNil(NightLink(url: try XCTUnwrap(URL(string: address))), address)
        }
        XCTAssertEqual(NightLink(url: try XCTUnwrap(URL(string: "CHIPCOUNTER://night/"))), .openNight)
    }

    func testABreakLinkStopsTheClockAndShowsTheNight() async throws {
        let night = liveNight()
        let store = await store(with: [night])

        XCTAssertEqual(store.handle(.takeBreak), night.id)
        XCTAssertEqual(store.night(night.id)?.hasOpenPause, true)
    }

    func testTappingBreakTwiceChangesNothingTheSecondTime() async throws {
        let night = liveNight()
        let store = await store(with: [night])
        store.handle(.takeBreak)
        let once = try XCTUnwrap(store.night(night.id))

        store.handle(.takeBreak)
        XCTAssertEqual(store.night(night.id), once, "no second break, and no new version to back up")
        XCTAssertEqual(once.pauses.count, 1)
    }

    func testAResumeLinkTakesTheClockOffABreakAndIsHarmlessOtherwise() async throws {
        let night = liveNight()
        let store = await store(with: [night])

        let untouched = try XCTUnwrap(store.night(night.id))
        store.handle(.resumePlay)
        XCTAssertEqual(store.night(night.id), untouched, "nothing to resume")

        store.handle(.takeBreak)
        XCTAssertEqual(store.night(night.id)?.hasOpenPause, true)
        store.handle(.resumePlay)
        XCTAssertEqual(store.night(night.id)?.hasOpenPause, false)
        XCTAssertEqual(store.night(night.id)?.pauses.count, 1)
    }

    func testOpeningTheNightNeverChangesIt() async throws {
        let night = liveNight()
        let store = await store(with: [night])
        let before = try XCTUnwrap(store.night(night.id))
        XCTAssertEqual(store.handle(.openNight), night.id)
        XCTAssertEqual(store.night(night.id), before)
    }

    func testWithNoNightInProgressThereIsNothingToShowOrChange() async throws {
        var over = liveNight()
        over.endPlay(at: start.addingTimeInterval(3_600))
        let store = await store(with: [over])
        let before = try XCTUnwrap(store.night(over.id))

        for link in [NightLink.openNight, .takeBreak, .resumePlay] {
            XCTAssertNil(store.handle(link))
        }
        XCTAssertEqual(store.night(over.id), before)
        let empty = await self.store(with: [])
        XCTAssertNil(empty.handle(.takeBreak))
    }
}
