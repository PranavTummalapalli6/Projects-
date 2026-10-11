//
//  APIConfig.swift
//  PokerChipApp
//
//  Points the app at the ChipVisionService backend.
//

import Foundation

enum APIConfig {
    /// The backend's base URL, read from Info.plist (`APIBaseURL`). Each build
    /// configuration supplies it through the `API_BASE_URL` build setting:
    ///   - Debug: a locally running container on the developer's Mac (a LAN
    ///     address so a physical phone on the same Wi-Fi can reach it — update
    ///     it if the Mac's IP changes).
    ///   - Release: the deployed service. Until that URL is filled in, the
    ///     "Check Release configuration" build phase fails App Store archives.
    static var rawBaseURL: String {
        Bundle.main.object(forInfoDictionaryKey: "APIBaseURL") as? String ?? ""
    }

    /// False while the build still carries a placeholder (or nothing at all),
    /// so the app can say "not set up" instead of timing out against a host
    /// that doesn't exist.
    static var isConfigured: Bool {
        let raw = rawBaseURL
        return !raw.isEmpty && !raw.contains("REPLACE_WITH") && URL(string: raw)?.host != nil
    }

    static var baseURL: URL {
        if let url = URL(string: rawBaseURL), url.host != nil {
            return url
        }
        assertionFailure("APIBaseURL is missing or malformed in Info.plist")
        // `.invalid` is reserved and can never resolve.
        return URL(string: "https://backend.invalid")!
    }
}
