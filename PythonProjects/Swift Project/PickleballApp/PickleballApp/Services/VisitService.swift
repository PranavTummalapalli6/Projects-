import Foundation
import Observation
import OSLog
import PickleCore

private let log = Logger(subsystem: "PickleballNow", category: "visits")

/// Foreground visit detection (arrival after a short dwell, departure when leaving). Produces at most one
/// contextual prompt per visit via PromptPolicy. No GPS trail is kept — only the current visit in memory,
/// and arrival/departure times are uploaded only if the user opted in.
@Observable
@MainActor
final class VisitService {
    struct ActivePrompt: Identifiable, Equatable {
        let facility: Facility
        let kind: PromptKind
        let visitID: UUID
        var id: UUID { visitID }
        static func == (a: Self, b: Self) -> Bool { a.visitID == b.visitID && a.kind == b.kind }
    }

    private(set) var currentFacility: Facility?
    var activePrompt: ActivePrompt?

    @ObservationIgnored private var candidate: (facility: Facility, since: Date)?
    @ObservationIgnored private var lastFix: LocationFix?
    @ObservationIgnored private var dwellTask: Task<Void, Never>?
    @ObservationIgnored private var visitID = UUID()
    @ObservationIgnored private var arrivedAt: Date?
    @ObservationIgnored private var facilities: [Facility] = []
    @ObservationIgnored private var predictions: [UUID: WaitPrediction] = [:]
    @ObservationIgnored private var weather: [UUID: WeatherAssessment] = [:]
    @ObservationIgnored private let reports: ReportService
    @ObservationIgnored private let profile: ProfileRepository
    @ObservationIgnored private let prefs: PreferencesStore
    @ObservationIgnored let arrivalDwell: TimeInterval
    @ObservationIgnored let arrivalRadius: Double = 150
    @ObservationIgnored let departureRadius: Double = 350

    init(reports: ReportService, profile: ProfileRepository, prefs: PreferencesStore, arrivalDwell: TimeInterval = 60) {
        self.reports = reports
        self.profile = profile
        self.prefs = prefs
        self.arrivalDwell = arrivalDwell
    }

    /// Latest facilities and their recommendation context (used to choose the right question).
    func update(recommendations: [FacilityRecommendation]) {
        facilities = recommendations.map(\.facility)
        predictions = Dictionary(recommendations.map { ($0.id, $0.prediction) }, uniquingKeysWith: { a, _ in a })
        weather = Dictionary(recommendations.map { ($0.id, $0.weather) }, uniquingKeysWith: { a, _ in a })
        if let lastFix { handle(fix: lastFix) }
    }

    func handle(fix: LocationFix, now: Date = Date()) {
        lastFix = fix
        if let current = currentFacility {
            if GeoMath.distanceMeters(fix.point, current.coordinate) > departureRadius { depart(at: now) }
            return
        }
        guard fix.horizontalAccuracy <= 100,
              let nearest = facilities.min(by: { GeoMath.distanceMeters(fix.point, $0.coordinate) < GeoMath.distanceMeters(fix.point, $1.coordinate) }),
              GeoMath.distanceMeters(fix.point, nearest.coordinate) <= arrivalRadius else {
            candidate = nil
            return
        }
        if candidate?.facility.id != nearest.id {
            log.debug("Near facility; waiting for dwell")
            candidate = (nearest, now)
            scheduleDwellCheck()
        }
        if let c = candidate, now.timeIntervalSince(c.since) >= arrivalDwell { arrive(at: c.facility, now: now) }
    }

    /// A stationary phone delivers no new fixes, so re-check once the dwell time has elapsed.
    private func scheduleDwellCheck() {
        dwellTask?.cancel()
        let delay = arrivalDwell + 1
        dwellTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled, let self, let fix = self.lastFix else { return }
            self.handle(fix: fix)
        }
    }

    /// Demo/DEBUG helper paired with ReportService.simulatedPresence.
    func simulateArrival(at f: Facility, prompt: Bool = true) {
        reports.simulatedPresence = f.id
        arrive(at: f, now: Date(), prompt: prompt)
    }

    private func arrive(at f: Facility, now: Date, prompt: Bool = true) {
        log.debug("Arrival detected")
        currentFacility = f
        arrivedAt = now
        visitID = UUID()
        candidate = nil
        if prompt { evaluatePrompt(now: now) }
    }

    private func depart(at now: Date) {
        if let f = currentFacility, let arrival = arrivedAt, prefs.passiveVisitsEnabled {
            let visit = VisitRecord(facilityID: f.id, arrival: arrival, departure: now)
            let profile = self.profile
            Task { try? await profile.recordVisit(visit) }
        }
        currentFacility = nil
        arrivedAt = nil
        activePrompt = nil
        reports.simulatedPresence = nil
    }

    func evaluatePrompt(now: Date = Date()) {
        guard let f = currentFacility, activePrompt == nil else { return }
        let ctx = PromptContext(facility: f, visitID: visitID, isNearby: true, prediction: predictions[f.id],
                                weather: weather[f.id], now: now)
        let decision = reports.decidePrompt(ctx)
        log.debug("Prompt decision: \(String(describing: decision), privacy: .public)")
        if case .ask(let kind) = decision {
            activePrompt = ActivePrompt(facility: f, kind: kind, visitID: visitID)
            reports.recordPromptShown(facilityID: f.id, visitID: visitID)
        }
    }

    func dismissPrompt() {
        activePrompt = nil
        reports.recordPromptDismissed()
    }

    func completePrompt() { activePrompt = nil }
}
