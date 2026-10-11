import Foundation

/// Centralized configuration. Secrets come from Config/Secrets.xcconfig → Info.plist; nothing is hardcoded.
/// Only the public anon key is ever shipped. Missing values switch the app into clearly-labelled demo mode.
struct AppConfig: Sendable {
    let supabaseURL: URL?
    let supabaseAnonKey: String?
    let useWeatherKit: Bool
    let isUITesting: Bool
    let isProduction: Bool

    var isDemo: Bool { supabaseURL == nil || (supabaseAnonKey ?? "").isEmpty || isUITesting }

    static func load(bundle: Bundle = .main, processInfo: ProcessInfo = .processInfo) -> AppConfig {
        func value(_ key: String) -> String? {
            guard let raw = bundle.object(forInfoDictionaryKey: key) as? String else { return nil }
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty || trimmed.hasPrefix("$(") ? nil : trimmed
        }
        let url = value("SupabaseURL").flatMap(URL.init(string:)).flatMap { $0.scheme == "https" || $0.host == "127.0.0.1" || $0.host == "localhost" ? $0 : nil }
        #if DEBUG
        let production = false
        #else
        let production = true
        #endif
        return AppConfig(
            supabaseURL: url,
            supabaseAnonKey: value("SupabaseAnonKey"),
            useWeatherKit: value("UseWeatherKit") == "YES",
            isUITesting: processInfo.arguments.contains("-uiTesting"),
            isProduction: production)
    }
}
