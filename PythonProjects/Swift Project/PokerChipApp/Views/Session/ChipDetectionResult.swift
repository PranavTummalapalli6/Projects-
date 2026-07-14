//
//  ChipDetectionResult.swift
//  PokerChipApp
//

import Foundation

/// Response from POST /v1/sessions/{id}/photo — the backend's best-effort read of
/// the photo. `confidence` reflects how many chip candidates were ambiguous or
/// overlapping; the review screen always requires the user to confirm regardless.
struct ChipDetectionResult: Codable, Hashable {
    let counts: [String: Int]
    let confidence: String
    let photoUrl: String
}

/// Bundles what TimerView learned from the photo upload (or didn't, if the backend
/// was unreachable) so it can hand off to ReviewCountsView via navigationDestination(item:).
struct PhotoAnalysisOutcome: Hashable {
    var counts: [String: Int]?
    var confidence: String?
    var photoUrl: String?
}
