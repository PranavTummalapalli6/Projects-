//
//  NightRepository.swift
//  PokerChipApp
//
//  Where nights are kept on the device. The app talks to this protocol, never
//  to files directly, so the store can be tested in memory and the storage
//  can change without touching a screen.
//

import Foundation

/// Everything read back from storage at launch.
struct NightLoadResult: Equatable {
    var nights: [GameNight] = []
    /// Files that couldn't be read. They are set aside, not deleted, so nothing
    /// is lost to a bad write or a bug.
    var quarantinedCount = 0
    /// Nights saved by a newer version of the app. They are left untouched on
    /// disk and not shown, rather than guessed at.
    var newerVersionCount = 0
}

/// What sync needs to remember between launches.
struct NightSyncState: Codable, Equatable {
    /// The account the cursor and queue belong to.
    var ownerUID: String?
    /// The server's position: everything up to here has been pulled.
    var cursor: String?
    /// Nights with changes the server hasn't confirmed, as UUID strings in a
    /// fixed order so the same state always produces the same bytes.
    var dirty: [String] = []
    /// The account whose old single-player sessions were already imported.
    var legacyImportedFor: String?
}

protocol NightRepository {
    func loadAll() throws -> NightLoadResult
    func save(_ night: GameNight) throws
    func loadSyncState() -> NightSyncState
    func saveSyncState(_ state: NightSyncState) throws
    /// Removes every night and the sync state — used when an account is deleted.
    func removeAll() throws
}

// MARK: - Schema versions

/// Brings a night saved by an older build up to the current shape. Step N turns
/// version N into N + 1; adding a version means adding one step here and
/// bumping `GameNight.currentSchemaVersion`.
struct NightMigrator {
    typealias Step = (inout [String: Any]) throws -> Void

    enum Outcome {
        case current(GameNight)
        case upgraded(GameNight)
        /// Saved by a build newer than this one.
        case newer(Int)
    }

    enum MigrationError: Error, Equatable {
        case notAnObject
        case missingStep(from: Int)
    }

    var steps: [Int: Step] = [:]

    static let standard = NightMigrator()

    func decode(_ data: Data) throws -> Outcome {
        struct Peek: Decodable { var schemaVersion: Int? }
        let version = try JSONDecoder().decode(Peek.self, from: data).schemaVersion ?? GameNight.currentSchemaVersion

        if version > GameNight.currentSchemaVersion { return .newer(version) }
        if version == GameNight.currentSchemaVersion {
            return .current(try NightCoding.makeDecoder().decode(GameNight.self, from: data))
        }

        guard var object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw MigrationError.notAnObject
        }
        var step = version
        while step < GameNight.currentSchemaVersion {
            guard let upgrade = steps[step] else { throw MigrationError.missingStep(from: step) }
            try upgrade(&object)
            step += 1
            object["schemaVersion"] = step
        }
        let upgraded = try JSONSerialization.data(withJSONObject: object)
        return .upgraded(try NightCoding.makeDecoder().decode(GameNight.self, from: upgraded))
    }
}

// MARK: - In memory

/// Keeps everything in memory: for tests, previews, and as the fallback when
/// the device has nowhere to write.
final class MemoryNightRepository: NightRepository {
    private(set) var nights: [UUID: GameNight] = [:]
    private(set) var syncState = NightSyncState()
    /// Make writes fail, to exercise the "couldn't save" path.
    var failsToSave = false

    struct WriteFailure: Error {}

    init(nights: [GameNight] = []) {
        for night in nights { self.nights[night.id] = night }
    }

    func loadAll() throws -> NightLoadResult {
        NightLoadResult(nights: Array(nights.values))
    }

    func save(_ night: GameNight) throws {
        if failsToSave { throw WriteFailure() }
        nights[night.id] = night
    }

    func loadSyncState() -> NightSyncState { syncState }

    func saveSyncState(_ state: NightSyncState) throws {
        if failsToSave { throw WriteFailure() }
        syncState = state
    }

    func removeAll() throws {
        nights = [:]
        syncState = NightSyncState()
    }
}
