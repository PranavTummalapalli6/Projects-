//
//  APIConfig.swift
//  PokerChipApp
//
//  Points the app at the ChipVisionService backend.
//

import Foundation

enum APIConfig {
    /// Debug builds talk to a locally-running container; Release builds talk to
    /// the deployed Cloud Run service. Update the Release URL after deploying
    /// (see ChipVisionService/README.md).
    static var baseURL: URL {
        #if DEBUG
        // - iOS Simulator can reach the host machine's Docker container at "localhost".
        // - A physical device on the same Wi-Fi network needs the host machine's LAN IP
        //   instead, e.g. "http://192.168.1.23:8000".
        return URL(string: "http://localhost:8000")!
        #else
        return URL(string: "https://REPLACE_WITH_CLOUD_RUN_URL")!
        #endif
    }
}
