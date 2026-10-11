//
//  NightSync.swift
//  PokerChipApp
//
//  Keeps this device and the server level, in the background and without ever
//  being in the way: the phone is always the source of truth for what the
//  person just did, so nothing here can lose a night, and every failure just
//  means "try again later".
//
//  One pass is: tell the server about our changes (each night is one idempotent
//  PUT, so a dropped connection costs nothing), then ask what changed there
//  since our cursor, last-writer-wins by each night's own `updatedAt`.
//

import Foundation
import os

@MainActor
final class NightSync: ObservableObject {
    private static let log = Logger(subsystem: "Vanarp.PokerChipApp", category: "night-sync")

    /// Each pull starts this far before the cursor, so a write the server
    /// stamped slightly out of order (clocks drift between its instances) is
    /// still picked up. Re-reading a night is harmless: merging is idempotent.
    static let overlap: TimeInterval = 10
    static let pageSize = 100
    /// How long to wait after a change before syncing, so a burst of taps is one request.
    static let quietPeriod: Double = 2

    enum Status: Equatable {
        case idle
        case syncing
        /// No connection; changes are safe on this iPhone and will go when there is one.
        case offline
        /// This server doesn't offer night sync (yet); nothing is wrong on the phone.
        case unavailable
        case needsSignIn
        case failed(String)
    }

    @Published private(set) var status: Status = .idle
    @Published private(set) var lastSyncedAt: Date?
    /// Nights the server refused (it couldn't understand them). They stay on the phone.
    @Published private(set) var refusedCount = 0

    private let store: NightStore
    private let client: () -> ChipVisionAPIClient
    private let now: () -> Date
    private let sleep: (Double) async -> Void
    private var isRunning = false
    private var needsAnotherPass = false
    private var scheduled: Task<Void, Never>?

    init(
        store: NightStore,
        client: @escaping () -> ChipVisionAPIClient = { .shared },
        now: @escaping () -> Date = Date.init,
        sleep: @escaping (Double) async -> Void = { try? await Task.sleep(nanoseconds: UInt64($0 * 1_000_000_000)) }
    ) {
        self.store = store
        self.client = client
        self.now = now
        self.sleep = sleep
    }

    // MARK: Running

    /// Syncs soon: waits for a quiet moment first, and a newer request replaces an older one.
    func schedule(uid: String?) {
        scheduled?.cancel()
        let delay = Self.quietPeriod
        scheduled = Task { [weak self, sleep] in
            await sleep(delay)
            guard !Task.isCancelled, let self else { return }
            await self.sync(uid: uid)
        }
    }

    /// Waits for a scheduled sync to finish (used by tests).
    func waitForScheduledSync() async {
        await scheduled?.value
    }

    /// Brings this device level with the server for this account. If a sync is
    /// already running, asks it for one more pass instead of overlapping.
    func sync(uid: String?) async {
        guard let uid else {
            status = .needsSignIn
            return
        }
        guard store.phase == .ready else { return }
        if isRunning {
            needsAnotherPass = true
            return
        }
        isRunning = true
        defer { isRunning = false }

        repeat {
            needsAnotherPass = false
            status = .syncing
            do {
                store.attach(to: uid)
                await importLegacySessions(for: uid)
                try await push()
                try await pull()
                store.stripDeleted()
                lastSyncedAt = now()
                status = .idle
            } catch {
                status = Self.status(for: error)
                if status != .offline { Self.log.error("Sync stopped: \(String(describing: error), privacy: .public)") }
                return
            }
        } while needsAnotherPass
    }

    // MARK: Steps

    private func importLegacySessions(for uid: String) async {
        guard store.legacyImportedFor != uid else { return }
        do {
            let added = try await client().importLegacyNights()
            store.markLegacyImported(for: uid)
            Self.log.info("Imported \(added, privacy: .public) earlier sessions as nights")
        } catch {
            // Best effort: it is tried again next time, and must never keep
            // tonight's game from syncing.
            Self.log.notice("Could not import earlier sessions yet: \(String(describing: error), privacy: .public)")
        }
    }

    private func push() async throws {
        var refused = 0
        for night in store.pending {
            do {
                let result = try await client().putNight(night)
                if result.applied {
                    store.markSynced(night.id, version: night.updatedAt)
                } else {
                    store.adopt(result.night)    // the server kept a later edit: take it
                }
            } catch let error as ChipVisionAPIError {
                guard Self.isRefusal(error) else { throw error }
                refused += 1
                Self.log.error("The server refused a night: \(error.localizedDescription, privacy: .public)")
            }
        }
        refusedCount = refused
    }

    private func pull() async throws {
        var since = store.cursor.flatMap { NightCursor.shifted($0, by: -Self.overlap) } ?? store.cursor
        var newest = store.cursor
        var hasMore = true
        while hasMore {
            let page = try await client().fetchNights(since: since, limit: Self.pageSize)
            for night in page.nights { store.merge(night) }
            if let cursor = page.cursor, !page.nights.isEmpty {
                since = cursor
                newest = max(newest ?? cursor, cursor)
            }
            hasMore = page.hasMore && !page.nights.isEmpty
        }
        store.setCursor(newest)
    }

    // MARK: Errors

    /// The server understood the request and said no to this night in particular.
    private static func isRefusal(_ error: ChipVisionAPIError) -> Bool {
        switch error {
        case .tooLarge:
            return true
        case .server(let status, _):
            return (400..<500).contains(status) && status != 404 && status != 405
        default:
            return false
        }
    }

    static func status(for error: Error) -> Status {
        guard let error = error as? ChipVisionAPIError else {
            return .failed("Syncing stopped unexpectedly. Your nights are safe on this iPhone.")
        }
        switch error {
        case .offline, .timedOut, .unreachable:
            return .offline
        case .unauthorized:
            return .needsSignIn
        case .notConfigured:
            return .unavailable
        case .server(let status, _) where status == 404 || status == 405:
            return .unavailable
        case .rateLimited:
            return .failed("That's a lot of changes at once. Syncing will carry on in a little while.")
        default:
            return .failed("The sync service had a problem. Your nights are safe on this iPhone.")
        }
    }
}

// MARK: - Cursors

/// The server's cursor is a fixed-width UTC timestamp with microseconds. To
/// start a pull a little before it, it is read and written here by hand rather
/// than trusting a date formatter with more fractional digits than it documents.
enum NightCursor {
    static func date(from cursor: String) -> Date? {
        let parts = cursor.split(separator: ".", maxSplits: 1, omittingEmptySubsequences: false)
        guard parts.count == 2 else { return NightCoding.date(from: cursor) }

        // "2026-08-07T00:00:05" "000123+00:00"
        let digits = parts[1].prefix { $0.isNumber }
        let rest = parts[1].dropFirst(digits.count)
        guard !digits.isEmpty, let fraction = Double("0." + digits),
              let whole = NightCoding.date(from: String(parts[0]) + String(rest))
        else { return nil }
        return whole.addingTimeInterval(fraction)
    }

    /// The cursor moved by `seconds`, written the way the app writes dates
    /// (whole milliseconds, rounded down so the result is never later than asked).
    static func shifted(_ cursor: String, by seconds: TimeInterval) -> String? {
        date(from: cursor).map { NightCoding.string(from: NightCoding.quantized($0.addingTimeInterval(seconds))) }
    }
}
