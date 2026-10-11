//
//  FileNightRepository.swift
//  PokerChipApp
//
//  One JSON file per night in Application Support. Each write goes to a
//  temporary file and is renamed into place, so a crash or a full disk leaves
//  either the old night or the new one — never half of each. A file that can't
//  be read is moved aside rather than deleted.
//

import Foundation
import os

struct FileNightRepository: NightRepository {
    private static let log = Logger(subsystem: "Vanarp.PokerChipApp", category: "night-store")

    let directory: URL
    var migrator = NightMigrator.standard

    /// …/Application Support/GameNights
    static var defaultDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("GameNights", isDirectory: true)
    }

    init(directory: URL = FileNightRepository.defaultDirectory, migrator: NightMigrator = .standard) {
        self.directory = directory
        self.migrator = migrator
    }

    private var nightsDirectory: URL { directory.appendingPathComponent("nights", isDirectory: true) }
    private var quarantineDirectory: URL { directory.appendingPathComponent("quarantine", isDirectory: true) }
    private var syncURL: URL { directory.appendingPathComponent("sync.json") }
    private static let writeOptions: Data.WritingOptions = [.atomic, .completeFileProtectionUntilFirstUserAuthentication]

    private func fileURL(for id: UUID) -> URL {
        nightsDirectory.appendingPathComponent("\(id.uuidString).json")
    }

    // MARK: NightRepository

    func loadAll() throws -> NightLoadResult {
        let manager = FileManager.default
        guard manager.fileExists(atPath: nightsDirectory.path) else { return NightLoadResult() }
        let files = try manager.contentsOfDirectory(at: nightsDirectory, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }

        var result = NightLoadResult()
        for url in files {
            do {
                let data = try Data(contentsOf: url)
                switch try migrator.decode(data) {
                case .current(let night):
                    result.nights.append(night)
                case .upgraded(let night):
                    result.nights.append(night)
                    // Rewrite at the current version so the upgrade happens once.
                    try? save(night)
                case .newer(let version):
                    result.newerVersionCount += 1
                    Self.log.notice("A saved night is from a newer version of the app (schema \(version, privacy: .public)); leaving it alone")
                }
            } catch {
                quarantine(url)
                result.quarantinedCount += 1
            }
        }
        return result
    }

    func save(_ night: GameNight) throws {
        try FileManager.default.createDirectory(at: nightsDirectory, withIntermediateDirectories: true)
        let data = try NightCoding.makeEncoder().encode(night)
        try data.write(to: fileURL(for: night.id), options: Self.writeOptions)
    }

    func loadSyncState() -> NightSyncState {
        guard let data = try? Data(contentsOf: syncURL),
              let state = try? JSONDecoder().decode(NightSyncState.self, from: data)
        else { return NightSyncState() }
        return state
    }

    func saveSyncState(_ state: NightSyncState) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        try encoder.encode(state).write(to: syncURL, options: Self.writeOptions)
    }

    func removeAll() throws {
        let manager = FileManager.default
        if manager.fileExists(atPath: directory.path) {
            try manager.removeItem(at: directory)
        }
    }

    // MARK: Unreadable files

    private func quarantine(_ url: URL) {
        let manager = FileManager.default
        do {
            try manager.createDirectory(at: quarantineDirectory, withIntermediateDirectories: true)
            let stamp = Int(Date().timeIntervalSince1970)
            let target = quarantineDirectory.appendingPathComponent("\(stamp)-\(url.lastPathComponent)")
            try manager.moveItem(at: url, to: target)
            Self.log.error("A saved night couldn't be read and was set aside")
        } catch {
            Self.log.error("A saved night couldn't be read and couldn't be set aside: \(error.localizedDescription, privacy: .public)")
        }
    }
}
