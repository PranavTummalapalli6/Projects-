import Foundation
import MapKit
import Observation
import PickleCore

@Observable
@MainActor
final class AddCourtViewModel {
    enum Step: Equatable { case location, basics, details, duplicates, done }

    var step: Step = .location
    var draft = FacilitySubmissionDraft()
    var pinCenter: GeoPoint?
    var duplicates: [DuplicateCandidateDTO] = []
    var photoData: Data?
    var submitting = false
    var errorMessage: String?
    private(set) var result: SubmissionResult?
    private(set) var confirmedExistingName: String?

    @ObservationIgnored private let env: AppEnvironment

    init(env: AppEnvironment, initialCenter: GeoPoint?) {
        self.env = env
        self.pinCenter = initialCenter
    }

    var validationIssues: [SubmissionIssue] { SubmissionValidator.validate(draft) }

    func confirmLocation() {
        draft.location = pinCenter
        step = .basics
    }

    /// Submits; the server (and the demo backend) first checks for duplicates.
    func submit(forceNew: Bool = false) async {
        guard validationIssues.isEmpty else { errorMessage = validationIssues.first?.message; return }
        submitting = true
        errorMessage = nil
        defer { submitting = false }
        do {
            let fix = await env.location.currentFix(timeout: 4)
            let r = try await env.submissionService.submit(draft, forceNew: forceNew, userFix: fix)
            switch r.status {
            case "duplicate_candidates":
                duplicates = r.candidates ?? []
                step = .duplicates
            case "created":
                result = r
                env.contributor.noteContribution(insightsUntil: r.insightsUntil)
                if let photoData {
                    try? await env.submissionService.uploadPhoto(photoData, facilityID: r.facilityId, submissionID: r.submissionId)
                }
                await env.facilityService.invalidate()
                step = .done
                Haptics.success()
            case "rate_limited":
                errorMessage = "You've added several courts today — thanks! Try again tomorrow."
            default:
                errorMessage = r.reason ?? "Please check the details and try again."
            }
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? "Couldn't submit right now."
        }
    }

    /// "Yes, it's this one" → counts as a confirmation of the existing facility instead of a duplicate.
    func chooseExisting(_ c: DuplicateCandidateDTO) async {
        submitting = true
        defer { submitting = false }
        let f = Facility(id: c.facilityId, name: c.name, latitude: c.latitude ?? draft.location?.latitude ?? 0,
                         longitude: c.longitude ?? draft.location?.longitude ?? 0)
        _ = try? await env.reports.confirm(f, exists: true)
        confirmedExistingName = c.name
        step = .done
        Haptics.success()
    }

    func search(_ query: String) async -> GeoPoint? {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query
        if let p = pinCenter { request.region = MKCoordinateRegion(center: p.coordinate, latitudinalMeters: 50_000, longitudinalMeters: 50_000) }
        guard let item = try? await MKLocalSearch(request: request).start().mapItems.first else { return nil }
        let c = item.placemark.coordinate
        return GeoPoint(latitude: c.latitude, longitude: c.longitude)
    }
}
