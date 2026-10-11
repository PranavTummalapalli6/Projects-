//
//  AppEnvironment.swift
//  PokerChipApp
//

import Foundation

/// Process-wide switches derived from how the app was launched.
enum AppEnvironment {
    /// `-UITestMode`: UI tests run the real app against stubbed auth and
    /// network, so they are deterministic and never touch Firebase or the
    /// backend.
    static let isUITest = ProcessInfo.processInfo.arguments.contains("-UITestMode")

    /// `-ResetState` (used with `-UITestMode`): wipe saved sessions and
    /// preferences before the first screen appears.
    static let shouldResetState = ProcessInfo.processInfo.arguments.contains("-ResetState")

    /// `-UITestLiveNight` (debug builds, with `-UITestMode`): start a night in progress if there is
    /// none, and let the Live Activity run, so the Lock Screen can be looked at without driving the setup screens.
    static let seedsLiveNight: Bool = {
        #if DEBUG
        return isUITest && ProcessInfo.processInfo.arguments.contains("-UITestLiveNight")
        #else
        return false
        #endif
    }()

    /// `-UITestGuidedCamera` (debug builds, with `-UITestMode`): the guided camera runs on a stand-in
    /// that shows a still picture and walks through scripted readings, since a UI test has no camera.
    static let usesStubCamera: Bool = {
        #if DEBUG
        return isUITest && ProcessInfo.processInfo.arguments.contains("-UITestGuidedCamera")
        #else
        return false
        #endif
    }()

    /// e.g. "1.0 (1)" — shown in Settings so a bug report can name the build.
    static var versionString: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "\(version) (\(build))"
    }

    static func resetPersistedStateIfRequested() {
        guard isUITest, shouldResetState, let bundleId = Bundle.main.bundleIdentifier else { return }
        UserDefaults.standard.removePersistentDomain(forName: bundleId)
        try? FileNightRepository().removeAll()
    }
}

/// Where people can reach the owner. Left unset until the owner supplies real
/// values — Settings hides a row whose value is nil rather than shipping a
/// placeholder link.
enum SupportConfig {
    static let supportEmail: String? = nil
    static let privacyPolicyURL: URL? = nil
    static let termsURL: URL? = nil
}
