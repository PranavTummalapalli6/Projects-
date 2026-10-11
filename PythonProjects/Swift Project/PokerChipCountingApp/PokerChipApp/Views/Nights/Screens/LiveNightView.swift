//
//  LiveNightView.swift
//  PokerChipApp
//
//  The night in progress. The clock isn't a counter this screen owns — it is
//  worked out from the night's start time, so closing the app or popping back
//  never loses or restarts it. Every player has a card with what they have put
//  in and a one-tap rebuy that can be undone; calling the game turns the same
//  screen into the cash-out list.
//

import SwiftUI
import UIKit

struct LiveNightView: View {
    let nightID: UUID

    @EnvironmentObject private var store: NightStore
    @EnvironmentObject private var coordinator: NavigationCoordinator

    @ScaledMetric(relativeTo: .largeTitle) private var clockSize: CGFloat = 60
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    @State private var sheet: PlayerSheet?
    @State private var confirmEnd = false
    @State private var confirmDelete = false
    @State private var playerToRemove: PlayerLedger?
    @State private var lastRebuy: RebuyUndo?
    @State private var showsTableCard = false

    private struct RebuyUndo: Equatable {
        let playerID: UUID
        let playerName: String
        let eventID: UUID
        let amountMinor: Int
    }

    var body: some View {
        Group {
            if let night = store.night(nightID) {
                if night.isSettled {
                    closedNight
                } else {
                    content(night)
                }
            } else if store.phase == .loading {
                VStack(spacing: Spacing.md) {
                    SkeletonView(cornerRadius: Radius.card).frame(height: 160)
                    SkeletonView(cornerRadius: Radius.card).frame(height: 110)
                    SkeletonView(cornerRadius: Radius.card).frame(height: 110)
                }
                .padding(Spacing.gutter)
            } else {
                EmptyState(
                    icon: "questionmark.folder",
                    title: "This night isn't here any more",
                    message: "It may have been deleted on another device.",
                    actionTitle: "Back to home"
                ) { coordinator.popToRoot() }
                .padding(Spacing.gutter)
                .pokerReadableWidth()
            }
        }
        .background(PokerBackground())
        .navigationTitle("Game night")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if store.night(nightID) != nil {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        if let night = store.night(nightID), TableCardContent(night: night) != nil {
                            Button { showsTableCard = true } label: {
                                Label("Show the chip values", systemImage: "rectangle.landscape.rotate")
                            }
                            .accessibilityIdentifier("night.tableCard")
                        }
                        Button(role: .destructive) { confirmDelete = true } label: {
                            Label("Delete this night", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .foregroundStyle(.pokerTextSecondary)
                            .frame(width: Spacing.minTapTarget, height: Spacing.minTapTarget)
                    }
                    .accessibilityLabel("More")
                    .accessibilityIdentifier("night.menu")
                }
            }
        }
        .sheet(item: $sheet) { sheet in
            PlayerSheetContent(sheet: sheet, nightID: nightID)
                .environmentObject(store)
        }
        .fullScreenCover(isPresented: $showsTableCard) {
            if let night = store.night(nightID), let content = TableCardContent(night: night) {
                TableCardView(content: content)
            }
        }
        .confirmationDialog("End the night?", isPresented: $confirmEnd, titleVisibility: .visible) {
            Button("End night") { endNight() }
                .accessibilityIdentifier("night.end.confirm")
            Button("Keep playing", role: .cancel) {}
        } message: {
            Text("The clock stops. Next, each player cashes out their chips.")
        }
        .confirmationDialog("Delete this night?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete night", role: .destructive) {
                store.delete(nightID)
                coordinator.popToRoot()
            }
            Button("Keep it", role: .cancel) {}
        } message: {
            Text("Everything recorded for it — buy-ins, cash-outs and notes — goes with it.")
        }
        .confirmationDialog(
            "Remove \(playerToRemove?.name ?? "this player")?",
            isPresented: Binding(get: { playerToRemove != nil }, set: { if !$0 { playerToRemove = nil } }),
            titleVisibility: .visible
        ) {
            Button("Remove from the night", role: .destructive) {
                if let player = playerToRemove { store.mutate(nightID) { $0.removePlayer(player.id) } }
                playerToRemove = nil
            }
            Button("Keep", role: .cancel) { playerToRemove = nil }
        } message: {
            Text("Their buy-ins come out of the night's totals.")
        }
        .onAppear(perform: updateIdleTimer)
        // A night in progress will probably end with a photo; wake the counting service now.
        .task { if store.night(nightID)?.isLive == true { Prewarm.countingService() } }
        .onChange(of: store.night(nightID)?.isLive) { _ in updateIdleTimer() }
        .onDisappear {
            // The phone may sleep again once this screen is gone.
            UIApplication.shared.isIdleTimerDisabled = false
        }
    }

    // MARK: Content

    private func content(_ night: GameNight) -> some View {
        ScrollView {
            VStack(spacing: Spacing.lg) {
                StepIndicator(current: night.isLive ? 2 : 3)

                clockCard(night)

                if !night.isLive {
                    InlineBanner(
                        kind: .info,
                        message: night.allCashedOut
                            ? "Everyone has cashed out. Check the bank next."
                            : "The game is over. Cash each player out, then check the bank.",
                        actionTitle: "Resume play"
                    ) {
                        store.mutate(nightID) { $0.resumePlay() }
                    }
                    .accessibilityIdentifier("night.endedBanner")
                }

                boardCard(night)

                VStack(spacing: Spacing.md) {
                    ForEach(night.players) { player in
                        playerCard(player, in: night)
                    }
                }

                PokerButton(title: "Add a player", systemImage: "person.badge.plus", kind: .secondary) {
                    sheet = .addPlayer
                }
                .accessibilityIdentifier("night.addPlayer")

                // At accessibility sizes this note would take a third of the screen in the pinned bar.
                if dynamicTypeSize.isAccessibilitySize, !night.isLive, !night.allCashedOut {
                    stillToCashOut(night)
                }
            }
            .padding(.horizontal, Spacing.gutter)
            .padding(.vertical, Spacing.lg)
            .pokerReadableWidth()
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            bottomBar(night)
        }
    }

    // MARK: Clock and board

    private func clockCard(_ night: GameNight) -> some View {
        VStack(spacing: Spacing.md) {
            HStack(spacing: Spacing.sm) {
                PulsingDot(isActive: night.isLive && !night.hasOpenPause)
                Text(night.isLive ? (night.hasOpenPause ? "On a break" : "Timing") : "Game over")
                    .font(.pokerCaption)
                    .textCase(.uppercase)
                    .tracking(0.8)
                    .foregroundStyle(Color.pokerPurpleLight)
                    .accessibilityIdentifier("night.status")
            }

            if night.isLive && !night.hasOpenPause {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    clockText(night.playtimeSeconds(at: context.date))
                }
            } else {
                clockText(night.playtimeSeconds())
            }

            Text("\(Money.format(cents: night.totalInMinor, currencyCode: night.currency)) in play · \(night.players.count) players")
                .font(.pokerFootnote)
                .foregroundStyle(.pokerTextSecondary)
                .accessibilityIdentifier("night.pot")

            if night.isLive {
                breakControls(night)
            }
        }
        .frame(maxWidth: .infinity)
        .pokerCard(padding: Spacing.xl)
        .accessibilityElement(children: .contain)
    }

    /// A break stops the clock; the time on it is never counted as time played.
    private func breakControls(_ night: GameNight) -> some View {
        VStack(spacing: Spacing.sm) {
            if night.hasOpenPause {
                PokerButton(title: "Resume play", systemImage: "play.fill") {
                    store.mutate(nightID) { $0.resumeFromPause() }
                    Haptics.selection()
                }
                .accessibilityIdentifier("night.resume")
            } else {
                PokerButton(title: "Take a break", systemImage: "pause.fill", kind: .secondary) {
                    store.mutate(nightID) { $0.pause() }
                    Haptics.selection()
                }
                .accessibilityIdentifier("night.break")
            }

            TimelineView(.periodic(from: .now, by: 15)) { context in
                let paused = night.pausedSeconds(at: context.date)
                if paused >= 60 {
                    Text("\(DurationFormat.compact(paused)) on breaks so far. That isn't counted as time played.")
                        .font(.pokerFootnote)
                        .foregroundStyle(.pokerTextSecondary)
                        .multilineTextAlignment(.center)
                        .accessibilityIdentifier("night.breakTime")
                }
            }
        }
    }

    private func clockText(_ seconds: Int) -> some View {
        Text(DurationFormat.clock(seconds))
            .font(.system(size: clockSize, weight: .bold, design: .rounded).monospacedDigit())
            .foregroundStyle(LinearGradient(colors: [.pokerGoldLight, .pokerGold], startPoint: .top, endPoint: .bottom))
            .lineLimit(1)
            .minimumScaleFactor(0.5)
            .accessibilityLabel("Time played")
            .accessibilityValue(DurationFormat.spoken(seconds))
            .accessibilityAddTraits(.updatesFrequently)
            .accessibilityIdentifier("night.clock")
    }

    /// Who has put in the most, as a running board of bars.
    private func boardCard(_ night: GameNight) -> some View {
        let ranked = night.playersByInvested
        let top = max(ranked.first?.totalInMinor ?? 1, 1)
        return VStack(alignment: .leading, spacing: Spacing.md) {
            SectionHeader(title: "Money in")
            ForEach(ranked) { player in
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    HStack {
                        Text(player.name).font(.pokerCallout).foregroundStyle(.pokerTextPrimary).lineLimit(1)
                        Spacer(minLength: Spacing.sm)
                        MoneyText(cents: player.totalInMinor, font: .pokerNumeric(.callout), color: .pokerGoldLight)
                    }
                    GeometryReader { proxy in
                        Capsule()
                            .fill(Color.pokerGold.opacity(0.55))
                            .frame(width: max(6, proxy.size.width * CGFloat(player.totalInMinor) / CGFloat(top)))
                    }
                    .frame(height: 6)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(player.name)
                .accessibilityValue("\(Money.spoken(cents: player.totalInMinor)) in")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .pokerCard()
        .pokerSpring(value: night.totalInMinor)
    }

    // MARK: Player cards

    private func playerCard(_ player: PlayerLedger, in night: GameNight) -> some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            HStack(alignment: .top, spacing: Spacing.sm) {
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    HStack(spacing: Spacing.sm) {
                        Text(player.name)
                            .font(.pokerHeadline)
                            .foregroundStyle(.pokerTextPrimary)
                            .lineLimit(2)
                        if night.myPlayerID == player.id {
                            Text("You")
                                .font(.pokerCaption)
                                .foregroundStyle(Color.black)
                                .padding(.horizontal, Spacing.sm)
                                .padding(.vertical, 2)
                                .background(Color.pokerGold)
                                .clipShape(Capsule())
                                .accessibilityLabel("That's you")
                        }
                    }
                    summaryLine(player, in: night)
                }
                Spacer(minLength: Spacing.sm)
                playerMenu(player, in: night)
            }

            actionButton(player, in: night)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .pokerCard()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("night.player.\(player.name)")
    }

    @ViewBuilder
    private func summaryLine(_ player: PlayerLedger, in night: GameNight) -> some View {
        let rebuys = player.rebuyCount
        let moneyIn = "In \(Money.format(cents: player.totalInMinor, currencyCode: night.currency))" + (rebuys > 0 ? " · \(rebuys) rebuy\(rebuys == 1 ? "" : "s")" : "")
        if let net = player.netMinor, let out = player.cashOutMinor {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text(moneyIn).font(.pokerFootnote).foregroundStyle(.pokerTextSecondary)
                HStack(spacing: Spacing.sm) {
                    Text("Cashed out \(Money.format(cents: out, currencyCode: night.currency))")
                        .font(.pokerFootnote)
                        .foregroundStyle(.pokerTextSecondary)
                    MoneyText(cents: net, signed: true, font: .pokerNumeric(.footnote), color: net >= 0 ? .pokerPositive : .pokerNegative)
                }
            }
            .accessibilityElement(children: .combine)
        } else {
            Text(moneyIn)
                .font(.pokerFootnote)
                .foregroundStyle(.pokerTextSecondary)
                .accessibilityIdentifier("night.in.\(player.name)")
        }
    }

    @ViewBuilder
    private func actionButton(_ player: PlayerLedger, in night: GameNight) -> some View {
        if player.isCashedOut {
            PokerButton(title: "Edit cash-out", kind: .quiet) {
                coordinator.push(.cashOut(CashOutTarget(nightID: night.id, playerID: player.id)))
            }
            .accessibilityIdentifier("night.editCashOut.\(player.name)")
        } else if night.isLive {
            PokerButton(
                title: "Rebuy +\(Money.format(cents: night.defaultBuyInMinor, currencyCode: night.currency))",
                systemImage: "plus",
                kind: .secondary
            ) {
                rebuy(player, in: night)
            }
            .accessibilityLabel("Rebuy for \(player.name)")
            .accessibilityValue(Money.spoken(cents: night.defaultBuyInMinor))
            .accessibilityIdentifier("night.rebuy.\(player.name)")
        } else {
            PokerButton(title: "Cash out", systemImage: "banknote") {
                coordinator.push(.cashOut(CashOutTarget(nightID: night.id, playerID: player.id)))
            }
            .accessibilityLabel("Cash out \(player.name)")
            .accessibilityIdentifier("night.cashOut.\(player.name)")
        }
    }

    private func playerMenu(_ player: PlayerLedger, in night: GameNight) -> some View {
        Menu {
            if !player.isCashedOut {
                Button {
                    coordinator.push(.cashOut(CashOutTarget(nightID: night.id, playerID: player.id)))
                } label: {
                    Label("Cash out…", systemImage: "banknote")
                }
            }
            Button { sheet = .history(player.id) } label: {
                Label("Buy-ins", systemImage: "list.bullet")
            }
            Button { sheet = .rename(player.id) } label: {
                Label("Rename", systemImage: "pencil")
            }
            if night.myPlayerID != player.id {
                Button { store.mutate(nightID) { $0.setMe(player.id) } } label: {
                    Label("This is me", systemImage: "person.fill.checkmark")
                }
            }
            if !player.isCashedOut {
                Button(role: .destructive) { playerToRemove = player } label: {
                    Label("Remove from the night", systemImage: "person.fill.xmark")
                }
            }
        } label: {
            Image(systemName: "ellipsis")
                .foregroundStyle(.pokerTextSecondary)
                .frame(width: Spacing.minTapTarget, height: Spacing.minTapTarget)
                .contentShape(Rectangle())
        }
        .accessibilityLabel("More for \(player.name)")
        .accessibilityIdentifier("night.playerMenu.\(player.name)")
    }

    // MARK: Bottom bar

    private func bottomBar(_ night: GameNight) -> some View {
        VStack(spacing: Spacing.sm) {
            if let undo = lastRebuy {
                InlineBanner(
                    kind: .success,
                    message: "\(undo.playerName) rebought \(Money.format(cents: undo.amountMinor, currencyCode: night.currency)).",
                    actionTitle: "Undo"
                ) {
                    store.mutate(nightID) { $0.undoBuyIn(playerID: undo.playerID, eventID: undo.eventID) }
                    Haptics.selection()
                    lastRebuy = nil
                }
                .accessibilityIdentifier("night.undoBanner")
                .transition(.opacity)
            }

            if night.isLive {
                PokerButton(title: "End night", systemImage: "flag.checkered") { confirmEnd = true }
                    .accessibilityIdentifier("night.end")
            } else {
                PokerButton(title: "Check the bank", systemImage: "scalemass", isEnabled: night.allCashedOut) {
                    coordinator.push(.bankCheck(night.id))
                }
                .accessibilityHint(night.allCashedOut ? "" : "\(night.players.count - night.cashedOutCount) still to cash out.")
                .accessibilityIdentifier("night.bank")
                if !night.allCashedOut, !dynamicTypeSize.isAccessibilitySize {
                    stillToCashOut(night)
                }
            }
        }
        .pokerBottomBar()
        .pokerSpring(value: lastRebuy)
        .task(id: lastRebuy?.eventID) {
            guard lastRebuy != nil else { return }
            try? await Task.sleep(nanoseconds: 6_000_000_000)
            if !Task.isCancelled { lastRebuy = nil }
        }
    }

    private func stillToCashOut(_ night: GameNight) -> some View {
        let remaining = night.players.count - night.cashedOutCount
        return Text("\(remaining) player\(remaining == 1 ? "" : "s") still to cash out.")
            .font(.pokerFootnote)
            .foregroundStyle(.pokerTextSecondary)
            .frame(maxWidth: .infinity, alignment: dynamicTypeSize.isAccessibilitySize ? .leading : .center)
            .accessibilityIdentifier("night.remaining")
    }

    // MARK: Closed

    private var closedNight: some View {
        EmptyState(
            icon: "checkmark.seal",
            title: "This night is closed",
            message: "It has been settled. You can look at the result.",
            actionTitle: "View result"
        ) { coordinator.path = [.result(nightID)] }
        .padding(Spacing.gutter)
        .pokerReadableWidth()
    }

    // MARK: Actions

    private func rebuy(_ player: PlayerLedger, in night: GameNight) {
        var event: BuyInEvent?
        store.mutate(night.id) { event = $0.rebuy(player.id) }
        guard let event else { return }
        Haptics.success()
        lastRebuy = RebuyUndo(playerID: player.id, playerName: player.name, eventID: event.id, amountMinor: event.amountMinor)
    }

    private func endNight() {
        store.mutate(nightID) { $0.endPlay() }
        lastRebuy = nil
        Haptics.success()
    }

    private func updateIdleTimer() {
        // Keep the screen awake while the game is running so the clock stays in view.
        UIApplication.shared.isIdleTimerDisabled = store.night(nightID)?.isLive == true
    }
}

/// A small dot that blinks once a second, in step with the clock, while the clock runs. Still under Reduce Motion.
///
/// It used to pulse with a repeating animation, which keeps the screen redrawing every frame for as long as the
/// night lasts: in a profile of this screen that was most of the main thread's work (about 15% of a core in a
/// Debug build on the Simulator, against almost nothing on Home), and the screen is kept awake for hours. One
/// redraw a second costs next to nothing.
private struct PulsingDot: View {
    let isActive: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if isActive && !reduceMotion {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                dot(dim: Int(context.date.timeIntervalSinceReferenceDate) % 2 == 0)
            }
        } else {
            dot(dim: false)
        }
    }

    private func dot(dim: Bool) -> some View {
        Circle()
            .fill(isActive ? Color.pokerNegative : Color.pokerTextTertiary)
            .frame(width: 8, height: 8)
            .opacity(dim ? 0.25 : 1)
            .accessibilityHidden(true)
    }
}
