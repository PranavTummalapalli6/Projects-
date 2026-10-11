//
//  NightLiveActivity.swift
//  PokerChipWidgets
//
//  The night in progress, on the Lock Screen and in the Dynamic Island: the clock,
//  the money on the table, and a Break button. The clock counts itself — it is a
//  date the system counts up from — so it stays right while the app is closed.
//  The button opens the app, which puts the clock on a break (or takes it off
//  one): on iOS 16 a Live Activity can't run an action without opening the app.
//

import ActivityKit
import SwiftUI
import WidgetKit

struct NightLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: NightActivityAttributes.self) { context in
            LockScreenNightView(state: context.state)
                .activityBackgroundTint(WidgetPalette.backgroundBottom)
                .activitySystemActionForegroundColor(WidgetPalette.goldLight)
                .widgetURL(NightLink.openNight.url)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(context.state.isOnBreak ? "On a break" : "Playing")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(WidgetPalette.goldLight)
                        NightClock(state: context.state)
                            .font(.title2.weight(.bold).monospacedDigit())
                            .foregroundStyle(WidgetPalette.textPrimary)
                    }
                    // The island's corner is round; text right at the edge is cut by it.
                    .padding(.leading, 8)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("On the table")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(WidgetPalette.goldLight)
                        Text(ActivityMoney.format(minor: context.state.inPlayMinor, currencyCode: context.state.currencyCode))
                            .font(.title3.weight(.bold).monospacedDigit())
                            .foregroundStyle(WidgetPalette.textPrimary)
                    }
                    .padding(.trailing, 8)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack {
                        Text("\(context.state.players) players")
                            .font(.footnote)
                            .foregroundStyle(WidgetPalette.textSecondary)
                        Spacer()
                        BreakLink(isOnBreak: context.state.isOnBreak)
                    }
                }
            } compactLeading: {
                Image(systemName: context.state.isOnBreak ? "pause.fill" : "suit.spade.fill")
                    .foregroundStyle(WidgetPalette.goldLight)
            } compactTrailing: {
                NightClock(state: context.state)
                    .font(.footnote.weight(.semibold).monospacedDigit())
                    .foregroundStyle(WidgetPalette.textPrimary)
                    .frame(maxWidth: 56)
            } minimal: {
                Image(systemName: context.state.isOnBreak ? "pause.fill" : "suit.spade.fill")
                    .foregroundStyle(WidgetPalette.goldLight)
            }
            .widgetURL(NightLink.openNight.url)
            .keylineTint(WidgetPalette.gold)
        }
    }
}

/// The night's clock: counting up by itself while it runs, still while on a break.
struct NightClock: View {
    let state: NightActivityAttributes.ContentState

    var body: some View {
        if let frozen = state.frozenSeconds {
            Text(ActivityMoney.clock(seconds: frozen))
        } else {
            Text(state.clockStart, style: .timer)
        }
    }
}

struct BreakLink: View {
    let isOnBreak: Bool

    var body: some View {
        Link(destination: (isOnBreak ? NightLink.resumePlay : NightLink.takeBreak).url) {
            Label(isOnBreak ? "Resume" : "Break", systemImage: isOnBreak ? "play.fill" : "pause.fill")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(WidgetPalette.goldLight)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Capsule().fill(WidgetPalette.gold.opacity(0.18)))
        }
    }
}

struct LockScreenNightView: View {
    let state: NightActivityAttributes.ContentState

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(state.isOnBreak ? "On a break" : "Game night")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(WidgetPalette.goldLight)
                    NightClock(state: state)
                        .font(.system(size: 38, weight: .bold, design: .rounded).monospacedDigit())
                        .foregroundStyle(WidgetPalette.textPrimary)
                }
                Spacer(minLength: 12)
                VStack(alignment: .trailing, spacing: 2) {
                    Text("On the table")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(WidgetPalette.goldLight)
                    Text(ActivityMoney.format(minor: state.inPlayMinor, currencyCode: state.currencyCode))
                        .font(.title2.weight(.bold).monospacedDigit())
                        .foregroundStyle(WidgetPalette.textPrimary)
                    Text("\(state.players) players")
                        .font(.caption)
                        .foregroundStyle(WidgetPalette.textSecondary)
                }
            }
            HStack {
                Text(state.isOnBreak ? "The clock is stopped." : "Time on a break isn't counted as playing.")
                    .font(.caption)
                    .foregroundStyle(WidgetPalette.textSecondary)
                Spacer()
                BreakLink(isOnBreak: state.isOnBreak)
            }
        }
        .padding(16)
    }
}
