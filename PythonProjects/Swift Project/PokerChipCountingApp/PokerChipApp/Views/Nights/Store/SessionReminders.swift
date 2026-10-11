//
//  SessionReminders.swift
//  PokerChipApp
//
//  The optional "time for a break?" notification during a long night. It is
//  scheduled on the phone (no server involved), moved whenever the night
//  changes — a pause pushes it back, ending the night cancels it — and only ever
//  exists while the person has turned it on and allowed notifications.
//

import Foundation
import UserNotifications
import os

/// What the reminder needs from the system, so it can be tested without one.
protocol ReminderCenter {
    func requestAuthorization() async -> Bool
    func isAuthorized() async -> Bool
    func schedule(id: String, title: String, body: String, after seconds: TimeInterval) async
    func cancel(id: String)
}

struct SystemReminderCenter: ReminderCenter {
    private static let log = Logger(subsystem: "Vanarp.PokerChipApp", category: "reminders")

    func requestAuthorization() async -> Bool {
        (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])) ?? false
    }

    func isAuthorized() async -> Bool {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        return settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional
    }

    func schedule(id: String, title: String, body: String, after seconds: TimeInterval) async {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(seconds, 1), repeats: false)
        do {
            try await UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
        } catch {
            Self.log.error("Could not schedule the break reminder: \(error.localizedDescription, privacy: .public)")
        }
    }

    func cancel(id: String) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [id])
    }
}

@MainActor
final class SessionReminders {
    static let identifier = "session-break-reminder"

    private let center: ReminderCenter

    init(center: ReminderCenter = SystemReminderCenter()) {
        self.center = center
    }

    /// Brings the scheduled reminder in line with the night and the setting.
    func update(night: GameNight?, hours: Double?, now: Date = Date()) async {
        switch HealthyPlay.reminderPlan(for: night, hours: hours, now: now) {
        case .cancel:
            center.cancel(id: Self.identifier)
        case .schedule(let seconds):
            guard await center.isAuthorized(), let hours else {
                center.cancel(id: Self.identifier)
                return
            }
            // One pending reminder at a time: re-adding with the same id replaces it.
            await center.schedule(
                id: Self.identifier,
                title: "Time for a break?",
                body: HealthyPlay.reminderBody(hours: hours),
                after: seconds
            )
        }
    }

    /// Asks permission when the person turns the reminder on — not at launch.
    func requestPermission() async -> Bool {
        await center.requestAuthorization()
    }

    func isAllowed() async -> Bool {
        await center.isAuthorized()
    }
}
