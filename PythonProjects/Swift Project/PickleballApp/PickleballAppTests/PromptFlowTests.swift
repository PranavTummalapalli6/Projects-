import CoreLocation
import XCTest
import PickleCore
@testable import PickleballApp

/// Integration of VisitService + ReportService + PromptPolicy (report fatigue rules end to end).
@MainActor
final class PromptFlowTests: XCTestCase {
    private func makeServices(dwell: TimeInterval = 0) -> (VisitService, ReportService, RecordingReportRepository) {
        let store = TestData.tempStore()
        let profile = SilentProfileRepository()
        let location = LocationService(fixedLocation: CLLocation(latitude: TestData.laurel.latitude, longitude: TestData.laurel.longitude))
        let repo = RecordingReportRepository()
        let reports = ReportService(repository: repo, location: location, contributor: ContributorStore(profile: profile),
                                    store: store, analytics: profile, isProduction: false, allowsSimulatedPresence: true)
        let prefs = PreferencesStore(store: store, profile: profile)
        return (VisitService(reports: reports, profile: profile, prefs: prefs, arrivalDwell: dwell), reports, repo)
    }

    private func recommendation(for f: Facility) -> FacilityRecommendation {
        RecommendationEngine().evaluate(RecommendationInput(facility: f, travel: nil, weather: nil), prefs: .init(), now: Date())
    }

    func testArrivalAsksOneContextualQuestionPerVisit() {
        let (visits, _, _) = makeServices()
        let f = TestData.facility(play: .paddleStack)
        visits.update(recommendations: [recommendation(for: f)])
        visits.handle(fix: TestData.fix(at: TestData.laurel))
        XCTAssertEqual(visits.activePrompt?.kind, .paddleWait)

        visits.dismissPrompt()
        visits.evaluatePrompt()
        XCTAssertNil(visits.activePrompt, "never ask twice in the same visit")
    }

    func testUnverifiedFacilityAsksIfItExists() {
        let (visits, _, _) = makeServices()
        let f = TestData.facility(status: .communityReported)
        visits.update(recommendations: [recommendation(for: f)])
        visits.handle(fix: TestData.fix(at: TestData.laurel))
        XCTAssertEqual(visits.activePrompt?.kind, .confirmExists)
    }

    func testNoPromptWhenFarAwayOrBeforeDwell() {
        let (visits, _, _) = makeServices(dwell: 60)
        let f = TestData.facility()
        visits.update(recommendations: [recommendation(for: f)])
        visits.handle(fix: TestData.fix(at: GeoPoint(latitude: 38.90, longitude: -77.30)))
        XCTAssertNil(visits.currentFacility)
        visits.handle(fix: TestData.fix(at: TestData.laurel))
        XCTAssertNil(visits.activePrompt, "arrival requires a short dwell")
        visits.handle(fix: TestData.fix(at: TestData.laurel), now: Date().addingTimeInterval(61))
        XCTAssertNotNil(visits.activePrompt)
    }

    func testAnsweringStartsCooldownAndSendsFixForServerVerification() async throws {
        let (_, reports, repo) = makeServices()
        let f = TestData.facility()
        let result = try await reports.submit(.occupancy, value: "courts_open", at: f, promptKind: .howBusy)
        XCTAssertTrue(result.accepted)
        let sent = await repo.requests
        XCTAssertEqual(sent.count, 1)
        XCTAssertNotNil(sent.first?.fix, "the server re-verifies location; the client must send the fix")
        let ctx = PromptContext(facility: f, visitID: UUID(), isNearby: true, prediction: nil, weather: nil, now: Date())
        XCTAssertNil(reports.decidePrompt(ctx).kind, "no prompt right after the user reported here")
    }

    func testLocationGateUsesDistance() {
        let (_, reports, _) = makeServices()
        XCTAssertTrue(reports.locationCheck(for: TestData.facility()).allowsLiveReport)
        let far = TestData.facility(at: GeoPoint(latitude: 38.70, longitude: -77.30))
        XCTAssertFalse(reports.locationCheck(for: far).allowsLiveReport)
        reports.simulatedPresence = far.id
        XCTAssertTrue(reports.locationCheck(for: far).allowsLiveReport)
    }
}
