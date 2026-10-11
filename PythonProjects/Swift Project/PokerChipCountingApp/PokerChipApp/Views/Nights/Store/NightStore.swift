//
//  NightStore.swift
//  PokerChipApp
//
//  The nights on this device. Everything goes through here: a change is made
//  with `mutate`, stamped, saved straight away and queued for the server, so a
//  killed app or a dead signal never costs a night. Reads are served from
//  memory; the screens just observe `nights`.
//

import Foundation
import os

@MainActor
final class NightStore: ObservableObject {
    private static let log = Logger(subsystem: "Vanarp.PokerChipApp", category: "night-store")

    enum Phase: Equatable {
        case loading
        case ready
    }

    /// Something the person should know, phrased for them.
    enum Problem: Equatable {
        case unreadable(Int)
        case newerVersion(Int)
        case couldNotOpenStorage
        case couldNotSave

        var message: String {
            switch self {
            case .unreadable(let count):
                return count == 1
                    ? "One saved night couldn't be opened and was set aside."
                    : "\(count) saved nights couldn't be opened and were set aside."
            case .newerVersion(let count):
                return count == 1
                    ? "One night was saved by a newer version of the app. Update the app to see it."
                    : "\(count) nights were saved by a newer version of the app. Update the app to see them."
            case .couldNotOpenStorage:
                return "Saved nights couldn't be opened. Your iPhone's storage may be full or unavailable."
            case .couldNotSave:
                return "Your latest changes couldn't be saved to this iPhone. Free up some space and they'll be saved with your next change."
            }
        }
    }

    enum MergeResult: Equatable {
        case inserted
        case replaced
        case identical
        case keptLocal
    }

    /// How long a deleted night can still be brought back, with its details.
    nonisolated static let undoWindow: TimeInterval = 8

    @Published private(set) var phase: Phase = .loading
    /// Nights that aren't deleted, newest first.
    @Published private(set) var nights: [GameNight] = []
    @Published private(set) var problems: [Problem] = []
    /// How many nights the server hasn't confirmed yet.
    @Published private(set) var pendingCount = 0
    /// The night just deleted, while it can still be brought back — what the
    /// "Night deleted · Undo" banner on every list is driven by.
    @Published private(set) var lastDeletedID: UUID?

    private let repository: NightRepository
    private let clock: () -> Date
    private var records: [UUID: GameNight] = [:]
    private var dirty: Set<UUID> = []
    private var unsaved: Set<UUID> = []
    private var syncStateUnsaved = false
    private var loadProblems: [Problem] = []
    private var syncState = NightSyncState()
    private var undoExpiry: Task<Void, Never>?

    init(repository: NightRepository, clock: @escaping () -> Date = Date.init) {
        self.repository = repository
        self.clock = clock
    }

    // MARK: Loading

    /// Reads everything from storage, off the main thread so a long history
    /// doesn't hold up launch. Only the first call does anything.
    func load() async {
        guard phase == .loading else { return }
        let repository = self.repository
        let outcome = await Task.detached(priority: .userInitiated) {
            Result { (try repository.loadAll(), repository.loadSyncState()) }
        }.value

        switch outcome {
        case .success(let (result, state)):
            for night in result.nights {
                // Two files for one night shouldn't happen; if they do, the newer wins.
                if let existing = records[night.id], existing.updatedAt >= night.updatedAt { continue }
                records[night.id] = night
            }
            syncState = state
            dirty = Set(state.dirty.compactMap(UUID.init(uuidString:))).intersection(records.keys)
            if result.quarantinedCount > 0 { loadProblems.append(.unreadable(result.quarantinedCount)) }
            if result.newerVersionCount > 0 { loadProblems.append(.newerVersion(result.newerVersionCount)) }
        case .failure(let error):
            Self.log.error("Could not read saved nights: \(error.localizedDescription, privacy: .public)")
            loadProblems.append(.couldNotOpenStorage)
        }
        phase = .ready
        publish()
    }

    // MARK: Reading

    /// The night, unless it has been deleted.
    func night(_ id: UUID) -> GameNight? {
        records[id].flatMap { $0.isDeleted ? nil : $0 }
    }

    /// The night the Resume banner points at: the most recent one not yet settled.
    var openNight: GameNight? { nights.first(where: \.isOpen) }

    // MARK: Changing

    /// Adds a new night.
    @discardableResult
    func start(_ night: GameNight) -> GameNight {
        var night = NightCoding.canonical(night)
        night.updatedAt = nextStamp(after: nil)
        records[night.id] = night
        dirty.insert(night.id)
        didChange(night)
        return night
    }

    /// Applies a change to one night. If the night really changed, it is
    /// re-stamped (strictly later than before, even if the clock went
    /// backwards), saved, and queued for the server. Returns whether it changed.
    @discardableResult
    func mutate(_ id: UUID, _ change: (inout GameNight) -> Void) -> Bool {
        guard let before = records[id] else { return false }
        var night = before
        change(&night)
        night = NightCoding.canonical(night)
        guard night != before else { return false }
        night.updatedAt = nextStamp(after: before.updatedAt)
        records[id] = night
        dirty.insert(id)
        didChange(night)
        return true
    }

    func delete(_ id: UUID) {
        let now = clock()
        guard mutate(id, { $0.markDeleted(at: NightCoding.quantized(now)) }) else { return }
        lastDeletedID = id
        undoExpiry?.cancel()
        undoExpiry = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64((Self.undoWindow + 1) * 1_000_000_000))
            guard !Task.isCancelled, let self else { return }
            if self.lastDeletedID == id { self.lastDeletedID = nil }
            self.stripDeleted()
        }
    }

    /// Undo for `delete`, while the details are still here.
    func restore(_ id: UUID) {
        mutate(id) { $0.restore() }
        if lastDeletedID == id { lastDeletedID = nil }
        undoExpiry?.cancel()
    }

    /// Once Undo is over, keeps only the marker of each deleted night — no
    /// names, place or notes. Same version as before, so it isn't re-queued
    /// unless it was already waiting to go.
    func stripDeleted(olderThan age: TimeInterval = NightStore.undoWindow) {
        let cutoff = clock().addingTimeInterval(-age)
        var changed = false
        for (id, night) in records where night.isDeleted {
            guard let deletedAt = night.deletedAt, deletedAt <= cutoff, night != night.tombstone else { continue }
            let stripped = night.tombstone
            records[id] = stripped
            persist(stripped)
            changed = true
        }
        if changed { publish() }
    }

    /// Removes everything from this device (a deleted account leaves nothing behind).
    func reset() {
        undoExpiry?.cancel()
        lastDeletedID = nil
        records = [:]
        dirty = []
        unsaved = []
        syncState = NightSyncState()
        syncStateUnsaved = false
        loadProblems = []
        do { try repository.removeAll() } catch {
            Self.log.error("Could not remove saved nights: \(error.localizedDescription, privacy: .public)")
        }
        publish()
    }

    /// Writes again whatever couldn't be saved earlier (storage was full).
    func retrySaving() {
        for id in unsaved {
            if let night = records[id] { persist(night) }
        }
        if syncStateUnsaved { persistSyncState() }
        publish()
    }

    // MARK: Sync

    var cursor: String? { syncState.cursor }
    var ownerUID: String? { syncState.ownerUID }
    var legacyImportedFor: String? { syncState.legacyImportedFor }

    /// Changes the server hasn't confirmed, oldest edit first.
    var pending: [GameNight] {
        dirty.compactMap { records[$0] }
            .sorted { $0.updatedAt != $1.updatedAt ? $0.updatedAt < $1.updatedAt : $0.id.uuidString < $1.id.uuidString }
    }

    /// Records which account sync is working for. If it isn't the one this
    /// device last synced with, every night here is queued for the new account
    /// and the pull starts from the beginning.
    func attach(to uid: String) {
        guard syncState.ownerUID != uid else { return }
        syncState.ownerUID = uid
        syncState.cursor = nil
        syncState.legacyImportedFor = nil
        dirty = Set(records.keys)
        persistSyncState()
    }

    /// The server now holds exactly this version of the night.
    func markSynced(_ id: UUID, version: Date) {
        guard dirty.contains(id), let night = records[id], night.updatedAt == version else { return }
        dirty.remove(id)
        persistSyncState()
    }

    /// Takes the server's copy over the local one, whatever their stamps say:
    /// used when the server answers that it kept its own version.
    func adopt(_ remote: GameNight) {
        records[remote.id] = remote
        dirty.remove(remote.id)
        persist(remote)
        persistSyncState()
        publish()
    }

    /// Last-writer-wins: a night from the server replaces the local one only if
    /// it was edited later. Ties and older versions keep the local night, which
    /// stays queued so the server hears about it.
    @discardableResult
    func merge(_ remote: GameNight) -> MergeResult {
        guard let local = records[remote.id] else {
            records[remote.id] = remote
            persist(remote)
            publish()
            return .inserted
        }
        if remote.updatedAt > local.updatedAt {
            records[remote.id] = remote
            dirty.remove(remote.id)
            persist(remote)
            persistSyncState()
            publish()
            return .replaced
        }
        if remote.updatedAt == local.updatedAt && remote == local { return .identical }
        if !dirty.contains(remote.id) {
            dirty.insert(remote.id)
            persistSyncState()
        }
        return .keptLocal
    }

    func setCursor(_ cursor: String?) {
        guard syncState.cursor != cursor else { return }
        syncState.cursor = cursor
        persistSyncState()
    }

    func markLegacyImported(for uid: String) {
        syncState.legacyImportedFor = uid
        persistSyncState()
    }

    // MARK: Plumbing

    private func nextStamp(after previous: Date?) -> Date {
        let now = NightCoding.quantized(clock())
        guard let previous else { return now }
        return max(now, previous.addingTimeInterval(0.001))
    }

    private func didChange(_ night: GameNight) {
        persist(night)
        persistSyncState()
        publish()
    }

    private func persist(_ night: GameNight) {
        do {
            try repository.save(night)
            unsaved.remove(night.id)
        } catch {
            unsaved.insert(night.id)
            Self.log.error("Could not save a night: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func persistSyncState() {
        syncState.dirty = dirty.map(\.uuidString).sorted()
        pendingCount = dirty.count
        do {
            try repository.saveSyncState(syncState)
            syncStateUnsaved = false
        } catch {
            syncStateUnsaved = true
            Self.log.error("Could not save the sync queue: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func publish() {
        nights = records.values
            .filter { !$0.isDeleted }
            .sorted { $0.startedAt != $1.startedAt ? $0.startedAt > $1.startedAt : $0.id.uuidString < $1.id.uuidString }
        problems = loadProblems + ((unsaved.isEmpty && !syncStateUnsaved) ? [] : [.couldNotSave])
        pendingCount = dirty.count
    }
}
