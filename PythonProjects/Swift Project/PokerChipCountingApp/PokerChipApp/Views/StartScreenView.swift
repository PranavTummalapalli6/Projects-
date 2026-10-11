//
//  StartScreenView.swift
//  PokerChipApp
//
//  Created by Pranav on 4/2/25.
//
//  Home. Everything a returning player wants one tap away: pick the game back
//  up, start the same game again, see how the last one went and how much
//  they've played this week.
//

import SwiftUI

struct StartScreenView: View {
    @EnvironmentObject private var coordinator: NavigationCoordinator
    @EnvironmentObject private var store: NightStore
    @EnvironmentObject private var sync: NightSync
    @EnvironmentObject private var auth: AuthViewModel
    @State private var lastSetup: GameSetup?
    @State private var confirmDiscard = false
    @AppStorage(PrefKey.weeklyHoursCap) private var weeklyHoursCap = AppPreferences.defaultWeeklyHoursCap
    @AppStorage(PrefKey.weeklyLossLimit) private var weeklyLossLimit = 0.0
    @AppStorage(PrefKey.coolOffUntil) private var coolOffUntil = 0.0
    @AppStorage(PrefKey.dismissedNudge) private var dismissedNudge = ""

    /// Nothing played yet: Home also explains how a night goes.
    private var isFirstRun: Bool {
        store.phase == .ready && store.nights.isEmpty && lastSetup == nil
    }

    private var limits: PlayLimits {
        PlayLimits(
            weeklyHours: weeklyHoursCap,
            weeklyLoss: weeklyLossLimit > 0 ? weeklyLossLimit : nil,
            reminderHours: nil,
            coolOffUntil: coolOffUntil > 0 ? Date(timeIntervalSince1970: coolOffUntil) : nil
        )
    }

    private var coolingOff: Bool { HealthyPlay.isCoolingOff(limits) }

    /// A gentle word about the week, unless they've already seen it.
    private var nudge: HealthyPlay.Nudge? {
        guard !coolingOff, store.phase == .ready, let nudge = HealthyPlay.nudge(nights: store.nights, limits: limits) else { return nil }
        return nudge.isHidden(byDismissed: dismissedNudge) ? nil : nudge
    }

    private var lastResult: (night: GameNight, summary: NightSummary)? {
        store.nights.first { $0.isSettled && $0.me != nil }.map { ($0, NightSummary(night: $0)) }
    }

    var body: some View {
        let open = store.openNight
        ScrollView {
            VStack(spacing: Spacing.lg) {
                header

                if let night = open {
                    resumeCard(night)
                }

                statusBanners

                if coolingOff, let end = limits.coolOffUntil {
                    InlineBanner(
                        kind: .info,
                        message: "You're taking a break until \(end.formatted(date: .abbreviated, time: .shortened)). New nights are paused; your history is all still here."
                    )
                    .accessibilityIdentifier("home.coolOff")
                }

                if let nudge {
                    InlineBanner(kind: .info, message: nudge.message, actionTitle: "Got it") {
                        dismissedNudge = nudge.id
                    }
                    .accessibilityIdentifier("home.nudge")
                }

                PokerButton(title: "New game", systemImage: "plus", isEnabled: open == nil && !coolingOff) {
                    coordinator.push(.buyIn(nil))
                }
                .accessibilityIdentifier("home.newGame")

                if open != nil {
                    Text("Finish or delete the night in progress to start a new one.")
                        .font(.pokerFootnote)
                        .foregroundStyle(.pokerTextTertiary)
                        .multilineTextAlignment(.center)
                }

                if let setup = lastSetup, open == nil, !coolingOff {
                    Button {
                        coordinator.push(.players(setup))
                    } label: {
                        ListRow(
                            icon: "arrow.counterclockwise",
                            title: "Same as last game",
                            subtitle: summary(of: setup)
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("home.sameAsLast")
                }

                weeklyTile

                if let last = lastResult {
                    lastResultTile(last.night, last.summary)
                }

                if isFirstRun {
                    howItWorks
                }
            }
            .padding(.horizontal, Spacing.gutter)
            .padding(.bottom, Spacing.xl)
            .pokerReadableWidth()
        }
        .background(PokerBackground())
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { lastSetup = Stores.gameSetup.load() }
        .undoDeleteBanner()
        .confirmationDialog(
            "Delete this night?",
            isPresented: $confirmDiscard,
            titleVisibility: .visible
        ) {
            Button("Delete night", role: .destructive) {
                if let night = store.openNight { store.delete(night.id) }
            }
            Button("Keep it", role: .cancel) {}
        } message: {
            Text("Everything recorded for it — buy-ins, cash-outs and notes — goes with it.")
        }
    }

    // MARK: Pieces

    private var header: some View {
        let logo = Image("poker_chip_counter_no_bg")
            .resizable()
            .scaledToFit()
            .frame(width: 56, height: 56)
            .shadow(color: .pokerPurple.opacity(0.5), radius: 10)
            .accessibilityHidden(true)
        let title = PokerTitle(text: "Chip Counter", size: 30)

        return ViewThatFits(in: .horizontal) {
            HStack(spacing: Spacing.md) {
                logo
                title
                Spacer(minLength: 0)
            }
            VStack(alignment: .leading, spacing: Spacing.sm) {
                logo
                title
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, Spacing.sm)
    }

    private func resumeCard(_ night: GameNight) -> some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Label(night.isLive ? "Game night in progress" : "Cashing out", systemImage: night.isLive ? "timer" : "banknote")
                .font(.pokerCaption)
                .textCase(.uppercase)
                .tracking(0.8)
                .foregroundStyle(Color.pokerGoldLight)

            if night.isLive && !night.hasOpenPause {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    DurationText(
                        seconds: night.playtimeSeconds(at: context.date),
                        style: .clock,
                        font: .pokerNumeric(.largeTitle),
                        color: .pokerTextPrimary
                    )
                }
            } else {
                DurationText(
                    seconds: night.playtimeSeconds(),
                    style: .clock,
                    font: .pokerNumeric(.largeTitle),
                    color: .pokerTextPrimary
                )
            }

            Text(resumeSubtitle(night))
                .font(.pokerFootnote)
                .foregroundStyle(.pokerTextSecondary)

            HStack(spacing: Spacing.md) {
                PokerButton(title: "Resume") {
                    coordinator.open(night: night.id)
                }
                .accessibilityIdentifier("home.resume")

                PokerButton(title: "Delete", kind: .destructive) {
                    confirmDiscard = true
                }
                .accessibilityIdentifier("home.discard")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .pokerCard()
        .overlay(
            RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                .stroke(Color.pokerGold.opacity(0.55), lineWidth: 1.5)
        )
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("home.resumeCard")
    }

    private func resumeSubtitle(_ night: GameNight) -> String {
        let pot = "\(Money.format(cents: night.totalInMinor, currencyCode: night.currency)) in play · \(night.players.count) players"
        if night.isLive { return night.hasOpenPause ? pot + " · on a break" : pot }
        return pot + " · \(night.cashedOutCount) of \(night.players.count) cashed out"
    }

    /// What the person should know about their data, in plain words: problems
    /// reading or saving, and whether it has been backed up.
    @ViewBuilder
    private var statusBanners: some View {
        StoreProblemBanners()

        if sync.refusedCount > 0 {
            InlineBanner(
                kind: .warning,
                message: sync.refusedCount == 1
                    ? "One night couldn't be backed up to your account. It's safe on this iPhone."
                    : "\(sync.refusedCount) nights couldn't be backed up to your account. They're safe on this iPhone."
            )
        }

        switch sync.status {
        case .offline where store.pendingCount > 0:
            InlineBanner(
                kind: .info,
                message: store.pendingCount == 1
                    ? "1 change is saved on this iPhone. It will back up when you're online."
                    : "\(store.pendingCount) changes are saved on this iPhone. They will back up when you're online."
            )
        case .failed(let message):
            InlineBanner(kind: .info, message: message, actionTitle: "Try now") {
                Task { await sync.sync(uid: auth.account?.uid) }
            }
        default:
            EmptyView()
        }
    }

    @ViewBuilder
    private var weeklyTile: some View {
        if store.phase == .loading {
            SkeletonView(cornerRadius: Radius.card)
                .frame(height: 88)
        } else if !store.nights.isEmpty {
            let summary = WeeklySummary.make(from: store.nights)
            Button {
                coordinator.push(.pokerHealth)
            } label: {
                weeklyContent(summary)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("home.weekly")
        }
    }

    private func weeklyContent(_ summary: WeeklySummary) -> some View {
        let hours = Double(summary.totalSeconds) / 3600
        let decay = min(1, max(0, hours / max(weeklyHoursCap, 1)))
        return HStack(spacing: Spacing.lg) {
            DecayingChipView(decay: decay)
                .frame(width: 56, height: 56)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text("This week")
                    .font(.pokerCaption)
                    .textCase(.uppercase)
                    .tracking(0.8)
                    .foregroundStyle(Color.pokerPurpleLight)
                DurationText(seconds: summary.totalSeconds, font: .pokerNumeric(.title2), color: .pokerGoldLight)
                Text("Poker Health")
                    .font(.pokerFootnote)
                    .foregroundStyle(.pokerTextSecondary)
            }

            Spacer(minLength: Spacing.sm)

            Image(systemName: "chevron.right")
                .font(.caption.weight(.bold))
                .foregroundStyle(.pokerTextTertiary)
                .accessibilityHidden(true)
        }
        .pokerCard()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Poker Health. You've played \(DurationFormat.spoken(summary.totalSeconds)) this week.")
        .accessibilityAddTraits(.isButton)
    }

    private func lastResultTile(_ night: GameNight, _ summary: NightSummary) -> some View {
        let net = summary.myNetMinor ?? 0
        let tone: Color = net >= 0 ? .pokerPositive : .pokerNegative
        let finished = night.settledAt ?? night.endedAt ?? night.startedAt
        return Button {
            coordinator.push(.result(night.id))
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: Spacing.md) {
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text("Last game")
                        .font(.pokerCaption)
                        .textCase(.uppercase)
                        .tracking(0.8)
                        .foregroundStyle(Color.pokerPurpleLight)
                    MoneyText(cents: net, signed: true, font: .pokerNumeric(.title2), color: tone)
                }
                Spacer(minLength: Spacing.sm)
                VStack(alignment: .trailing, spacing: Spacing.xs) {
                    DurationText(seconds: summary.playtimeSeconds, font: .pokerNumeric(.subheadline, weight: .semibold), color: .pokerTextPrimary)
                    Text(finished.formatted(.relative(presentation: .named)))
                        .font(.pokerFootnote)
                        .foregroundStyle(.pokerTextSecondary)
                }
            }
            .pokerCard()
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Last game")
        .accessibilityValue("\(net >= 0 ? "Up" : "Down") \(Money.spoken(cents: abs(net))), \(DurationFormat.spoken(summary.playtimeSeconds)), \(finished.formatted(.relative(presentation: .named)))")
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("home.lastResult")
    }

    /// The same five steps as the progress bar on the screens that follow.
    private var howItWorks: some View {
        let steps: [(title: String, detail: String)] = [
            ("Set up the night", "The buy-in, who's playing, and the chip colours you own."),
            ("Get chip values", "Values and counts that add up to the buy\u{2011}in exactly."),
            ("Play", "Rebuys are one tap and can be undone. The clock keeps running even if you close the app."),
            ("Cash out", "Count each player's chips — by hand or from a photo — or type an amount."),
            ("Settle up", "Check the bank adds up, then see who pays whom."),
        ]
        return VStack(alignment: .leading, spacing: Spacing.lg) {
            SectionHeader(title: "How a game night works")

            ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                HStack(alignment: .top, spacing: Spacing.md) {
                    Text("\(index + 1)")
                        .font(.pokerNumeric(.footnote))
                        .foregroundStyle(Color.black)
                        .frame(width: 24, height: 24)
                        .background(Circle().fill(Color.pokerGold))
                        .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        Text(step.title)
                            .font(.pokerHeadline)
                            .foregroundStyle(.pokerTextPrimary)
                        Text(step.detail)
                            .font(.pokerFootnote)
                            .foregroundStyle(.pokerTextSecondary)
                    }
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Step \(index + 1). \(step.title). \(step.detail)")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .pokerCard()
        .accessibilityIdentifier("home.howItWorks")
    }

    private func summary(of setup: GameSetup) -> String {
        let colors = setup.colors.count
        return "\(Money.format(setup.buyIn)) · \(setup.players) players · \(colors) chip \(colors == 1 ? "colour" : "colours")"
    }
}

struct StartScreenView_Previews: PreviewProvider {
    static var previews: some View {
        let store = NightStore(repository: MemoryNightRepository())
        return NavigationStack {
            StartScreenView()
                .environmentObject(NavigationCoordinator())
                .environmentObject(store)
                .environmentObject(NightSync(store: store))
                .environmentObject(AuthViewModel())
        }
    }
}
