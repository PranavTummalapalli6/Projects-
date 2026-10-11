//
//  Persistence.swift
//  PokerChipApp
//
//  The small things remembered between nights in UserDefaults. Nights
//  themselves live in files (see Nights/Store); this is only for what the
//  next night starts from.
//

import Foundation

/// A Codable value kept as JSON in UserDefaults. Data that fails to decode
/// (an older build's shape, corruption) is dropped rather than crashing.
struct JSONDefaultsStore<Value: Codable> {
    let key: String
    var defaults: UserDefaults = .standard

    func load() -> Value? {
        guard let data = defaults.data(forKey: key) else { return nil }
        do {
            return try JSONDecoder().decode(Value.self, from: data)
        } catch {
            defaults.removeObject(forKey: key)
            return nil
        }
    }

    func save(_ value: Value) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        defaults.set(data, forKey: key)
    }

    func clear() {
        defaults.removeObject(forKey: key)
    }
}

enum Stores {
    /// What was entered on the setup screens, so the next night starts from the same table.
    static let gameSetup = JSONDefaultsStore<GameSetup>(key: "store.gameSetup.v1")
    /// The chips the person owns, remembered so it is entered once.
    static let chipInventory = JSONDefaultsStore<ChipInventory>(key: "store.chipInventory.v1")

    /// Keys written by earlier builds, which kept one unfinished game and its
    /// unsent results here. Nothing reads them now.
    private static let retiredKeys = [
        "store.activeSession.v1", "store.lastGame.v1", "store.lastResult.v1", "store.pendingSaves.v1",
    ]

    static func removeRetiredKeys(defaults: UserDefaults = .standard) {
        for key in retiredKeys { defaults.removeObject(forKey: key) }
    }

    /// Everything tied to a person's data on this device — used when an
    /// account is deleted so nothing of theirs lingers locally.
    static func clearAll() {
        gameSetup.clear()
        chipInventory.clear()
        removeRetiredKeys()
    }
}
