import XCTest
@testable import PickleCore

final class GeoTests: XCTestCase {
    func testHaversine() {
        let dc = GeoPoint(latitude: 38.9072, longitude: -77.0369), nyc = GeoPoint(latitude: 40.7128, longitude: -74.0060)
        XCTAssertEqual(GeoMath.distanceMeters(dc, nyc) / 1000, 328, accuracy: 3)
    }
    func testGeohashKnownValue() {
        XCTAssertEqual(GeoMath.geohash(GeoPoint(latitude: 57.64911, longitude: 10.40744), precision: 11), "u4pruydqqvj")
        XCTAssertEqual(GeoMath.geohash(GeoPoint(latitude: 38.85, longitude: -77.30)).count, 4)
    }
    func testBoundingBoxPaddingAndContainment() {
        let box = GeoBoundingBox(center: GeoPoint(latitude: 38.85, longitude: -77.3), latitudeDelta: 0.1, longitudeDelta: 0.1)
        let padded = box.padded(by: 0.25)
        XCTAssertTrue(padded.contains(box)); XCTAssertFalse(box.contains(padded))
        XCTAssertEqual(padded.latitudeDelta, 0.15, accuracy: 1e-9)
    }
    func testClustering() {
        let box = GeoBoundingBox(center: GeoPoint(latitude: 38.85, longitude: -77.3), latitudeDelta: 0.5, longitudeDelta: 0.5)
        let items = [ClusterItem(id: 1, point: GeoPoint(latitude: 38.850, longitude: -77.300)),
                     ClusterItem(id: 2, point: GeoPoint(latitude: 38.851, longitude: -77.301)),
                     ClusterItem(id: 3, point: GeoPoint(latitude: 38.99, longitude: -77.45))]
        let clusters = FacilityClusterer.cluster(items, visible: box)
        XCTAssertEqual(clusters.count, 2)
        XCTAssertEqual(clusters.map(\.memberIDs.count).sorted(), [1, 2])
        let zoomed = GeoBoundingBox(center: GeoPoint(latitude: 38.85, longitude: -77.3), latitudeDelta: 0.002, longitudeDelta: 0.002)
        XCTAssertEqual(FacilityClusterer.cluster(items, visible: zoomed).count, 3)
    }
}

final class CodingTests: XCTestCase {
    func testDecodesServerPayloadAndToleratesUnknownEnums() throws {
        let json = """
        [{"id":"9a7f3c1e-5b2d-4e8a-9c1f-1234567890ab","name":"Hanson Regional Park","latitude":38.85,"longitude":-77.3,
          "court_type":"some_future_type","indoor_outdoor":"outdoor","play_system":"paddle_stack",
          "existence_status":"verified","existence_confidence":0.95,
          "access":{"access_type":"public_walk_on","verification_status":"verified","confidence":0.9,"last_verified_at":"2026-09-01 10:00:00.123456+00"},
          "cost":{"cost_type":"free"},
          "hours":[{"day_of_week":3,"opens":"07:00","closes":"22:00"}],
          "blackouts":[{"id":"9a7f3c1e-5b2d-4e8a-9c1f-1234567890ac","start_at":"2026-10-10T08:00:00Z","end_at":"2026-10-10T18:00:00Z","reason":"tournament","verification_status":"verified","confidence":0.9}],
          "live":{"observations":[{"kind":"occupancy","age_minutes":3.2,"status":"all_full","weight":0.9,"location_verified":true}]},
          "skill":{"bands":[{"band":"3.0-3.5","weight":4.5}],"observation_count":9,"newest_days_ago":2}}]
        """
        let facilities = try JSONCoding.decoder.decode([Facility].self, from: Data(json.utf8))
        let f = try XCTUnwrap(facilities.first)
        XCTAssertEqual(f.courtType, .unknown)
        XCTAssertEqual(f.playSystem, .paddleStack)
        XCTAssertNotNil(f.access.lastVerifiedAt)
        XCTAssertEqual(f.blackouts.first?.reason, .tournament)
        XCTAssertEqual(f.live?.observations.first?.status, .allFull)
        XCTAssertTrue(f.overrides.isEmpty)
    }
}
