import XCTest
@testable import PickleCore

final class PredictionTests: XCTestCase {
    let predictor = WaitPredictor()
    let now = Fixtures.wednesdayEvening

    func testDecayHalvesAtHalfLife() {
        let c = PredictionConfig()
        XCTAssertEqual(c.decay(ageMinutes: 0), 1, accuracy: 1e-9)
        XCTAssertEqual(c.decay(ageMinutes: 25), 0.5, accuracy: 1e-6)
        XCTAssertLessThan(c.decay(ageMinutes: 120), 0.05)
    }

    func testUsesUsableCourtsNotPhysicalCourts() {
        var f = Fixtures.facility(courts: 6, pickleball: 4)
        XCTAssertEqual(predictor.usableCourts(for: f, at: now).0, 4)
        f.overrides = [OperationalOverride(kind: .usableCourts, value: 2, startsAt: now.addingTimeInterval(-600),
                                           expiresAt: now.addingTimeInterval(3600), confidence: 0.8)]
        let (n, src) = predictor.usableCourts(for: f, at: now)
        XCTAssertEqual(n, 2); XCTAssertEqual(src, .reported)
    }

    func testLowConfidenceOverrideIgnored() {
        var f = Fixtures.facility(pickleball: 4)
        f.overrides = [OperationalOverride(kind: .usableCourts, value: 1, startsAt: now.addingTimeInterval(-60),
                                           expiresAt: now.addingTimeInterval(3600), confidence: 0.2)]
        XCTAssertEqual(predictor.usableCourts(for: f, at: now).0, 4)
    }

    func testPartialBlackoutRemovesCourts() {
        var f = Fixtures.facility(pickleball: 4)
        f.blackouts = [Blackout(startAt: now.addingTimeInterval(-60), endAt: now.addingTimeInterval(3600), reason: .leagueEvent, courtsAffected: 3)]
        XCTAssertEqual(predictor.usableCourts(for: f, at: now).0, 1)
    }

    func testFreshCourtsOpenReportsGiveShortWaitHighConfidence() {
        let live = [LiveObservation(ageMinutes: 3, status: .courtsOpen, weight: 1),
                    LiveObservation(ageMinutes: 8, status: .courtsOpen, weight: 1),
                    LiveObservation(ageMinutes: 12, status: .courtsOpen, weight: 0.9)]
        let p = predictor.predict(facility: Fixtures.facility(live: live), now: now)
        XCTAssertEqual(p.wait, WaitRange(low: 0, high: 5))
        XCTAssertEqual(p.confidence, .high)
        XCTAssertEqual(p.basis, .live)
        XCTAssertEqual(p.busyLevel, .quiet)
    }

    func testPlayersWaitingProducesLongerWaitThanAllFull() {
        let full = predictor.predict(facility: Fixtures.facility(live: [LiveObservation(ageMinutes: 2, status: .allFull),
                                                                          LiveObservation(ageMinutes: 4, status: .allFull)]), now: now)
        let waiting = predictor.predict(facility: Fixtures.facility(live: [LiveObservation(ageMinutes: 2, status: .playersWaiting),
                                                                             LiveObservation(ageMinutes: 4, status: .playersWaiting)]), now: now)
        XCTAssertGreaterThan(waiting.rawWaitHigh, full.rawWaitHigh)
        XCTAssertGreaterThan(waiting.wait.midpoint, 5)
    }

    func testRecentReportsOutweighStaleHistory() {
        let history = HistoricalBucket(dayOfWeek: 3, bucket: 36, sampleCount: 40, avgOccupancy: 1.0)
        let live = [LiveObservation(ageMinutes: 2, status: .courtsOpen), LiveObservation(ageMinutes: 5, status: .courtsOpen),
                    LiveObservation(ageMinutes: 6, status: .courtsOpen)]
        let p = predictor.predict(facility: Fixtures.facility(live: live, history: history), now: now)
        XCTAssertLessThan(p.occupancy, 0.8)
    }

    func testOldReportsAlmostIrrelevant() {
        let history = HistoricalBucket(dayOfWeek: 3, bucket: 36, sampleCount: 40, avgOccupancy: 0.3)
        let live = [LiveObservation(ageMinutes: 170, status: .playersWaiting)]
        let p = predictor.predict(facility: Fixtures.facility(live: live, history: history), now: now)
        XCTAssertLessThan(p.occupancy, 0.35)
    }

    func testPaddleStackWaitScalesWithPaddlesAndCourts() {
        func wait(paddles: Double, courts: Int) -> WaitPrediction {
            predictor.predict(facility: Fixtures.facility(pickleball: courts, play: .paddleStack,
                live: [LiveObservation(kind: .paddleStack, ageMinutes: 2, paddles: paddles),
                       LiveObservation(ageMinutes: 2, status: .allFull)]), now: now)
        }
        let short = wait(paddles: 4, courts: 4)
        let long = wait(paddles: 24, courts: 4)
        let longFewCourts = wait(paddles: 24, courts: 2)
        XCTAssertLessThan(short.rawWaitHigh, long.rawWaitHigh)
        XCTAssertLessThan(long.rawWaitHigh, longFewCourts.rawWaitHigh)
        XCTAssertEqual(long.paddleStack, .long)
        // 24 paddles / (4 players × 4 courts) = 1.5 games ahead × 13 min ≈ 13–32 min raw
        XCTAssertEqual(long.rawWaitLow, 1.0 * 13 * 0.8, accuracy: 0.01)
        XCTAssertEqual(long.rawWaitHigh, 2.0 * 13 * 1.25, accuracy: 0.01)
    }

    func testNoDataUsesPriorWithLowConfidence() {
        let p = predictor.predict(facility: Fixtures.facility(), now: now)
        XCTAssertEqual(p.basis, .prior)
        XCTAssertEqual(p.confidence, .low)
    }

    func testRainReducesHistoricalDemand() {
        let history = HistoricalBucket(dayOfWeek: 3, bucket: 36, sampleCount: 40, avgOccupancy: 0.9)
        let rain = WeatherConditions(temperatureF: 60, windMph: 3, precipitationChance: 0.9)
        let dry = predictor.predict(facility: Fixtures.facility(history: history), now: now)
        let wet = predictor.predict(facility: Fixtures.facility(history: history), now: now, weather: rain)
        XCTAssertLessThan(wet.occupancy, dry.occupancy)
        let indoor = predictor.predict(facility: Fixtures.facility(indoor: .indoor, history: history), now: now, weather: rain)
        XCTAssertEqual(indoor.occupancy, dry.occupancy, accuracy: 1e-9)
    }

    func testZeroUsableCourts() {
        let p = predictor.predict(facility: Fixtures.facility(courts: 0, pickleball: 0), now: now)
        XCTAssertEqual(p.usableCourts, 0)
        XCTAssertNil(p.wait.high)
    }
}

final class WaitRangeTests: XCTestCase {
    func testSnappingIsHonest() {
        XCTAssertEqual(WaitRange.snapped(rawLow: 0, rawHigh: 3, confidence: .high), WaitRange(low: 0, high: 5))
        XCTAssertEqual(WaitRange.snapped(rawLow: 5, rawHigh: 12, confidence: .high), WaitRange(low: 5, high: 15))
        XCTAssertEqual(WaitRange.snapped(rawLow: 10, rawHigh: 26, confidence: .medium), WaitRange(low: 15, high: 30))
        XCTAssertEqual(WaitRange.snapped(rawLow: 70, rawHigh: 90, confidence: .high), WaitRange(low: 60, high: nil))
    }
    func testLowConfidenceWidens() {
        XCTAssertEqual(WaitRange.snapped(rawLow: 5, rawHigh: 12, confidence: .low), WaitRange(low: 5, high: 20))
    }
    func testLabels() {
        XCTAssertEqual(WaitRange(low: 5, high: 15).label, "5–15 min")
        XCTAssertEqual(WaitRange(low: 60, high: nil).label, "60+ min")
    }
}

final class ConfidenceTests: XCTestCase {
    func testHighNeedsFreshAgreeingObservations() {
        XCTAssertEqual(ConfidenceModel.level(.init(liveEffectiveWeight: 2.5, freshObservationCount: 3, agreement: 0.9, verifiedShare: 1)), .high)
        XCTAssertEqual(ConfidenceModel.level(.init(liveEffectiveWeight: 2.5, freshObservationCount: 1, agreement: 0.9, verifiedShare: 1)), .medium)
    }
    func testDisagreementLowersConfidence() {
        let agree = ConfidenceModel.agreement(values: [1, 1, 0.9], weights: [1, 1, 1])
        let disagree = ConfidenceModel.agreement(values: [0.45, 1, 0.45, 1], weights: [1, 1, 1, 1])
        XCTAssertGreaterThan(agree, 0.8)
        XCTAssertLessThan(disagree, 0.6)
        XCTAssertNotEqual(ConfidenceModel.level(.init(liveEffectiveWeight: 3, freshObservationCount: 4, agreement: disagree, verifiedShare: 1)), .high)
    }
    func testHistoryAloneCanReachMedium() {
        XCTAssertEqual(ConfidenceModel.level(.init(historicalSamples: 40, usableCourtsKnown: true)), .medium)
        XCTAssertEqual(ConfidenceModel.level(.init(historicalSamples: 5)), .low)
    }
    func testPriorIsAlwaysLow() {
        XCTAssertEqual(ConfidenceModel.level(.init(historicalSamples: 0, usableCourtsKnown: true, usesGenericPrior: true)), .low)
    }
}
