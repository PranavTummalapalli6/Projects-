//
//  Prewarm.swift
//  PokerChipApp
//
//  The counting service scales to zero when idle, and its first answer can take
//  several seconds. Asking it to wake as a night starts, and again when a
//  cash-out opens, means the photo isn't the thing that waits. At most one
//  request every few minutes, never an error, never any data.
//

import Foundation

@MainActor
enum Prewarm {
    /// Seconds before the service is asked again.
    static let interval: TimeInterval = 300

    private static var lastAsked: Date?

    static func countingService(now: Date = Date(), client: ChipVisionAPIClient = .shared) {
        if let lastAsked, now.timeIntervalSince(lastAsked) < interval { return }
        lastAsked = now
        Task { await client.prewarm() }
    }

    /// Forgets when it last asked (for tests).
    static func reset() {
        lastAsked = nil
    }
}
