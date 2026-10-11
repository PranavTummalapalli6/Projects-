import Foundation
import PickleCore

/// Offline backend for development and UI tests: fictional facilities from DemoFacilities.json plus
/// synthesized history/live signals and in-memory contributions. It runs the same PickleCore rules the
/// server mirrors (duplicate detection, location checks) so every flow is exercisable without Supabase.
actor DemoBackend: FacilityRepository, ReportRepository, SubmissionRepository, ProfileRepository {
    private var facilities: [Facility]
    private var userReports: [UUID: [LiveObservation]] = [:]
    private var reportTimes: [UUID: Date] = [:]
    private var issues: [UUID: [OperationalOverride]] = [:]
    private var insightsUntil: Date?
    private var contributions = 0
    private let verifier = LocationVerifier()
    private let now: @Sendable () -> Date
    /// Lets reports be submitted from anywhere (e.g. the simulator in Cupertino reporting on Fairfax).
    var relaxLocationChecks: Bool

    init(bundle: Bundle = .main, now: @escaping @Sendable () -> Date = { Date() }, relaxLocationChecks: Bool = false) {
        self.now = now
        self.relaxLocationChecks = relaxLocationChecks
        if let url = bundle.url(forResource: "DemoFacilities", withExtension: "json"),
           let data = try? Data(contentsOf: url),
           let list = try? JSONCoding.decoder.decode([Facility].self, from: data) {
            facilities = list
        } else {
            facilities = []
        }
    }

    init(facilities: [Facility], now: @escaping @Sendable () -> Date = { Date() }) {
        self.facilities = facilities
        self.now = now
        self.relaxLocationChecks = false
    }

    func setRelaxLocationChecks(_ value: Bool) { relaxLocationChecks = value }

    // MARK: Synthesis

    /// Stable per-facility pseudo-random number in 0..<1.
    private func noise(_ f: Facility, _ salt: Int) -> Double {
        // Swift's Hasher is seeded per launch, so derive stability from the UUID bytes instead.
        let bytes = withUnsafeBytes(of: f.id.uuid) { Array($0) }
        let v = bytes.enumerated().reduce(UInt64(salt &* 2654435761)) { ($0 &* 31) &+ UInt64($1.element) &+ UInt64($1.offset) }
        return Double(v % 10_000) / 10_000
    }

    private func popularity(_ f: Facility) -> Double { 0.7 + noise(f, 1) * 0.6 }

    private func weekBuckets(_ f: Facility) -> [HistoricalBucket] {
        guard !f.isCommunityReported else { return [] }
        let scale = popularity(f)
        return (0..<7).flatMap { dow in
            (12..<46).map { b in
                let occ = min(1.1, OccupancyPrior.occupancy(dayOfWeek: dow, bucket: b, indoor: f.indoorOutdoor == .indoor) * scale * 1.15)
                return HistoricalBucket(dayOfWeek: dow, bucket: b, sampleCount: 18 + Int(noise(f, b) * 20), avgOccupancy: occ)
            }
        }
    }

    private func synthesizedLive(_ f: Facility, at date: Date) -> [LiveObservation] {
        guard !f.isCommunityReported else { return [] }
        let tz = f.timeZone.flatMap(TimeZone.init(identifier:)) ?? .current
        let (dow, bucket) = TimeBuckets.bucket(for: date, timeZone: tz)
        let occ = OccupancyPrior.occupancy(dayOfWeek: dow, bucket: bucket, indoor: f.indoorOutdoor == .indoor) * popularity(f)
        // Only some facilities have recent reports, like the real world.
        guard noise(f, 7) > 0.35 else { return [] }
        let status: OccupancyStatus = occ > 0.9 ? .playersWaiting : occ > 0.7 ? .allFull : occ > 0.45 ? .mostlyFull : .courtsOpen
        let age1 = 2 + noise(f, 11) * 12, age2 = 9 + noise(f, 12) * 25
        var obs = [LiveObservation(ageMinutes: age1, status: status, weight: 1, locationVerified: true),
                   LiveObservation(ageMinutes: age2, status: status, weight: 0.9, locationVerified: true)]
        if f.playSystem == .paddleStack {
            let paddles = max(0, (occ - 0.6) * 30)
            obs.append(LiveObservation(kind: .paddleStack, ageMinutes: age1 + 1, paddles: paddles.rounded(), weight: 1, locationVerified: true))
        }
        return obs
    }

    private func synthesizedBlackouts(_ f: Facility, at date: Date) -> [Blackout] {
        guard f.name.contains("Willow Pond") || f.name.contains("Appletree") else { return [] }
        let tz = f.timeZone.flatMap(TimeZone.init(identifier:)) ?? .current
        var cal = Calendar(identifier: .gregorian); cal.timeZone = tz
        let day = cal.startOfDay(for: date)
        var start = cal.date(byAdding: .hour, value: 8, to: day)!, end = cal.date(byAdding: .hour, value: 18, to: day)!
        if date >= end {
            start = cal.date(byAdding: .day, value: 1, to: start)!; end = cal.date(byAdding: .day, value: 1, to: end)!
        }
        return [Blackout(id: UUID(uuidString: "00000000-0000-4000-8000-0000000000b1")!, startAt: start, endAt: end,
                         reason: .tournament, description: "Regional tournament", verificationStatus: .verified, confidence: 0.95)]
    }

    private func synthesizedOverrides(_ f: Facility, at date: Date) -> [OperationalOverride] {
        var list = issues[f.id, default: []].filter { $0.isActive(at: date) }
        if f.name.contains("Mason Ridge") {
            list.append(OperationalOverride(kind: .usableCourts, value: 4, note: "2 courts reserved for a lesson",
                                            startsAt: date.addingTimeInterval(-3600), expiresAt: date.addingTimeInterval(7200),
                                            reportCount: 2, confidence: 0.8))
        }
        return list
    }

    private func hydrate(_ base: Facility, at date: Date) -> Facility {
        var f = base
        let tz = f.timeZone.flatMap(TimeZone.init(identifier:)) ?? .current
        let (dow, bucket) = TimeBuckets.bucket(for: date, timeZone: tz)
        f.historicalNow = weekBuckets(f).first { $0.dayOfWeek == dow && $0.bucket == bucket }
        let mine = userReports[f.id, default: []].map { o -> LiveObservation in
            var copy = o
            copy.ageMinutes = date.timeIntervalSince(reportTimes[f.id] ?? date) / 60 + o.ageMinutes
            return copy
        }
        let live = synthesizedLive(f, at: date) + mine
        f.live = live.isEmpty ? nil : LiveSignals(observations: live)
        f.blackouts = synthesizedBlackouts(f, at: date)
        f.overrides = synthesizedOverrides(f, at: date)
        if f.indoorOutdoor != .indoor, f.surface == nil, noise(f, 21) > 0.6 {
            f.surface = SurfaceSummary(condition: .dry, ageMinutes: 20 + noise(f, 22) * 60, reportCount: 1, confidence: 0.7)
        }
        if !f.isCommunityReported && f.sessionStats == nil {
            f.sessionStats = SessionStats(medianMinutes: 55 + noise(f, 31) * 20, p25Minutes: 38, p75Minutes: 88, sampleCount: 40)
        }
        return f
    }

    // MARK: FacilityRepository

    func nearby(in box: GeoBoundingBox, timeZone: String) async throws -> [Facility] {
        try await Task.sleep(for: .milliseconds(250))
        let date = now()
        return facilities.filter { box.contains($0.coordinate) && $0.existenceStatus != .rejected }.map { hydrate($0, at: date) }
    }

    func detail(id: UUID, timeZone: String) async throws -> FacilityDetail? {
        guard let f = facilities.first(where: { $0.id == id }) else { return nil }
        let rules: [FacilityRule] = [f.access.accessNotes].compactMap { $0 }.map { FacilityRule(kind: "access", text: $0) }
        return FacilityDetail(facility: hydrate(f, at: now()), weekBuckets: weekBuckets(f), rules: rules, photos: [],
                              sources: [f.source ?? "demo"], myConfirmation: nil,
                              confirmationCount: f.isCommunityReported ? 1 : 12)
    }

    func search(_ query: String, near: GeoPoint?, timeZone: String) async throws -> [Facility] {
        let q = query.lowercased()
        let date = now()
        return facilities
            .filter { $0.name.lowercased().contains(q) || ($0.city?.lowercased() == q) || DuplicateDetector.similarity($0.name, query) > 0.6 }
            .sorted { a, b in
                guard let near else { return a.name < b.name }
                return GeoMath.distanceMeters(near, a.coordinate) < GeoMath.distanceMeters(near, b.coordinate)
            }
            .map { hydrate($0, at: date) }
    }

    func requestRegionDiscovery(at point: GeoPoint) async throws -> RegionDiscoveryResult {
        RegionDiscoveryResult(geohash: GeoMath.geohash(point), action: "fresh", facilityCount: 0, inserted: 0)
    }

    // MARK: ReportRepository

    private func check(_ fix: LocationFix?, _ f: Facility) -> Bool {
        relaxLocationChecks || verifier.check(fix, facility: f.coordinate, now: now()).allowsLiveReport
    }

    private func grant() -> Date {
        contributions += 1
        let until = now().addingTimeInterval(7 * 86400)
        insightsUntil = until
        return until
    }

    func submitLiveReport(_ r: LiveReportRequest) async throws -> LiveReportResult {
        try await Task.sleep(for: .milliseconds(300))
        guard let index = facilities.firstIndex(where: { $0.id == r.facilityID }) else {
            return LiveReportResult(accepted: false, reason: "facility_not_found")
        }
        let f = facilities[index]
        let live = [LiveReportKind.occupancy, .paddleStack, .surface, .usableCourts].contains(r.kind)
        if live && !check(r.fix, f) { return LiveReportResult(accepted: false, reason: "not_nearby") }
        switch r.kind {
        case .occupancy:
            let status = r.value.flatMap(OccupancyStatus.init(rawValue:))
            userReports[f.id, default: []].append(LiveObservation(ageMinutes: 0, status: status, occupiedCourts: r.count,
                                                                  groupsWaiting: r.groupsWaiting, weight: 1, locationVerified: true))
            reportTimes[f.id] = now()
        case .paddleStack:
            let paddles = r.count.map(Double.init) ?? r.value.flatMap(PaddleStackLevel.init(rawValue:))?.representativePaddles
            userReports[f.id, default: []].append(LiveObservation(kind: .paddleStack, ageMinutes: 0, paddles: paddles, weight: 1))
            reportTimes[f.id] = now()
        case .surface:
            if let c = r.value.flatMap(SurfaceCondition.init(rawValue:)) {
                facilities[index].surface = SurfaceSummary(condition: c, ageMinutes: 0, reportCount: 1, confidence: 0.6)
            }
        case .usableCourts:
            issues[f.id, default: []].append(OperationalOverride(kind: .usableCourts, value: r.count, startsAt: now(),
                                                                 expiresAt: now().addingTimeInterval(4 * 3600), confidence: 0.6))
        case .skill:
            if let band = r.value.flatMap(SkillBand.init(rawValue:)) {
                var s = facilities[index].skill ?? SkillSummary(bands: [], observationCount: 0)
                if let i = s.bands.firstIndex(where: { $0.band == band }) { s.bands[i].weight += 1 } else { s.bands.append(.init(band: band, weight: 1)) }
                s.observationCount += 1; s.newestDaysAgo = 0
                facilities[index].skill = s
            }
        case .culture:
            for raw in (r.value ?? "").split(separator: ",") {
                guard let tag = PlayCultureTag(rawValue: String(raw)) else { continue }
                if let i = facilities[index].culture.firstIndex(where: { $0.tag == tag }) {
                    facilities[index].culture[i].observationCount += 1
                    facilities[index].culture[i].share = min(1, facilities[index].culture[i].share + 0.1)
                } else {
                    facilities[index].culture.append(CultureSummary(tag: tag, share: 0.5, observationCount: 2))
                }
            }
        }
        return LiveReportResult(accepted: true, locationVerified: true, insightsUntil: live ? grant() : nil)
    }

    func reportIssue(facilityID: UUID, kind: IssueKind, note: String?, fix: LocationFix?) async throws -> LiveReportResult {
        guard let f = facilities.first(where: { $0.id == facilityID }) else { return LiveReportResult(accepted: false, reason: "facility_not_found") }
        let verified = check(fix, f)
        let overrideKind = OverrideKind(rawValue: kind.rawValue) ?? .unknown
        var list = issues[facilityID, default: []]
        if let i = list.firstIndex(where: { $0.kind == overrideKind && $0.isActive(at: now()) }) {
            list[i].reportCount += 1
            list[i].confidence = min(1, list[i].confidence + 0.3)
        } else {
            list.append(OperationalOverride(kind: overrideKind, note: note, startsAt: now(), expiresAt: now().addingTimeInterval(6 * 3600),
                                            reportCount: 1, confidence: verified ? 0.5 : 0.16))
        }
        issues[facilityID] = list
        return LiveReportResult(accepted: true, locationVerified: verified, state: "warning")
    }

    func confirmFacility(id: UUID, exists: Bool, fix: LocationFix?) async throws -> ConfirmationResult {
        guard let i = facilities.firstIndex(where: { $0.id == id }) else { return ConfirmationResult(accepted: false, reason: "facility_not_found") }
        if exists {
            facilities[i].existenceConfidence = min(1, facilities[i].existenceConfidence + 0.15)
            if facilities[i].existenceStatus == .communityReported && facilities[i].existenceConfidence >= 0.5 {
                facilities[i].existenceStatus = .partiallyVerified
            }
        } else {
            _ = try await reportIssue(facilityID: id, kind: .possibleClosure, note: nil, fix: fix)
        }
        return ConfirmationResult(accepted: true, existenceStatus: facilities[i].existenceStatus)
    }

    // MARK: SubmissionRepository

    func findDuplicates(at point: GeoPoint, name: String?) async throws -> [DuplicateCandidateDTO] {
        DuplicateDetector().candidates(name: name?.isEmpty == false ? name : nil, location: point,
                                       existing: facilities.map { ($0.id, $0.name, $0.coordinate, $0.address) })
            .map { c in
                let f = facilities.first { $0.id == c.facilityID }
                return DuplicateCandidateDTO(facilityId: c.facilityID, name: c.name, distanceMeters: c.distanceMeters,
                                             nameSimilarity: c.nameSimilarity, existenceStatus: f?.existenceStatus,
                                             latitude: f?.latitude, longitude: f?.longitude)
            }
    }

    func submitFacility(_ d: FacilitySubmissionDraft, forceNew: Bool, userFix: LocationFix?) async throws -> SubmissionResult {
        try await Task.sleep(for: .milliseconds(400))
        guard SubmissionValidator.validate(d).isEmpty, let loc = d.location else {
            return SubmissionResult(status: "invalid", reason: SubmissionValidator.validate(d).first?.message)
        }
        let dups = try await findDuplicates(at: loc, name: d.name)
        if !dups.isEmpty && (!forceNew || dups.contains { $0.distanceMeters <= 30 }) {
            return SubmissionResult(status: "duplicate_candidates", candidates: dups)
        }
        let f = Facility(name: d.name.isEmpty ? "Pickleball courts" : d.name, latitude: loc.latitude, longitude: loc.longitude,
                         totalPhysicalCourts: d.courtCount, defaultPickleballCourts: d.courtCount, courtType: d.courtType,
                         indoorOutdoor: d.indoorOutdoor, hasLights: d.hasLights, playSystem: d.playSystem, source: "community",
                         existenceStatus: .communityReported, existenceConfidence: 0.3,
                         access: FacilityAccess(accessType: d.accessType, verificationStatus: .communityReported, confidence: 0.2),
                         cost: FacilityCost(costType: d.costType))
        facilities.append(f)
        return SubmissionResult(status: "created", facilityId: f.id, submissionId: UUID(), existenceStatus: .communityReported,
                                insightsUntil: grant())
    }

    func suggestEdit(facilityID: UUID, type: EditType, proposed: [String: JSONValue], note: String?, fix: LocationFix?) async throws -> EditResult {
        if type == .permanentlyClosed { _ = try await reportIssue(facilityID: facilityID, kind: .possibleClosure, note: note, fix: fix) }
        if type == .noLongerPickleball { _ = try await reportIssue(facilityID: facilityID, kind: .pickleballProhibited, note: note, fix: fix) }
        return EditResult(status: "recorded", suggestionId: UUID())
    }

    func uploadPhoto(jpeg: Data, facilityID: UUID?, submissionID: UUID?, width: Int, height: Int) async throws {
        try await Task.sleep(for: .milliseconds(300))
    }

    // MARK: ProfileRepository

    func contributorStatus() async throws -> ContributorStatus {
        ContributorStatus(insightsUntil: insightsUntil, qualifyingContributions: contributions, hasLiveInsights: true, liveGatingEnabled: false)
    }

    func saveProfile(_ prefs: UserPreferences, passiveVisits: Bool) async throws {}
    func recordVisit(_ visit: VisitRecord) async throws {}
    func logEvent(_ name: String, facilityID: UUID?, props: [String: JSONValue]) async {}
}
