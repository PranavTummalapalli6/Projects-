import XCTest
import PickleCore
@testable import PickleballApp

final class DemoBackendTests: XCTestCase {
    func testNearbyOnlyReturnsFacilitiesInBox() async throws {
        let far = GeoPoint(latitude: 37.32, longitude: -122.04)
        let backend = DemoBackend(facilities: [TestData.facility("Near"), TestData.facility("Far", at: far)])
        let box = GeoBoundingBox(center: TestData.laurel, latitudeDelta: 0.1, longitudeDelta: 0.1)
        let result = try await backend.nearby(in: box, timeZone: "UTC")
        XCTAssertEqual(result.map(\.name), ["Near"])
    }

    func testLiveReportRequiresPresenceAndThenAppearsInLiveSignals() async throws {
        let f = TestData.facility()
        let backend = DemoBackend(facilities: [f])
        let far = TestData.fix(at: GeoPoint(latitude: 38.70, longitude: -77.30))
        let rejected = try await backend.submitLiveReport(LiveReportRequest(facilityID: f.id, kind: .occupancy, value: "all_full", fix: far))
        XCTAssertFalse(rejected.accepted)
        XCTAssertEqual(rejected.reason, "not_nearby")

        let near = TestData.fix(at: TestData.laurel)
        let accepted = try await backend.submitLiveReport(LiveReportRequest(facilityID: f.id, kind: .occupancy, value: "players_waiting", fix: near))
        XCTAssertTrue(accepted.accepted)
        XCTAssertNotNil(accepted.insightsUntil, "a verified live report grants temporary live insights")

        let box = GeoBoundingBox(center: TestData.laurel, latitudeDelta: 0.1, longitudeDelta: 0.1)
        let hydrated = try await backend.nearby(in: box, timeZone: "UTC").first!
        XCTAssertTrue(hydrated.live?.observations.contains { $0.status == .playersWaiting } == true)
    }

    func testAddCourtDetectsDuplicatesThenAllowsGenuinelyNewCourt() async throws {
        let existing = TestData.facility("Hanson Regional Park")
        let backend = DemoBackend(facilities: [existing])
        var draft = FacilitySubmissionDraft(location: GeoPoint(latitude: TestData.laurel.latitude + 0.0002, longitude: TestData.laurel.longitude))
        draft.name = "Hanson Park"
        let dup = try await backend.submitFacility(draft, forceNew: false, userFix: nil)
        XCTAssertEqual(dup.status, "duplicate_candidates")
        XCTAssertEqual(dup.candidates?.first?.facilityId, existing.id)

        // Within 30 m even "force new" is refused — no stacked markers for the same park.
        let forced = try await backend.submitFacility(draft, forceNew: true, userFix: nil)
        XCTAssertEqual(forced.status, "duplicate_candidates")

        var elsewhere = FacilitySubmissionDraft(location: GeoPoint(latitude: 38.80, longitude: -77.40))
        elsewhere.courtCount = 2
        let created = try await backend.submitFacility(elsewhere, forceNew: false, userFix: nil)
        XCTAssertEqual(created.status, "created")
        XCTAssertEqual(created.existenceStatus, .communityReported)
    }

    func testBundledDemoDataDecodes() async throws {
        let backend = DemoBackend(bundle: Bundle(for: AppEnvironment.self))
        let box = GeoBoundingBox(center: GeoPoint(latitude: 38.85, longitude: -77.30), latitudeDelta: 0.3, longitudeDelta: 0.3)
        let list = try await backend.nearby(in: box, timeZone: "UTC")
        XCTAssertGreaterThanOrEqual(list.count, 8)
        XCTAssertTrue(list.contains { $0.access.accessType == .residentGuestAllowed })
    }
}

final class FacilityServiceTests: XCTestCase {
    func testCameraMovesInsidePaddedBoxDoNotRefetch() async throws {
        let repo = CountingFacilityRepository(facilities: [TestData.facility()])
        let service = FacilityService(repository: repo, store: TestData.tempStore())
        let box = GeoBoundingBox(center: TestData.laurel, latitudeDelta: 0.1, longitudeDelta: 0.1)
        _ = try await service.facilities(visible: box)
        let nudged = GeoBoundingBox(center: GeoPoint(latitude: 38.85, longitude: -77.31), latitudeDelta: 0.1, longitudeDelta: 0.1)
        let second = try await service.facilities(visible: nudged)
        let calls = await repo.nearbyCalls
        XCTAssertEqual(calls, 1)
        XCTAssertTrue(second.fromCache)
    }

    func testForceAndLargeMovesRefetch() async throws {
        let repo = CountingFacilityRepository(facilities: [])
        let service = FacilityService(repository: repo, store: TestData.tempStore())
        let box = GeoBoundingBox(center: TestData.laurel, latitudeDelta: 0.1, longitudeDelta: 0.1)
        _ = try await service.facilities(visible: box)
        _ = try await service.facilities(visible: box, force: true)
        _ = try await service.facilities(visible: GeoBoundingBox(center: GeoPoint(latitude: 40, longitude: -75), latitudeDelta: 0.1, longitudeDelta: 0.1))
        let calls = await repo.nearbyCalls
        XCTAssertEqual(calls, 3)
    }

    func testOfflineFallsBackToLastLoadedFacilities() async throws {
        let repo = CountingFacilityRepository(facilities: [TestData.facility()])
        let service = FacilityService(repository: repo, store: TestData.tempStore())
        let box = GeoBoundingBox(center: TestData.laurel, latitudeDelta: 0.1, longitudeDelta: 0.1)
        _ = try await service.facilities(visible: box)
        await repo.setFailure(.offline)
        let offline = try await service.facilities(visible: box, force: true)
        XCTAssertEqual(offline.facilities.count, 1)
        XCTAssertTrue(offline.fromCache)
    }

    func testRegionDiscoveryIsThrottledPerCell() async {
        let repo = CountingFacilityRepository(facilities: [])
        let service = FacilityService(repository: repo, store: TestData.tempStore())
        _ = await service.discoverIfEmpty(center: TestData.laurel)
        _ = await service.discoverIfEmpty(center: GeoPoint(latitude: 38.8470, longitude: -77.3070))
        let calls = await repo.discoveryCalls
        XCTAssertEqual(calls, 1, "same geohash cell must not trigger repeated backfills")
    }
}

final class FilterStateTests: XCTestCase {
    func testStaticFacets() {
        var filters = FilterState()
        var f = TestData.facility()
        XCTAssertTrue(filters.includes(f, origin: nil))
        filters.freeOnly = true
        f.cost.costType = .dayPass
        XCTAssertFalse(filters.includes(f, origin: nil))
        filters = FilterState(maxMiles: 2)
        XCTAssertFalse(filters.includes(TestData.facility(), origin: GeoPoint(latitude: 38.95, longitude: -77.30)))
        filters = FilterState(minCourts: 8)
        XCTAssertFalse(filters.includes(TestData.facility(), origin: nil))
        XCTAssertEqual(filters.activeCount, 1)
    }

    func testFiltersRoundTripPersistence() throws {
        let filters = FilterState(likelyAvailableOnly: true, setting: .indoor, maxMiles: 5)
        let data = try JSONEncoder().encode(filters)
        XCTAssertEqual(try JSONDecoder().decode(FilterState.self, from: data), filters)
    }
}

final class EncodingTests: XCTestCase {
    func testRPCParamsKeepExplicitNulls() throws {
        let params: RPCParams = ["p_name": .of(nil as String?), "p_count": .of(3), "p_ok": .bool(true)]
        let json = String(decoding: try JSONEncoder().encode(params), as: UTF8.self)
        XCTAssertTrue(json.contains("\"p_name\":null"))
        XCTAssertTrue(json.contains("\"p_count\":3"))
    }

    func testPhotoPreparationResizesAndStripsMetadata() throws {
        let image = UIGraphicsImageRenderer(size: CGSize(width: 3000, height: 2000)).image { ctx in
            UIColor.systemGreen.setFill(); ctx.fill(CGRect(x: 0, y: 0, width: 3000, height: 2000))
        }
        let prepared = try XCTUnwrap(SubmissionService.preparePhoto(try XCTUnwrap(image.pngData())))
        XCTAssertLessThanOrEqual(max(prepared.width, prepared.height), 1600)
        let source = try XCTUnwrap(CGImageSourceCreateWithData(prepared.jpeg as CFData, nil))
        let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        XCTAssertNil(props?[kCGImagePropertyGPSDictionary], "photos must not carry GPS metadata")
    }
}
