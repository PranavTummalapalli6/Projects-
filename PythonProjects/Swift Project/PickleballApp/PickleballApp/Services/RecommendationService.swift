import Foundation
import PickleCore

/// Joins facilities with travel time and weather, then runs the staged PickleCore engine.
/// Travel: instant straight-line estimates for all; routed ETAs for the top candidates only.
struct RecommendationService: Sendable {
    let engine: RecommendationEngine
    let travel: TravelTimeService
    let conditions: ConditionsService
    var routedCandidateCount = 6
    var maxWeatherCells = 4

    func recommend(_ facilities: [Facility], origin: GeoPoint?, prefs: UserPreferences, mode: SortMode,
                   now: Date = Date()) async -> RecommendationSet {
        var inputs: [RecommendationInput] = []
        for f in facilities {
            let routed = origin == nil ? nil : await travel.cached(from: origin!, to: f.id)
            let travelEstimate = routed ?? origin.map { travel.estimate(from: $0, to: f) }
            let weather = f.indoorOutdoor == .indoor ? nil : await conditions.cached(at: f.coordinate)
            inputs.append(RecommendationInput(facility: f, travel: travelEstimate, weather: weather))
        }
        return engine.recommend(inputs, prefs: prefs, now: now, mode: mode)
    }

    /// Warms routed ETAs for the most promising candidates. Returns true if anything changed.
    func refineTravel(for set: RecommendationSet, origin: GeoPoint) async -> Bool {
        let candidates = Array((set.picks + set.ranked).reduce(into: [FacilityRecommendation]()) { acc, r in
            if !acc.contains(where: { $0.id == r.id }) { acc.append(r) }
        }.prefix(routedCandidateCount))
        var changed = false
        await withTaskGroup(of: Bool.self) { group in
            for r in candidates where r.travel?.isEstimate != false {
                group.addTask { await travel.routed(from: origin, to: r.facility).isEstimate == false }
            }
            for await updated in group { changed = changed || updated }
        }
        return changed
    }

    /// Fetches weather for the outdoor facilities' cells (bounded). Returns true if new data arrived.
    func refreshWeather(for facilities: [Facility]) async -> Bool {
        var cells: [String: GeoPoint] = [:]
        for f in facilities where f.indoorOutdoor != .indoor {
            let key = ConditionsService.cellKey(f.coordinate)
            if cells[key] == nil, await conditions.cached(at: f.coordinate) == nil { cells[key] = f.coordinate }
            if cells.count >= maxWeatherCells { break }
        }
        guard !cells.isEmpty else { return false }
        await withTaskGroup(of: Void.self) { group in
            for point in cells.values { group.addTask { _ = await conditions.conditions(at: point) } }
        }
        return true
    }
}
