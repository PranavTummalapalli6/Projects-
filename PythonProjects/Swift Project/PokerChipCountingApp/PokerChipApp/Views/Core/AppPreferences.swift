//
//  AppPreferences.swift
//  PokerChipApp
//

import Foundation

/// UserDefaults keys, shared with `@AppStorage` in views so a toggle in
/// Settings and the code that reads it can never drift apart.
enum PrefKey {
    static let haptics = "pref.hapticsEnabled"
    static let colorBlindChips = "pref.colorBlindChips"
    static let weeklyHoursCap = "pref.weeklyHoursCap"
    static let lastSplashVersion = "pref.lastSplashVersion"
    /// Whole currency units lost over seven days that earn a gentle word; 0 = off.
    static let weeklyLossLimit = "pref.weeklyLossLimit"
    /// Hours into a night at which to suggest a break; 0 = off.
    static let sessionReminderHours = "pref.sessionReminderHours"
    /// A break the person committed to: seconds since 1970 until which no new night starts; 0 = none.
    static let coolOffUntil = "pref.coolOffUntil"
    /// The week's nudge they have already seen and dismissed.
    static let dismissedNudge = "pref.dismissedNudge"
    /// Live tips on the camera screen. On unless the person turns it off; off means the system's own camera.
    static let guidedCamera = "pref.guidedCamera"
}

enum AppPreferences {
    static let defaultWeeklyHoursCap: Double = 20

    static var hapticsEnabled: Bool {
        UserDefaults.standard.object(forKey: PrefKey.haptics) as? Bool ?? true
    }

    static var colorBlindChips: Bool {
        UserDefaults.standard.bool(forKey: PrefKey.colorBlindChips)
    }

    /// Hours of poker in a week at which the Poker Health chip is fully worn.
    static var weeklyHoursCap: Double {
        let stored = UserDefaults.standard.double(forKey: PrefKey.weeklyHoursCap)
        return stored > 0 ? stored : defaultWeeklyHoursCap
    }
}

/// The in-app splash shows once per app version, not on every launch — the
/// system launch screen already covers the load, so repeating the splash would
/// only delay the people who open the app every game night.
enum SplashPolicy {
    static func shouldShow(defaults: UserDefaults = .standard, version: String = AppEnvironment.versionString) -> Bool {
        if AppEnvironment.isUITest { return false }
        return defaults.string(forKey: PrefKey.lastSplashVersion) != version
    }

    static func markShown(defaults: UserDefaults = .standard, version: String = AppEnvironment.versionString) {
        defaults.set(version, forKey: PrefKey.lastSplashVersion)
    }
}
