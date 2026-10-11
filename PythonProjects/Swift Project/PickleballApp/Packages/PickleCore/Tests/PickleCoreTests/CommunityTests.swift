import XCTest
@testable import PickleCore

final class DuplicateDetectionTests: XCTestCase {
    let detector = DuplicateDetector()
    let park = GeoPoint(latitude: 38.8500, longitude: -77.3000)
    func offset(_ meters: Double) -> GeoPoint { GeoPoint(latitude: park.latitude + meters / 111_000, longitude: park.longitude) }

    func testNormalization() {
        XCTAssertEqual(DuplicateDetector.normalize("Hanson Regional Pk. Pickleball Courts"), "hanson regional park")
        XCTAssertEqual(DuplicateDetector.similarity("Hanson Regional Park", "hanson regional pk"), 1)
    }
    func testSameSpotIsDuplicateRegardlessOfName() {
        let id = UUID()
        let c = detector.candidates(name: "My Courts", location: offset(30), existing: [(id, "Hanson Regional Park", park, nil)])
        XCTAssertEqual(c.first?.facilityID, id)
    }
    func testNearbySimilarNameIsDuplicate() {
        let c = detector.candidates(name: "Hanson Park", location: offset(180), existing: [(UUID(), "Hanson Regional Park", park, nil)])
        XCTAssertEqual(c.count, 1)
    }
    func testNearbyDifferentNameIsNotDuplicate() {
        let c = detector.candidates(name: "Oak Ridge HOA Courts", location: offset(200), existing: [(UUID(), "Hanson Regional Park", park, nil)])
        XCTAssertTrue(c.isEmpty)
    }
    func testFarAwayNeverDuplicate() {
        let c = detector.candidates(name: "Hanson Regional Park", location: offset(2000), existing: [(UUID(), "Hanson Regional Park", park, nil)])
        XCTAssertTrue(c.isEmpty)
    }
    func testJaroWinklerKnownValue() {
        XCTAssertEqual(DuplicateDetector.jaroWinkler("martha", "marhta"), 0.961, accuracy: 0.001)
    }
}

final class LocationVerificationTests: XCTestCase {
    let verifier = LocationVerifier()
    let facility = GeoPoint(latitude: 38.85, longitude: -77.30)
    let now = Date()

    func fix(meters: Double, accuracy: Double = 10, age: TimeInterval = 5) -> LocationFix {
        LocationFix(point: GeoPoint(latitude: 38.85 + meters / 111_000, longitude: -77.30), horizontalAccuracy: accuracy,
                    timestamp: now.addingTimeInterval(-age))
    }
    func testNearbyAllowed() { XCTAssertTrue(verifier.check(fix(meters: 100), facility: facility, now: now).allowsLiveReport) }
    func testTwelveMilesAwayRejected() {
        if case .tooFar = verifier.check(fix(meters: 19_000), facility: facility, now: now) {} else { XCTFail() }
    }
    func testImpreciseAndStale() {
        XCTAssertEqual(verifier.check(fix(meters: 10, accuracy: 500), facility: facility, now: now), .imprecise)
        XCTAssertEqual(verifier.check(fix(meters: 10, age: 600), facility: facility, now: now), .stale)
        XCTAssertEqual(verifier.check(nil, facility: facility, now: now), .unavailable)
    }
    func testAccuracyAllowanceIsCapped() {
        XCTAssertTrue(verifier.check(fix(meters: 300, accuracy: 60), facility: facility, now: now).allowsLiveReport)
        XCTAssertFalse(verifier.check(fix(meters: 340, accuracy: 140), facility: facility, now: now).allowsLiveReport)
    }
}

final class IntegrityTests: XCTestCase {
    let now = Date()
    let a = GeoPoint(latitude: 38.85, longitude: -77.30)
    let b = GeoPoint(latitude: 34.05, longitude: -118.24) // Los Angeles

    func fix(_ p: GeoPoint, simulated: Bool = false) -> LocationFix {
        LocationFix(point: p, horizontalAccuracy: 10, timestamp: now, isSimulatedBySoftware: simulated)
    }

    func testCleanReportScoresOne() {
        let r = IntegrityRiskEvaluator(isProduction: true).assess(fix: fix(a), facilityID: UUID(), facilityLocation: a, history: [], now: now)
        XCTAssertEqual(r.score, 1); XCTAssertTrue(r.flags.isEmpty)
    }
    func testSimulatedLocationDownweightedOnlyInProduction() {
        let prod = IntegrityRiskEvaluator(isProduction: true).assess(fix: fix(a, simulated: true), facilityID: UUID(), facilityLocation: a, history: [], now: now)
        let debug = IntegrityRiskEvaluator(isProduction: false).assess(fix: fix(a, simulated: true), facilityID: UUID(), facilityLocation: a, history: [], now: now)
        XCTAssertLessThan(prod.score, 0.5); XCTAssertEqual(debug.score, 1)
    }
    func testImpossibleTravel() {
        let history = [ReportHistoryEntry(facilityID: UUID(), facilityLocation: b, at: now.addingTimeInterval(-1800))]
        let r = IntegrityRiskEvaluator(isProduction: true).assess(fix: fix(a), facilityID: UUID(), facilityLocation: a, history: history, now: now)
        XCTAssertTrue(r.flags.contains(.impossibleTravel))
    }
    func testBurstAndManyFacilities() {
        let history = (0..<5).map { ReportHistoryEntry(facilityID: UUID(), facilityLocation: a, at: now.addingTimeInterval(Double(-$0 * 60))) }
        let r = IntegrityRiskEvaluator(isProduction: true).assess(fix: fix(a), facilityID: UUID(), facilityLocation: a, history: history, now: now)
        XCTAssertTrue(r.flags.contains(.burst)); XCTAssertTrue(r.flags.contains(.manyFacilities))
        XCTAssertLessThan(r.score, 0.3)
    }
}

final class PromptPolicyTests: XCTestCase {
    let policy = PromptPolicy()
    let now = Fixtures.wednesdayEvening

    func ctx(_ f: Facility, visit: UUID = UUID(), nearby: Bool = true, prediction: WaitPrediction? = nil,
             weather: WeatherAssessment? = nil, at: Date? = nil) -> PromptContext {
        PromptContext(facility: f, visitID: visit, isNearby: nearby, prediction: prediction, weather: weather, now: at ?? now)
    }

    func testContextualQuestionChoice() {
        XCTAssertEqual(policy.decide(ctx(Fixtures.facility()), state: .init()).kind, .howBusy)
        XCTAssertEqual(policy.decide(ctx(Fixtures.facility(play: .paddleStack)), state: .init()).kind, .paddleWait)
        var unverified = Fixtures.facility(); unverified.existenceStatus = .communityReported
        XCTAssertEqual(policy.decide(ctx(unverified), state: .init()).kind, .confirmExists)
        let rain = WeatherAssessor.assess(WeatherConditions(temperatureF: 60, windMph: 2, precipitationLast3hMm: 3), isOutdoor: true)
        XCTAssertEqual(policy.decide(ctx(Fixtures.facility(), weather: rain), state: .init()).kind, .courtSurface)
    }

    func testNotAskedWhenFarAway() {
        XCTAssertNil(policy.decide(ctx(Fixtures.facility(), nearby: false), state: .init()).kind)
    }

    func testOncePerVisit() {
        let f = Fixtures.facility(); let visit = UUID()
        var state = PromptState()
        policy.recordShown(&state, facilityID: f.id, visitID: visit, at: now.addingTimeInterval(-3600 * 4))
        state.lastPromptAt = nil
        XCTAssertNil(policy.decide(ctx(f, visit: visit), state: state).kind)
    }

    func testSkipsWhenFreshHighConfidenceDataExists() {
        let live = [LiveObservation(ageMinutes: 3, status: .courtsOpen), LiveObservation(ageMinutes: 5, status: .courtsOpen),
                    LiveObservation(ageMinutes: 6, status: .courtsOpen)]
        let f = Fixtures.facility(live: live)
        let p = WaitPredictor().predict(facility: f, now: now)
        XCTAssertEqual(p.confidence, .high)
        XCTAssertNil(policy.decide(ctx(f, prediction: p), state: .init()).kind)
    }

    func testCooldownAfterReporting() {
        let f = Fixtures.facility()
        var state = PromptState()
        policy.recordAnswered(&state, facilityID: f.id, kind: .howBusy, at: now.addingTimeInterval(-3600))
        XCTAssertNil(policy.decide(ctx(f), state: state).kind)
        XCTAssertNotNil(policy.decide(ctx(f, at: now.addingTimeInterval(3 * 3600)), state: state).kind)
    }

    func testDismissalBackoff() {
        let f = Fixtures.facility()
        var state = PromptState()
        policy.recordDismissed(&state, at: now)
        XCTAssertNil(state.backoffUntil)
        policy.recordDismissed(&state, at: now)
        XCTAssertNotNil(state.backoffUntil)
        XCTAssertNil(policy.decide(ctx(f, at: now.addingTimeInterval(86400)), state: state).kind)
        XCTAssertNotNil(policy.decide(ctx(f, at: now.addingTimeInterval(4 * 86400)), state: state).kind)
        policy.recordDismissed(&state, at: now); policy.recordDismissed(&state, at: now)
        XCTAssertGreaterThan(state.backoffUntil!, now.addingTimeInterval(13 * 86400))
        policy.recordAnswered(&state, facilityID: UUID(), kind: .howBusy, at: now)
        XCTAssertEqual(state.consecutiveDismissals, 0); XCTAssertNil(state.backoffUntil)
    }

    func testMinimumGapBetweenPrompts() {
        var state = PromptState()
        state.lastPromptAt = now.addingTimeInterval(-300)
        XCTAssertNil(policy.decide(ctx(Fixtures.facility()), state: state).kind)
    }
}

final class SubmissionValidationTests: XCTestCase {
    func testMinimalSubmissionIsValid() {
        XCTAssertTrue(SubmissionValidator.validate(FacilitySubmissionDraft(location: GeoPoint(latitude: 38.8, longitude: -77.3))).isEmpty)
    }
    func testInvalidInputs() {
        XCTAssertEqual(SubmissionValidator.validate(FacilitySubmissionDraft()), [.missingLocation])
        var d = FacilitySubmissionDraft(location: GeoPoint(latitude: 0, longitude: 0))
        d.courtCount = 99; d.name = "www.spam.example"
        let issues = SubmissionValidator.validate(d)
        XCTAssertTrue(issues.contains(.invalidLocation)); XCTAssertTrue(issues.contains(.courtCountOutOfRange)); XCTAssertTrue(issues.contains(.nameLooksLikeSpam))
    }
}
