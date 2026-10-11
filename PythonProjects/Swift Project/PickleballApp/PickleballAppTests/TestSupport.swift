import CoreLocation
import Foundation
import PickleCore
@testable import PickleballApp

enum TestData {
    static let laurel = GeoPoint(latitude: 38.8462, longitude: -77.3064)

    static func facility(_ name: String = "Test Park", at p: GeoPoint = laurel, play: PlaySystem = .stayUntilFinished,
                         status: VerificationStatus = .verified) -> Facility {
        Facility(name: name, latitude: p.latitude, longitude: p.longitude, timeZone: "UTC", totalPhysicalCourts: 4,
                 defaultPickleballCourts: 4, courtType: .dedicatedPickleball, indoorOutdoor: .outdoor, hasLights: true,
                 playSystem: play, existenceStatus: status, access: FacilityAccess(accessType: .publicWalkOn),
                 cost: FacilityCost(costType: .free))
    }

    static func fix(at p: GeoPoint, accuracy: Double = 10) -> LocationFix {
        LocationFix(point: p, horizontalAccuracy: accuracy, timestamp: Date())
    }

    static func tempStore() -> LocalStore {
        LocalStore(directory: FileManager.default.temporaryDirectory.appending(path: "PickleballTests-\(UUID().uuidString)"))
    }
}

/// Counts calls so caching behaviour can be asserted.
actor CountingFacilityRepository: FacilityRepository {
    var nearbyCalls = 0
    var discoveryCalls = 0
    var facilities: [Facility]
    var failWith: APIError?

    init(facilities: [Facility]) { self.facilities = facilities }

    func setFailure(_ e: APIError?) { failWith = e }

    func nearby(in box: GeoBoundingBox, timeZone: String) async throws -> [Facility] {
        nearbyCalls += 1
        if let failWith { throw failWith }
        return facilities.filter { box.contains($0.coordinate) }
    }
    func detail(id: UUID, timeZone: String) async throws -> FacilityDetail? { nil }
    func search(_ query: String, near: GeoPoint?, timeZone: String) async throws -> [Facility] { [] }
    func requestRegionDiscovery(at point: GeoPoint) async throws -> RegionDiscoveryResult {
        discoveryCalls += 1
        return RegionDiscoveryResult(geohash: nil, action: "fresh", facilityCount: 0, inserted: 0)
    }
}

actor RecordingReportRepository: ReportRepository {
    var requests: [LiveReportRequest] = []
    func submitLiveReport(_ request: LiveReportRequest) async throws -> LiveReportResult {
        requests.append(request)
        return LiveReportResult(accepted: true, locationVerified: true, insightsUntil: Date().addingTimeInterval(7 * 86400))
    }
    func reportIssue(facilityID: UUID, kind: IssueKind, note: String?, fix: LocationFix?) async throws -> LiveReportResult {
        LiveReportResult(accepted: true)
    }
    func confirmFacility(id: UUID, exists: Bool, fix: LocationFix?) async throws -> ConfirmationResult {
        ConfirmationResult(accepted: true, existenceStatus: .partiallyVerified)
    }
}

struct SilentProfileRepository: ProfileRepository {
    func contributorStatus() async throws -> ContributorStatus { .unknown }
    func saveProfile(_ prefs: UserPreferences, passiveVisits: Bool) async throws {}
    func recordVisit(_ visit: VisitRecord) async throws {}
    func logEvent(_ name: String, facilityID: UUID?, props: [String: JSONValue]) async {}
}
