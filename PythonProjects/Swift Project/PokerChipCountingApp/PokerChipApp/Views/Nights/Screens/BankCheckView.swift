//
//  BankCheckView.swift
//  PokerChipApp
//
//  Does the money add up? Everything put in should equal everything cashed
//  out. If it doesn't, nothing is rounded away: the difference is shown to the
//  cent and the host chooses what it was — a recount, a tip or rake, one
//  player's miscount, or shared out evenly.
//

import SwiftUI

struct BankCheckView: View {
    let nightID: UUID

    @EnvironmentObject private var store: NightStore
    @EnvironmentObject private var coordinator: NavigationCoordinator

    @State private var choosingPlayer = false
    @State private var choosingRecount = false
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Group {
            if let night = store.night(nightID) {
                content(night)
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
        .navigationTitle("Bank check")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: Content

    private func content(_ night: GameNight) -> some View {
        ScrollView {
            VStack(spacing: Spacing.lg) {
                StepIndicator(current: 4)

                totalsCard(night)

                if !night.allCashedOut {
                    InlineBanner(
                        kind: .warning,
                        message: "\(night.players.count - night.cashedOutCount) players haven't cashed out yet.",
                        actionTitle: "Back"
                    ) { coordinator.pop() }
                } else if night.bankDeltaMinor == 0 {
                    InlineBanner(kind: .success, message: "The bank balances to the cent. Nothing to resolve.")
                        .accessibilityIdentifier("bank.balanced")
                } else {
                    differenceSection(night)
                }

                // At accessibility sizes a hint in the pinned bar would take a third of the screen.
                if dynamicTypeSize.isAccessibilitySize { chooseHint(night) }
            }
            .padding(.horizontal, Spacing.gutter)
            .padding(.vertical, Spacing.lg)
            .pokerReadableWidth()
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: Spacing.sm) {
                PokerButton(title: "Settle up", systemImage: "arrow.left.arrow.right", isEnabled: night.isBalanced) {
                    coordinator.push(.settleUp(night.id))
                }
                .accessibilityHint(night.allCashedOut && !night.isBalanced ? "Choose what the difference was to continue." : "")
                .accessibilityIdentifier("bank.settle")
                if !dynamicTypeSize.isAccessibilitySize { chooseHint(night) }
            }
            .pokerBottomBar()
        }
    }

    @ViewBuilder
    private func chooseHint(_ night: GameNight) -> some View {
        if night.allCashedOut && !night.isBalanced {
            Text("Choose what the difference was to continue.")
                .font(.pokerFootnote)
                .foregroundStyle(.pokerTextSecondary)
                .frame(maxWidth: .infinity, alignment: dynamicTypeSize.isAccessibilitySize ? .leading : .center)
                .multilineTextAlignment(dynamicTypeSize.isAccessibilitySize ? .leading : .center)
        }
    }

    private func totalsCard(_ night: GameNight) -> some View {
        let delta = night.bankDeltaMinor
        let balanced = night.allCashedOut && delta == 0
        return VStack(spacing: Spacing.md) {
            row("Money in", night.totalInMinor, color: .pokerTextPrimary)
            row("Chips cashed out", night.totalOutMinor, color: .pokerTextPrimary)
            Divider().overlay(Color.white.opacity(0.12))
            let label = Text("Difference").font(.pokerHeadline).foregroundStyle(.pokerTextPrimary)
            let value = Group {
                if night.allCashedOut {
                    HStack(spacing: Spacing.sm) {
                        if balanced {
                            Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.pokerPositive).accessibilityHidden(true)
                        }
                        MoneyText(
                            cents: delta,
                            signed: delta != 0,
                            font: .pokerNumeric(.title3),
                            color: delta == 0 ? .pokerPositive : .pokerWarning
                        )
                    }
                } else {
                    Text("—").font(.pokerNumeric(.title3)).foregroundStyle(.pokerTextTertiary)
                }
            }
            ViewThatFits(in: .horizontal) {
                HStack { label; Spacer(); value }
                VStack(alignment: .leading, spacing: Spacing.xs) { label; value }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .pokerCard()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Money in \(Money.spoken(cents: night.totalInMinor)). Chips cashed out \(Money.spoken(cents: night.totalOutMinor)). " + (night.allCashedOut ? (delta == 0 ? "The bank balances." : "Difference \(delta > 0 ? "plus" : "minus") \(Money.spoken(cents: abs(delta)))") : "Not everyone has cashed out."))
        .accessibilityIdentifier("bank.totals")
    }

    /// Label and amount on one line; the amount goes underneath when the label needs the room.
    private func row(_ label: String, _ cents: Int, color: Color) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack {
                Text(label).foregroundStyle(.pokerTextSecondary)
                Spacer()
                MoneyText(cents: cents, font: .pokerNumeric(.body), color: color)
            }
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text(label).foregroundStyle(.pokerTextSecondary)
                MoneyText(cents: cents, font: .pokerNumeric(.body), color: color)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: The difference

    @ViewBuilder
    private func differenceSection(_ night: GameNight) -> some View {
        let delta = night.bankDeltaMinor
        let amount = Money.format(cents: abs(delta), currencyCode: night.currency)
        let active = night.activeResolution

        VStack(alignment: .leading, spacing: Spacing.md) {
            InlineBanner(
                kind: .warning,
                message: delta < 0
                    ? "The chips cashed out are \(amount) short of the money in. Nothing is rounded for you — choose what happened."
                    : "The chips cashed out are \(amount) more than the money in. Nothing is rounded for you — choose what happened."
            )
            .accessibilityIdentifier("bank.difference")

            SectionHeader(title: "What happened?")

            recountOption(night)

            if delta < 0 {
                optionButton(
                    icon: "banknote",
                    title: "It was a tip or rake",
                    subtitle: "The house keeps the \(amount). It shows up as its own line when you settle.",
                    isSelected: active?.kind == .tip,
                    identifier: "bank.tip"
                ) {
                    store.mutate(nightID) { $0.resolveBank(.tip) }
                    Haptics.selection()
                }
            }

            optionButton(
                icon: "person.fill.questionmark",
                title: "Put it on one player",
                subtitle: delta < 0
                    ? "That player's count is treated as \(amount) higher — they probably miscounted."
                    : "That player's count is treated as \(amount) lower — they probably miscounted.",
                isSelected: active?.kind == .assign,
                identifier: "bank.assign"
            ) {
                choosingPlayer.toggle()
            }

            if choosingPlayer || active?.kind == .assign {
                VStack(spacing: Spacing.sm) {
                    ForEach(night.players) { player in
                        Button {
                            store.mutate(nightID) { $0.resolveBank(.assign, playerID: player.id) }
                            choosingPlayer = false
                            Haptics.selection()
                        } label: {
                            HStack {
                                Text(player.name).foregroundStyle(.pokerTextPrimary)
                                Spacer()
                                if active?.kind == .assign && active?.playerID == player.id {
                                    Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.pokerGoldLight)
                                }
                            }
                            .frame(minHeight: Spacing.minTapTarget)
                            .padding(.horizontal, Spacing.md)
                            .background(Color.white.opacity(0.06))
                            .clipShape(RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("bank.assign.\(player.name)")
                        .accessibilityAddTraits(active?.kind == .assign && active?.playerID == player.id ? .isSelected : [])
                    }
                }
                .padding(.leading, Spacing.lg)
            }

            let shares = GameNight.evenShares(of: delta, among: night.players.count)
            optionButton(
                icon: "divide.circle",
                title: "Split it evenly",
                subtitle: "Shared out cent by cent across all \(night.players.count) players (\(shareRange(shares, currency: night.currency))). No one is rounded up or down.",
                isSelected: active?.kind == .split,
                identifier: "bank.split"
            ) {
                store.mutate(nightID) { $0.resolveBank(.split) }
                Haptics.selection()
            }
        }
    }

    private func shareRange(_ shares: [Int], currency: String) -> String {
        let low = shares.map(abs).min() ?? 0
        let high = shares.map(abs).max() ?? 0
        let lowText = Money.format(cents: low, currencyCode: currency)
        return low == high ? "\(lowText) each" : "\(lowText) to \(Money.format(cents: high, currencyCode: currency))"
    }

    /// A card like the others rather than a menu: a menu's label can't grow with the text size.
    private func recountOption(_ night: GameNight) -> some View {
        Button {
            choosingRecount = true
        } label: {
            optionLabel(
                icon: "arrow.counterclockwise",
                title: "Recount a player's chips",
                subtitle: "Often it's one stack counted wrong. Fix it and the difference updates.",
                isSelected: false
            )
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Choose whose chips to count again")
        .accessibilityIdentifier("bank.recount")
        .confirmationDialog("Whose chips should be counted again?", isPresented: $choosingRecount, titleVisibility: .visible) {
            ForEach(night.players) { player in
                Button(player.name) {
                    coordinator.push(.cashOut(CashOutTarget(nightID: night.id, playerID: player.id)))
                }
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    private func optionButton(
        icon: String,
        title: String,
        subtitle: String,
        isSelected: Bool,
        identifier: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            optionLabel(icon: icon, title: title, subtitle: subtitle, isSelected: isSelected)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier(identifier)
    }

    private func optionLabel(icon: String, title: String, subtitle: String, isSelected: Bool) -> some View {
        HStack(alignment: .top, spacing: Spacing.lg) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(Color.pokerGold)
                .frame(width: 40, height: 40)
                .background(Color.pokerGold.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text(title).font(.pokerHeadline).foregroundStyle(.pokerTextPrimary).multilineTextAlignment(.leading)
                Text(subtitle).font(.pokerFootnote).foregroundStyle(.pokerTextSecondary).multilineTextAlignment(.leading)
            }

            Spacer(minLength: Spacing.sm)

            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(Color.pokerGoldLight)
                    .accessibilityLabel("Chosen")
            }
        }
        .frame(minHeight: Spacing.minTapTarget)
        .pokerCard()
        .overlay(
            RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                .stroke(Color.pokerGold.opacity(isSelected ? 0.8 : 0), lineWidth: 1.5)
        )
        .contentShape(Rectangle())
    }
}
