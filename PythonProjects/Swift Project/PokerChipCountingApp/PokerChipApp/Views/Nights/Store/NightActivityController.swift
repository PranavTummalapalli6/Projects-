//
//  NightActivityController.swift
//  PokerChipApp
//
//  Keeps the Live Activity — the night's clock and money on the Lock Screen and in
//  the Dynamic Island — in step with the night in progress: started with the
//  night, updated when a rebuy or a break changes what it shows, ended when play
//  is called. The clock itself is a date the system counts up from, so nothing
//  needs sending while it simply runs. If Live Activities are off in Settings, or
//  the system won't start one, nothing happens and the app is unaffected.
//

import ActivityKit
import Foundation
import os

extension NightActivityAttributes.ContentState {
    /// What the Lock Screen shows for a night, or nil when it isn't in progress.
    init?(night: GameNight, now: Date = Date()) {
        guard night.isLive else { return nil }
        self.init(
            // While on a break the clock isn't running, so it needs no start; keeping it still stops
            // the state changing second by second as the break gets longer.
            clockStart: night.hasOpenPause ? night.startedAt : night.startedAt.addingTimeInterval(TimeInterval(night.pausedSeconds(at: now))),
            frozenSeconds: night.hasOpenPause ? night.playtimeSeconds(at: now) : nil,
            players: night.players.count,
            inPlayMinor: night.totalInMinor,
            currencyCode: night.currency
        )
    }
}

@MainActor
final class NightActivityController {
    static let shared = NightActivityController()

    private static let log = Logger(subsystem: "Vanarp.PokerChipApp", category: "live-activity")

    private var activity: Activity<NightActivityAttributes>?
    private var shown: NightActivityAttributes.ContentState?

    /// Starts, updates or ends the Live Activity so that it matches `night`
    /// (nil, or one that isn't in progress, means none should be showing).
    func sync(with night: GameNight?, now: Date = Date()) {
        guard let night, let state = NightActivityAttributes.ContentState(night: night, now: now) else {
            end()
            return
        }
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        let content = ActivityContent(state: state, staleDate: nil)

        if let running = adopt(for: night.id) {
            guard state != shown else { return }
            shown = state
            Task { await running.update(content) }
            return
        }
        do {
            activity = try Activity.request(attributes: NightActivityAttributes(nightID: night.id.uuidString), content: content, pushType: nil)
            shown = state
        } catch {
            // Too many already showing, or the person has turned them off: not worth bothering anyone about.
            Self.log.error("Could not start the Live Activity: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Takes the activity away, wherever it was started from (a launch after the app was killed
    /// finds the one the last run left behind).
    func end() {
        let leftovers = Activity<NightActivityAttributes>.activities
        activity = nil
        shown = nil
        guard !leftovers.isEmpty else { return }
        Task {
            for leftover in leftovers { await leftover.end(nil, dismissalPolicy: .immediate) }
        }
    }

    /// The activity already showing for this night — possibly started by an earlier run of the
    /// app — with any other ended: those belong to a night that is over.
    private func adopt(for nightID: UUID) -> Activity<NightActivityAttributes>? {
        let all = Activity<NightActivityAttributes>.activities
        let mine = all.first { $0.attributes.nightID == nightID.uuidString }
        for other in all where other.id != mine?.id {
            Task { await other.end(nil, dismissalPolicy: .immediate) }
        }
        if let mine, activity?.id != mine.id {
            // Found, not made by this run, so what it shows is unknown: say it again.
            shown = nil
        }
        activity = mine
        return mine
    }
}

extension NightStore {
    /// Applies a link from the Lock Screen or Dynamic Island: shows the night in
    /// progress, putting its clock on a break or taking it off one if asked. Both
    /// are only ever applied when they change something, so a link tapped twice is
    /// harmless. Returns the night to show, or nil if none is in progress.
    @discardableResult
    func handle(_ link: NightLink) -> UUID? {
        guard let night = nights.first(where: \.isLive) else { return nil }
        switch link {
        case .openNight:
            break
        case .takeBreak:
            if !night.hasOpenPause { mutate(night.id) { $0.pause() } }
        case .resumePlay:
            if night.hasOpenPause { mutate(night.id) { $0.resumeFromPause() } }
        }
        return night.id
    }
}
