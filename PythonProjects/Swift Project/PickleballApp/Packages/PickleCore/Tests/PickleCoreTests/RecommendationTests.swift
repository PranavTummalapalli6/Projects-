import XCTest
@testable import PickleCore

final class RecommendationTests: XCTestCase {
    let engine = RecommendationEngine()
    let now = Fixtures.wednesdayEvening

    func testBlackoutIsNeverTopPickAndExplainsWhy() {
        var tournament = Fixtures.facility(name: "Tournament Park", live: [LiveObservation(ageMinutes: 1, status: .courtsOpen)])
        tournament.blackouts = [Blackout(startAt: now.addingTimeInterval(-3600), endAt: now.addingTimeInterval(3 * 3600), reason: .tournament)]
        let other = Fixtures.facility(name: "Other Park", live: [LiveObservation(ageMinutes: 2, status: .allFull)])
        let set = engine.recommend([
            RecommendationInput(facility: tournament, travel: .init(minutes: 3, distanceMeters: 800, isEstimate: false), weather: nil),
            RecommendationInput(facility: other, travel: .init(minutes: 15, distanceMeters: 9000, isEstimate: false), weather: nil),
        ], prefs: .init(), now: now)
        XCTAssertEqual(set.picks.first?.facility.name, "Other Park")
        let t = set.notAvailable.first { $0.facility.name == "Tournament Park" }!
        XCTAssertEqual(t.eligibility.status, .unavailable)
        XCTAssertTrue(t.eligibility.reason!.hasPrefix("Tournament — public play unavailable until"))
    }

    func testResidentOnlyIsRestrictedUnlessUserHasAccess() {
        let f = Fixtures.facility(access: .residentGuestAllowed)
        let r1 = engine.evaluate(.init(facility: f, travel: nil, weather: nil), prefs: .init(), now: now)
        XCTAssertEqual(r1.eligibility.status, .restricted)
        let r2 = engine.evaluate(.init(facility: f, travel: nil, weather: nil),
                                 prefs: .init(accessGrantedFacilityIDs: [f.id]), now: now)
        XCTAssertEqual(r2.eligibility.status, .eligible)
    }

    func testWetCourtsUnavailable() {
        var f = Fixtures.facility()
        f.surface = SurfaceSummary(condition: .wet, ageMinutes: 20, reportCount: 2, confidence: 0.8)
        let r = engine.evaluate(.init(facility: f, travel: nil, weather: nil), prefs: .init(), now: now)
        XCTAssertEqual(r.eligibility.reason, "Courts currently wet")
    }

    func testSingleClosureReportWarnsButMultipleExclude() {
        var f = Fixtures.facility()
        f.overrides = [OperationalOverride(kind: .lockedGates, startsAt: now.addingTimeInterval(-600), expiresAt: now.addingTimeInterval(3600), reportCount: 1, confidence: 0.4)]
        var r = engine.evaluate(.init(facility: f, travel: nil, weather: nil), prefs: .init(), now: now)
        XCTAssertEqual(r.eligibility.status, .eligible)
        XCTAssertTrue(r.warnings.contains("Gates reported locked"))
        f.overrides[0].reportCount = 2
        r = engine.evaluate(.init(facility: f, travel: nil, weather: nil), prefs: .init(), now: now)
        XCTAssertEqual(r.eligibility.status, .unavailable)
    }

    func testClosedHoursShowsNextOpening() {
        let f = Fixtures.facility(hours: [FacilityHours(dayOfWeek: 3, opens: "07:00", closes: "12:00"),
                                          FacilityHours(dayOfWeek: 4, opens: "07:00", closes: "21:00")])
        let r = engine.evaluate(.init(facility: f, travel: nil, weather: nil), prefs: .init(), now: now)
        XCTAssertEqual(r.eligibility.issue, .closedHours)
        XCTAssertNotNil(r.eligibility.until)
    }

    func testLowConfidenceShortWaitDoesNotDominate() {
        // A: no data (prior, low confidence) but marginally closer. B: verified live "courts open".
        let a = Fixtures.facility(name: "A")
        let b = Fixtures.facility(name: "B", live: [LiveObservation(ageMinutes: 2, status: .courtsOpen),
                                                   LiveObservation(ageMinutes: 6, status: .courtsOpen),
                                                   LiveObservation(ageMinutes: 9, status: .courtsOpen)])
        let set = engine.recommend([
            .init(facility: a, travel: .init(minutes: 8, distanceMeters: 4000, isEstimate: false), weather: nil),
            .init(facility: b, travel: .init(minutes: 10, distanceMeters: 5000, isEstimate: false), weather: nil),
        ], prefs: .init(), now: now)
        XCTAssertEqual(set.ranked.first?.facility.name, "B")
    }

    func testFreeOnlyPreferenceExcludesPaidFromPicksButStillShowsIt() {
        let paid = Fixtures.facility(name: "Club", cost: .dayPass)
        let free = Fixtures.facility(name: "Park")
        let set = engine.recommend([
            .init(facility: paid, travel: .init(minutes: 3, distanceMeters: 1000, isEstimate: false), weather: nil),
            .init(facility: free, travel: .init(minutes: 20, distanceMeters: 15000, isEstimate: false), weather: nil),
        ], prefs: .init(costPreference: .freeOnly), now: now)
        XCTAssertFalse(set.picks.contains { $0.facility.name == "Club" })
        XCTAssertTrue(set.ranked.contains { $0.facility.name == "Club" })
    }

    func testPaidFasterOptionAndBestFreeBothSurfaced() {
        var club = Fixtures.facility(name: "Indoor Club", cost: .dayPass, indoor: .indoor,
                                     live: [LiveObservation(ageMinutes: 2, status: .courtsOpen), LiveObservation(ageMinutes: 4, status: .courtsOpen),
                                            LiveObservation(ageMinutes: 5, status: .courtsOpen)])
        club.cost.dayPassPrice = 15
        club.access.reservationAvailable = true
        let park = Fixtures.facility(name: "Hanson", live: [LiveObservation(ageMinutes: 2, status: .allFull), LiveObservation(ageMinutes: 5, status: .allFull),
                                                            LiveObservation(ageMinutes: 7, status: .allFull)])
        let set = engine.recommend([
            .init(facility: club, travel: .init(minutes: 7, distanceMeters: 4000, isEstimate: false), weather: nil),
            .init(facility: park, travel: .init(minutes: 11, distanceMeters: 7000, isEstimate: false), weather: nil),
        ], prefs: .init(costPreference: .includePaid), now: now)
        let clubRec = set.picks.first { $0.facility.name == "Indoor Club" }
        let parkRec = set.picks.first { $0.facility.name == "Hanson" }
        XCTAssertTrue(clubRec?.badges.contains(.fastest) == true)
        XCTAssertTrue(parkRec?.badges.contains(.bestFree) == true)
        XCTAssertTrue(clubRec!.explanation.contains("$15"))
    }

    func testSortModes() {
        let near = Fixtures.facility(name: "Near", pickleball: 2)
        let big = Fixtures.facility(name: "Big", pickleball: 12)
        let inputs: [RecommendationInput] = [
            .init(facility: near, travel: .init(minutes: 4, distanceMeters: 1000, isEstimate: false), weather: nil),
            .init(facility: big, travel: .init(minutes: 14, distanceMeters: 9000, isEstimate: false), weather: nil),
        ]
        XCTAssertEqual(engine.recommend(inputs, prefs: .init(), now: now, mode: .closest).ranked.first?.facility.name, "Near")
        XCTAssertEqual(engine.recommend(inputs, prefs: .init(), now: now, mode: .mostCourts).ranked.first?.facility.name, "Big")
    }

    func testExplanationIsHumanReadable() {
        let f = Fixtures.facility(live: [LiveObservation(ageMinutes: 1, status: .courtsOpen)],
                                  skill: Fixtures.skill([(.b30_35, 10), (.b35_40, 10), (.b40_45, 5)]))
        let r = engine.evaluate(.init(facility: f, travel: .init(minutes: 8, distanceMeters: 4000, isEstimate: false), weather: nil),
                                prefs: .init(skill: .b35_40), now: now)
        XCTAssertTrue(r.explanation.hasPrefix("Good match for your 3.5 level."))
        XCTAssertTrue(r.explanation.contains("Free public access."))
        XCTAssertTrue(r.explanation.contains("Estimated playing in"))
    }
}

final class PlayerFitTests: XCTestCase {
    let fit = PlayerFitEvaluator()

    func testTypicalRange() {
        let s = Fixtures.skill([(.b30_35, 10), (.b35_40, 12), (.b40_45, 5), (.b25_30, 1)])
        XCTAssertEqual(s.typicalLabel, "3.0–4.5")
        XCTAssertEqual(s.confidence, .high)
    }

    func testStrongerFacilityIsSoftTradeoffNotExclusion() {
        let f = Fixtures.facility(skill: Fixtures.skill([(.b40_45, 10), (.b45plus, 10)]))
        let r = fit.evaluate(f, prefs: .init(skill: .b30_35))
        XCTAssertEqual(r.skillFit, .mismatch)
        XCTAssertEqual(r.tradeoff?.hasPrefix("Play here tends to be stronger"), true)
        XCTAssertGreaterThan(r.penaltyMinutes, 0)
    }

    func testUnknownSkillNoPenalty() {
        let f = Fixtures.facility(skill: Fixtures.skill([(.b30_35, 10)]))
        XCTAssertEqual(fit.evaluate(f, prefs: .init()).penaltyMinutes, 0)
    }

    func testFewObservationsNotUsed() {
        let f = Fixtures.facility(skill: Fixtures.skill([(.b45plus, 2)], count: 2))
        XCTAssertEqual(fit.evaluate(f, prefs: .init(skill: .beginner)).skillFit, .unknown)
    }
}

final class WeatherTests: XCTestCase {
    func testWindCategoriesUseGusts() {
        let t = WindThresholds()
        XCTAssertEqual(WeatherAssessor.windCategory(windMph: 5, gustMph: nil, thresholds: t).0, .calm)
        XCTAssertEqual(WeatherAssessor.windCategory(windMph: 9, gustMph: nil, thresholds: t).0, .breezy)
        XCTAssertEqual(WeatherAssessor.windCategory(windMph: 10, gustMph: 24, thresholds: t).0, .windy)
        XCTAssertEqual(WeatherAssessor.windCategory(windMph: 17, gustMph: 30, thresholds: t).0, .veryWindy)
    }
    func testWindyHeadline() {
        let a = WeatherAssessor.assess(WeatherConditions(temperatureF: 72, windMph: 17, gustMph: 24), isOutdoor: true)
        XCTAssertEqual(a.headline, "Wind may noticeably affect play")
        XCTAssertEqual(WeatherAssessor.assess(WeatherConditions(temperatureF: 72, windMph: 30), isOutdoor: false).impact, .none)
    }
}
