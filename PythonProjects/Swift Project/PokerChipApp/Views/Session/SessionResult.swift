//
//  SessionResult.swift
//  PokerChipApp
//

import Foundation

/// Response from POST /v1/sessions/{id}/complete — the backend's authoritative,
/// server-computed profit/loss for the session, plus the stored photo's URL.
struct SessionResult: Codable, Hashable {
    let profitLoss: Double
    let photoUrl: String
}
