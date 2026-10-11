import Foundation
import PickleCore

/// Production repositories backed by Supabase RPCs (see supabase/migrations/…_functions.sql).
struct SupabaseFacilityRepository: FacilityRepository {
    let client: SupabaseClient

    func nearby(in box: GeoBoundingBox, timeZone: String) async throws -> [Facility] {
        try await client.rpc("nearby_facilities", [
            "p_min_lat": .number(box.minLatitude), "p_min_lng": .number(box.minLongitude),
            "p_max_lat": .number(box.maxLatitude), "p_max_lng": .number(box.maxLongitude),
            "p_limit": .int(200), "p_time_zone": .string(timeZone),
        ])
    }

    func detail(id: UUID, timeZone: String) async throws -> FacilityDetail? {
        try await client.rpc("facility_detail", ["p_facility_id": .of(id), "p_time_zone": .string(timeZone)])
    }

    func search(_ query: String, near: GeoPoint?, timeZone: String) async throws -> [Facility] {
        try await client.rpc("search_facilities", [
            "p_query": .string(query), "p_latitude": .of(near?.latitude), "p_longitude": .of(near?.longitude),
            "p_time_zone": .string(timeZone),
        ])
    }

    func requestRegionDiscovery(at point: GeoPoint) async throws -> RegionDiscoveryResult {
        try await client.invokeFunction("region-discovery", body: [
            "latitude": .number(point.latitude), "longitude": .number(point.longitude),
        ])
    }
}

/// Location parameters shared by every write RPC. Coordinates are sent once, for verification;
/// the server stores only distance + accuracy.
private func locationParams(_ fix: LocationFix?, prefix: String = "p_") -> RPCParams {
    guard let fix else { return [:] }
    return [
        "\(prefix)latitude": .number(fix.point.latitude),
        "\(prefix)longitude": .number(fix.point.longitude),
        "\(prefix)accuracy_m": .number(fix.horizontalAccuracy),
    ]
}

private func fixExtras(_ fix: LocationFix?) -> RPCParams {
    guard let fix else { return [:] }
    return ["p_fix_age_seconds": .number(max(0, Date().timeIntervalSince(fix.timestamp))),
            "p_is_simulated": .bool(fix.isSimulatedBySoftware)]
}

struct SupabaseReportRepository: ReportRepository {
    let client: SupabaseClient

    func submitLiveReport(_ r: LiveReportRequest) async throws -> LiveReportResult {
        var params: RPCParams = [
            "p_facility_id": .of(r.facilityID), "p_kind": .string(r.kind.rawValue), "p_value": .of(r.value),
            "p_count": .of(r.count), "p_groups_waiting": .of(r.groupsWaiting), "p_client_report_id": .of(r.clientReportID),
        ]
        params.merge(locationParams(r.fix)) { $1 }
        params.merge(fixExtras(r.fix)) { $1 }
        return try await client.rpc("submit_live_report", params, requiresUser: true)
    }

    func reportIssue(facilityID: UUID, kind: IssueKind, note: String?, fix: LocationFix?) async throws -> LiveReportResult {
        var params: RPCParams = ["p_facility_id": .of(facilityID), "p_kind": .string(kind.rawValue), "p_note": .of(note)]
        params.merge(locationParams(fix)) { $1 }
        params.merge(fixExtras(fix)) { $1 }
        return try await client.rpc("report_facility_issue", params, requiresUser: true)
    }

    func confirmFacility(id: UUID, exists: Bool, fix: LocationFix?) async throws -> ConfirmationResult {
        var params: RPCParams = ["p_facility_id": .of(id), "p_exists": .bool(exists)]
        params.merge(locationParams(fix)) { $1 }
        params.merge(fixExtras(fix)) { $1 }
        return try await client.rpc("confirm_facility", params, requiresUser: true)
    }
}

struct SupabaseSubmissionRepository: SubmissionRepository {
    let client: SupabaseClient

    func findDuplicates(at point: GeoPoint, name: String?) async throws -> [DuplicateCandidateDTO] {
        try await client.rpc("find_duplicate_facilities", [
            "p_latitude": .number(point.latitude), "p_longitude": .number(point.longitude),
            "p_name": .of(name?.isEmpty == false ? name : nil),
        ])
    }

    func submitFacility(_ d: FacilitySubmissionDraft, forceNew: Bool, userFix: LocationFix?) async throws -> SubmissionResult {
        guard let loc = d.location else { throw APIError.invalidInput("Choose where the courts are") }
        var params: RPCParams = [
            "p_latitude": .number(loc.latitude), "p_longitude": .number(loc.longitude),
            "p_name": .of(d.name.trimmingCharacters(in: .whitespaces).isEmpty ? nil : d.name),
            "p_court_count": .of(d.courtCount), "p_court_type": .string(d.courtType.rawValue),
            "p_indoor_outdoor": .string(d.indoorOutdoor.rawValue), "p_has_lights": .of(d.hasLights),
            "p_access_type": .string(d.accessType.rawValue), "p_cost_type": .string(d.costType.rawValue),
            "p_play_system": .string(d.playSystem.rawValue),
            "p_notes": .of(d.notes.isEmpty ? nil : d.notes), "p_hours_note": .of(d.hoursNote.isEmpty ? nil : d.hoursNote),
            "p_force_new": .bool(forceNew),
        ]
        params.merge(locationParams(userFix, prefix: "p_user_")) { $1 }
        return try await client.rpc("submit_facility", params, requiresUser: true)
    }

    func suggestEdit(facilityID: UUID, type: EditType, proposed: [String: JSONValue], note: String?, fix: LocationFix?) async throws -> EditResult {
        var params: RPCParams = ["p_facility_id": .of(facilityID), "p_edit_type": .string(type.rawValue),
                                 "p_proposed": .object(proposed), "p_note": .of(note)]
        params.merge(locationParams(fix)) { $1 }
        return try await client.rpc("suggest_edit", params, requiresUser: true)
    }

    func uploadPhoto(jpeg: Data, facilityID: UUID?, submissionID: UUID?, width: Int, height: Int) async throws {
        let session = try await client.ensureSession()
        let path = "\(session.userID.uuidString.lowercased())/\(UUID().uuidString.lowercased()).jpg"
        try await client.uploadObject(bucket: "facility-photos", path: path, data: jpeg, contentType: "image/jpeg")
        struct Registered: Decodable { let status: String }
        let _: Registered = try await client.rpc("register_photo", [
            "p_storage_path": .string(path), "p_facility_id": .of(facilityID), "p_submission_id": .of(submissionID),
            "p_metadata": .object(["width": .int(width), "height": .int(height), "bytes": .int(jpeg.count)]),
        ], requiresUser: true)
    }
}

struct SupabaseProfileRepository: ProfileRepository {
    let client: SupabaseClient

    func contributorStatus() async throws -> ContributorStatus {
        guard await client.currentUserID != nil else { return .unknown }
        return try await client.rpc("my_contributor_status", [:], requiresUser: true)
    }

    func saveProfile(_ p: UserPreferences, passiveVisits: Bool) async throws {
        struct Ignored: Decodable {}
        let _: Ignored? = try await client.rpc("upsert_profile", [
            "p_skill_band": .string(p.skill.rawValue), "p_cost_preference": .string(p.costPreference.rawValue),
            "p_prefers_competitive": .of(p.prefersCompetitive), "p_wants_beginner_friendly": .bool(p.wantsBeginnerFriendly),
            "p_passive_visits_enabled": .bool(passiveVisits),
        ], requiresUser: true)
    }

    func recordVisit(_ v: VisitRecord) async throws {
        struct Ignored: Decodable {}
        let _: Ignored? = try await client.rpc("record_visit", [
            "p_facility_id": .of(v.facilityID), "p_arrival_at": .of(v.arrival), "p_departure_at": .of(v.departure),
            "p_detection_method": .string(v.method), "p_confidence": .number(v.confidence),
        ], requiresUser: true)
    }

    func logEvent(_ name: String, facilityID: UUID?, props: [String: JSONValue]) async {
        struct Ignored: Decodable {}
        let _: Ignored? = try? await client.rpc("log_event", [
            "p_event": .string(name), "p_facility_id": .of(facilityID), "p_props": .object(props),
        ])
    }
}
