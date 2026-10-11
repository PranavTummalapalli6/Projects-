import Foundation
import PickleCore

/// Read access to facilities. Views never call these directly — services do.
protocol FacilityRepository: Sendable {
    func nearby(in box: GeoBoundingBox, timeZone: String) async throws -> [Facility]
    func detail(id: UUID, timeZone: String) async throws -> FacilityDetail?
    func search(_ query: String, near: GeoPoint?, timeZone: String) async throws -> [Facility]
    func requestRegionDiscovery(at point: GeoPoint) async throws -> RegionDiscoveryResult
}

protocol ReportRepository: Sendable {
    func submitLiveReport(_ request: LiveReportRequest) async throws -> LiveReportResult
    func reportIssue(facilityID: UUID, kind: IssueKind, note: String?, fix: LocationFix?) async throws -> LiveReportResult
    func confirmFacility(id: UUID, exists: Bool, fix: LocationFix?) async throws -> ConfirmationResult
}

protocol SubmissionRepository: Sendable {
    func findDuplicates(at point: GeoPoint, name: String?) async throws -> [DuplicateCandidateDTO]
    func submitFacility(_ draft: FacilitySubmissionDraft, forceNew: Bool, userFix: LocationFix?) async throws -> SubmissionResult
    func suggestEdit(facilityID: UUID, type: EditType, proposed: [String: JSONValue], note: String?, fix: LocationFix?) async throws -> EditResult
    func uploadPhoto(jpeg: Data, facilityID: UUID?, submissionID: UUID?, width: Int, height: Int) async throws
}

protocol ProfileRepository: Sendable {
    func contributorStatus() async throws -> ContributorStatus
    func saveProfile(_ prefs: UserPreferences, passiveVisits: Bool) async throws
    func recordVisit(_ visit: VisitRecord) async throws
    func logEvent(_ name: String, facilityID: UUID?, props: [String: JSONValue]) async
}

/// Bundle handed to services by `AppEnvironment`.
struct Backend: Sendable {
    var facilities: FacilityRepository
    var reports: ReportRepository
    var submissions: SubmissionRepository
    var profile: ProfileRepository
    var isDemo: Bool
}
