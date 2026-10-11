import Foundation
import PickleCore

/// Small JSON-file persistence in Application Support (excluded from backups for caches).
/// Holds per-device state that never needs to leave the phone: prompt fatigue state, report history
/// (facility + time only), preferences, saved facilities, last map region.
final class LocalStore: @unchecked Sendable {
    private let directory: URL
    private let queue = DispatchQueue(label: "LocalStore")

    init(directory: URL? = nil) {
        let base = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appending(path: "PickleballNow", directoryHint: .isDirectory)
        self.directory = base
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
    }

    func load<T: Decodable>(_ type: T.Type, key: String) -> T? {
        queue.sync {
            guard let data = try? Data(contentsOf: url(key)) else { return nil }
            return try? JSONCoding.decoder.decode(T.self, from: data)
        }
    }

    func save<T: Encodable>(_ value: T, key: String) {
        queue.async {
            guard let data = try? JSONCoding.encoder.encode(value) else { return }
            try? data.write(to: self.url(key), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        }
    }

    func remove(key: String) {
        queue.sync { try? FileManager.default.removeItem(at: url(key)) }
    }

    func reset() {
        queue.sync {
            try? FileManager.default.removeItem(at: directory)
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
    }

    private func url(_ key: String) -> URL { directory.appending(path: "\(key).json") }
}

enum StoreKeys {
    static let promptState = "prompt_state"
    static let reportHistory = "report_history"
    static let preferences = "preferences"
    static let savedFacilities = "saved_facilities"
    static let lastRegion = "last_region"
    static let filters = "filters"
    static let onboarding = "onboarding"
    static let regionDiscovery = "region_discovery"
    static let facilityCache = "facility_cache"
}
