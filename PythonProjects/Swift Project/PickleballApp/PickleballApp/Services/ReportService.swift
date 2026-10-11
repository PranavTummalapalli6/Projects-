import Foundation
import Observation
import PickleCore

/// One-tap contributions: location pre-check, submission, prompt-fatigue bookkeeping and contributor
/// status. The server re-verifies location and decides trust; nothing here is authoritative.
@Observable
@MainActor
final class ReportService {
    /// Demo/DEBUG only: lets a developer act as if standing at a facility.
    var simulatedPresence: UUID?
    private(set) var promptState: PromptState

    @ObservationIgnored let policy: PromptPolicy
    @ObservationIgnored private let verifier = LocationVerifier()
    @ObservationIgnored private let integrity: IntegrityRiskEvaluator
    @ObservationIgnored private let repository: ReportRepository
    @ObservationIgnored private let location: LocationService
    @ObservationIgnored private let contributor: ContributorStore
    @ObservationIgnored private let store: LocalStore
    @ObservationIgnored private let analytics: ProfileRepository
    @ObservationIgnored private var history: [ReportHistoryEntry]
    @ObservationIgnored let allowsSimulatedPresence: Bool

    init(repository: ReportRepository, location: LocationService, contributor: ContributorStore, store: LocalStore,
         analytics: ProfileRepository, isProduction: Bool, allowsSimulatedPresence: Bool, policy: PromptPolicy = PromptPolicy()) {
        self.repository = repository
        self.location = location
        self.contributor = contributor
        self.store = store
        self.analytics = analytics
        self.policy = policy
        self.integrity = IntegrityRiskEvaluator(isProduction: isProduction)
        self.allowsSimulatedPresence = allowsSimulatedPresence
        self.promptState = store.load(PromptState.self, key: StoreKeys.promptState) ?? PromptState()
        self.history = store.load([ReportHistoryEntry].self, key: StoreKeys.reportHistory) ?? []
    }

    // MARK: Location gating

    func locationCheck(for f: Facility) -> LocationCheck {
        if simulatedPresence == f.id { return .nearby(distanceMeters: 0) }
        guard location.isAuthorized else { return .unavailable }
        return verifier.check(location.lastFix, facility: f.coordinate, now: Date())
    }

    private func fix(for f: Facility) async -> LocationFix? {
        if simulatedPresence == f.id {
            return LocationFix(point: f.coordinate, horizontalAccuracy: 10, timestamp: Date(), isSimulatedBySoftware: true)
        }
        return await location.currentFix()
    }

    // MARK: Submissions

    @discardableResult
    func submit(_ kind: LiveReportKind, value: String?, count: Int? = nil, groupsWaiting: Int? = nil,
                at f: Facility, promptKind: PromptKind?) async throws -> LiveReportResult {
        let fix = await fix(for: f)
        if let fix {
            // Client mirror of the integrity model — only used for local diagnostics; the server decides.
            _ = integrity.assess(fix: fix, facilityID: f.id, facilityLocation: f.coordinate, history: history, now: Date())
        }
        let result = try await repository.submitLiveReport(
            LiveReportRequest(facilityID: f.id, kind: kind, value: value, count: count, groupsWaiting: groupsWaiting, fix: fix))
        if result.accepted {
            history.append(ReportHistoryEntry(facilityID: f.id, facilityLocation: f.coordinate, at: Date()))
            history = history.filter { Date().timeIntervalSince($0.at) < 86400 }
            store.save(history, key: StoreKeys.reportHistory)
            policy.recordAnswered(&promptState, facilityID: f.id, kind: promptKind ?? Self.promptKind(for: kind), at: Date())
            store.save(promptState, key: StoreKeys.promptState)
            contributor.noteContribution(insightsUntil: result.insightsUntil)
            await analytics.logEvent("report_submitted", facilityID: f.id, props: ["kind": .string(kind.rawValue),
                                                                                   "prompted": .bool(promptKind != nil)])
        }
        return result
    }

    func reportIssue(_ kind: IssueKind, at f: Facility, note: String?) async throws -> LiveReportResult {
        let result = try await repository.reportIssue(facilityID: f.id, kind: kind, note: note, fix: await fix(for: f))
        if result.accepted { await analytics.logEvent("report_submitted", facilityID: f.id, props: ["kind": .string(kind.rawValue)]) }
        return result
    }

    func confirm(_ f: Facility, exists: Bool) async throws -> ConfirmationResult {
        let result = try await repository.confirmFacility(id: f.id, exists: exists, fix: await fix(for: f))
        if result.accepted {
            policy.recordAnswered(&promptState, facilityID: f.id, kind: .confirmExists, at: Date())
            store.save(promptState, key: StoreKeys.promptState)
            await analytics.logEvent("court_confirmed", facilityID: f.id, props: ["exists": .bool(exists)])
        }
        return result
    }

    // MARK: Prompt fatigue

    func decidePrompt(_ ctx: PromptContext) -> PromptDecision { policy.decide(ctx, state: promptState) }

    func recordPromptShown(facilityID: UUID, visitID: UUID) {
        policy.recordShown(&promptState, facilityID: facilityID, visitID: visitID, at: Date())
        store.save(promptState, key: StoreKeys.promptState)
    }

    func recordPromptDismissed() {
        policy.recordDismissed(&promptState, at: Date())
        store.save(promptState, key: StoreKeys.promptState)
    }

    static func promptKind(for kind: LiveReportKind) -> PromptKind {
        switch kind {
        case .paddleStack: .paddleWait
        case .surface: .courtSurface
        default: .howBusy
        }
    }
}
