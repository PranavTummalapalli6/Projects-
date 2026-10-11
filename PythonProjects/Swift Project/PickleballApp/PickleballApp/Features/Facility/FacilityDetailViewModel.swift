import Foundation
import Observation
import PickleCore

@Observable
@MainActor
final class FacilityDetailViewModel {
    enum State: Equatable { case loading, loaded, failed(String) }

    private(set) var state: State = .loading
    private(set) var detail: FacilityDetail?
    private(set) var bestTime: BestTimeResult?
    private(set) var confirmation: String?
    var confirmMessage: String?

    @ObservationIgnored private let rec: FacilityRecommendation
    @ObservationIgnored private let env: AppEnvironment

    init(rec: FacilityRecommendation, env: AppEnvironment) {
        self.rec = rec
        self.env = env
    }

    func load() async {
        do {
            let d = try await env.facilityService.detail(id: rec.facility.id)
            detail = d
            confirmation = d?.myConfirmation
            let weather = rec.facility.indoorOutdoor == .indoor ? nil
                : await env.recommendationService.conditions.conditions(at: rec.facility.coordinate)
            bestTime = BestTimePlanner().plan(facility: d?.facility ?? rec.facility, now: Date(),
                                              weekBuckets: d?.weekBuckets ?? [], current: rec.prediction, weather: weather)
            state = .loaded
            env.log("prediction_view", facilityID: rec.facility.id)
        } catch {
            // Still show a best-time estimate from the generic prior when the network fails.
            bestTime = BestTimePlanner().plan(facility: rec.facility, now: Date(), weekBuckets: [], current: rec.prediction, weather: nil)
            state = .failed((error as? LocalizedError)?.errorDescription ?? "Couldn't load details.")
        }
    }

    func confirm(exists: Bool) async {
        do {
            let r = try await env.reports.confirm(rec.facility, exists: exists)
            if r.accepted {
                confirmation = exists ? "exists" : "not_exists"
                confirmMessage = exists ? "Thanks for confirming this court." : "Thanks — we'll flag it for other players."
                Haptics.success()
            } else {
                confirmMessage = r.reason == "own_submission" ? "You added this court — others will confirm it." : "We couldn't save that."
            }
        } catch {
            confirmMessage = (error as? LocalizedError)?.errorDescription
        }
    }
}
