//
//  ShareCardTests.swift
//  PokerChipAppTests
//
//  The pictures that can be sent to the group chat, and the time on breaks that
//  the weekly recap and the clock must never count as played.
//

import XCTest
import UIKit
import SwiftUI
@testable import PokerChipApp

private let start = Date(timeIntervalSince1970: 1_786_042_800)

private func night(place: String? = "Pat's garage", names: [String] = ["Sam", "Alex", "Jo"]) -> GameNight {
    GameNight.start(
        now: start, timeZone: TimeZone(identifier: "UTC") ?? .current, buyInMinor: 2_500, playerNames: names,
        colors: ["White", "Red", "Blue"], denominationsMinor: ["White": 25, "Red": 100, "Blue": 250],
        startingCounts: ["White": 20, "Red": 8, "Blue": 2], location: place
    )
}

// MARK: - Pictures

@MainActor
final class ShareCardsTests: XCTestCase {
    func testANightSummaryIsDrawnAsAPicture() throws {
        var played = night()
        played.endPlay(at: start.addingTimeInterval(3 * 3_600 + 20 * 60))
        let image = try XCTUnwrap(ShareCards.image(NightSummaryCard(night: played)))
        XCTAssertEqual(image.size.width, 360, accuracy: 0.5)
        XCTAssertEqual(image.scale, 3, accuracy: 0.01, "sharp on a retina screen")
        XCTAssertGreaterThan(image.size.height, 150)
        XCTAssertLessThan(image.size.height, 600)
    }

    func testANightWithNoPlaceOrChipsStillMakesACard() throws {
        var bare = night(place: nil, names: ["Sam"])
        bare.colors = []
        bare.denominationsMinor = [:]
        XCTAssertNotNil(ShareCards.image(NightSummaryCard(night: bare)))
    }

    func testAWeeklyRecapIsDrawnForABusyWeekAndAnEmptyOne() throws {
        let busy = WeeklySummary(
            totalSeconds: 19_200,
            days: (0..<7).map { WeeklySummary.DaySummary(date: "2026-10-0\($0 + 3)", seconds: [0, 5_400, 0, 7_200, 3_600, 0, 3_000][$0]) }
        )
        let quiet = WeeklySummary(totalSeconds: 0, days: (0..<7).map { WeeklySummary.DaySummary(date: "2026-10-0\($0 + 3)", seconds: 0) })
        for summary in [busy, quiet] {
            let image = try XCTUnwrap(ShareCards.image(WeeklyRecapCard(summary: summary, trend: WeekTrend(weeks: [0, 3_600, 7_200, summary.totalSeconds]))))
            XCTAssertEqual(image.size.width, 360, accuracy: 0.5)
        }
    }

    func testAWeekWithNoDaysDoesNotCrashTheCard() {
        XCTAssertNotNil(ShareCards.image(WeeklyRecapCard(summary: WeeklySummary(totalSeconds: 0, days: []), trend: WeekTrend(weeks: []))))
    }

    func testTheWeekdayLetterAndTheRangeAreReadFromTheDays() {
        XCTAssertEqual(WeeklyRecapCard.weekdayLetter("2026-10-05"), "M", "5 October 2026 is a Monday")
        XCTAssertEqual(WeeklyRecapCard.weekdayLetter("2026-10-09"), "F")
        XCTAssertEqual(WeeklyRecapCard.weekdayLetter("not a date"), "")

        let days = (3...9).map { WeeklySummary.DaySummary(date: "2026-10-0\($0)", seconds: 0) }
        XCTAssertEqual(WeeklyRecapCard.rangeText(days), "Oct 3 – Oct 9")
        XCTAssertNil(WeeklyRecapCard.rangeText([]))
    }
}

// MARK: - Time on a break

final class BreakTimeTests: XCTestCase {
    private func hours(_ h: Double) -> Date { start.addingTimeInterval(h * 3_600) }

    func testABreakIsNotPlayedTime() {
        var game = night()
        game.pause(at: hours(1))
        game.resumeFromPause(at: hours(1.5))
        game.endPlay(at: hours(3))

        XCTAssertEqual(game.pausedSeconds(), 1_800)
        XCTAssertEqual(game.playtimeSeconds(), 9_000, "three hours minus the half hour on the break")
    }

    func testAnOpenBreakKeepsGrowingWhileTheClockStaysStill() {
        var game = night()
        game.pause(at: hours(1))

        XCTAssertEqual(game.playtimeSeconds(at: hours(1.25)), 3_600)
        XCTAssertEqual(game.playtimeSeconds(at: hours(2)), 3_600, "the clock doesn't move on a break")
        XCTAssertEqual(game.pausedSeconds(at: hours(1.25)), 900)
        XCTAssertEqual(game.pausedSeconds(at: hours(2)), 3_600)
    }

    func testCallingTheGameOnABreakEndsTheBreakThere() {
        var game = night()
        game.pause(at: hours(2))
        game.endPlay(at: hours(2.5))

        XCTAssertFalse(game.hasOpenPause)
        XCTAssertEqual(game.pausedSeconds(at: hours(10)), 1_800, "and later never adds to it")
        XCTAssertEqual(game.playtimeSeconds(at: hours(10)), 7_200)
    }

    func testSeveralBreaksAddUp() {
        var game = night()
        for (from, to) in [(0.5, 0.75), (1.0, 1.25), (2.0, 2.5)] {
            game.pause(at: hours(from))
            game.resumeFromPause(at: hours(to))
        }
        game.endPlay(at: hours(4))
        XCTAssertEqual(game.pausedSeconds(), 3_600)
        XCTAssertEqual(game.playtimeSeconds(), 10_800)
    }

    func testPlayedTimeAndBreakTimeAlwaysAccountForTheWholeNight() {
        var rng = SplitMix64(seed: 77)
        for _ in 0..<500 {
            var game = night()
            var clock = 0.0
            for _ in 0..<Int.random(in: 0...5, using: &rng) {
                clock += Double.random(in: 0.05...1, using: &rng)
                game.pause(at: hours(clock))
                clock += Double.random(in: 0.05...1, using: &rng)
                game.resumeFromPause(at: hours(clock))
            }
            clock += Double.random(in: 0.05...1, using: &rng)
            game.endPlay(at: hours(clock))
            let span = Int((hours(clock).timeIntervalSince(start)).rounded(.down))
            XCTAssertLessThanOrEqual(abs(game.playtimeSeconds() + game.pausedSeconds() - span), 1, "played + break = the night, give or take a rounding second")
            XCTAssertGreaterThanOrEqual(game.playtimeSeconds(), 0)
        }
    }

    func testABreakCanOnlyStartOnALiveNightAndOnlyOnce() {
        var game = night()
        game.pause(at: hours(1))
        game.pause(at: hours(1.2))                      // already on one
        XCTAssertEqual(game.pauses.count, 1)

        game.resumeFromPause(at: hours(1.5))
        game.resumeFromPause(at: hours(1.7))            // nothing to resume
        XCTAssertEqual(game.pauses.first?.end, hours(1.5))

        game.endPlay(at: hours(2))
        game.pause(at: hours(3))                        // the game is over
        XCTAssertEqual(game.pauses.count, 1)
    }

    func testABreakBeforeTheNightStartedOrAfterItEndedIsClamped() {
        var game = night()
        game.pauses = [
            PauseInterval(start: hours(-1), end: hours(0.5)),     // started before the night
            PauseInterval(start: hours(1.5), end: hours(5)),      // runs past the end
        ]
        game.endedAt = hours(2)
        XCTAssertEqual(game.pausedSeconds(), 1_800 + 1_800)
        XCTAssertEqual(game.playtimeSeconds(), 3_600)
    }
}
