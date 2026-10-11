//
//  ResultView.swift
//  PokerChipApp
//
//  How the night ended: your result (after the bank was reconciled), how long
//  you played, what that is per hour, everyone's results and who paid whom.
//  Restrained on purpose — a loss is stated plainly, not dramatised.
//

import SwiftUI

struct ResultView: View {
    let nightID: UUID

    @EnvironmentObject private var coordinator: NavigationCoordinator
    @EnvironmentObject private var store: NightStore

    @ScaledMetric(relativeTo: .largeTitle) private var netSize: CGFloat = 52

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
        .navigationTitle("Result")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: Content

    private func content(_ night: GameNight) -> some View {
        let summary = NightSummary(night: night)
        let entries = night.settlementEntries() ?? []
        let payments = night.payments() ?? []

        return ScrollView {
            VStack(spacing: Spacing.lg) {
                if let net = summary.myNetMinor {
                    netCard(net, currency: night.currency)
                } else {
                    potCard(summary.potMinor, currency: night.currency)
                }

                syncBanner

                HStack(spacing: Spacing.md) {
                    StatTile(
                        label: "Time played",
                        value: DurationFormat.compact(summary.playtimeSeconds),
                        spokenValue: DurationFormat.spoken(summary.playtimeSeconds)
                    )
                    if summary.myNetMinor != nil {
                        StatTile(
                            label: "Per hour",
                            value: summary.perHourMinor.map { Money.formatSigned(cents: $0, currencyCode: night.currency) } ?? "—",
                            valueColor: summary.perHourMinor.map { $0 >= 0 ? Color.pokerPositive : Color.pokerNegative } ?? Color.pokerTextSecondary
                        )
                    } else {
                        StatTile(label: "Players", value: "\(night.players.count)")
                    }
                }

                everyoneCard(entries, night: night)

                if !payments.isEmpty {
                    paymentsCard(payments, night: night)
                }

                actions(night, payments: payments)
            }
            .padding(.horizontal, Spacing.gutter)
            .padding(.vertical, Spacing.lg)
            .pokerReadableWidth()
        }
    }

    // MARK: Pieces

    private func netCard(_ net: Int, currency: String) -> some View {
        VStack(spacing: Spacing.sm) {
            Text("Your result")
                .font(.pokerCaption)
                .textCase(.uppercase)
                .tracking(0.8)
                .foregroundStyle(Color.pokerPurpleLight)

            Text(Money.formatSigned(cents: net, currencyCode: currency))
                .font(.system(size: netSize, weight: .heavy, design: .rounded).monospacedDigit())
                .foregroundStyle(net >= 0 ? Color.pokerPositive : Color.pokerNegative)
                .lineLimit(1)
                .minimumScaleFactor(0.5)

            Text(net == 0 ? "You finished even." : "For this night.")
                .font(.pokerFootnote)
                .foregroundStyle(.pokerTextSecondary)
        }
        .frame(maxWidth: .infinity)
        .pokerCard(padding: Spacing.xl)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Your result")
        .accessibilityValue(net == 0 ? "Even" : "\(net > 0 ? "Up" : "Down") \(Money.spoken(cents: abs(net), currencyCode: currency))")
        .accessibilityIdentifier("result.net")
    }

    private func potCard(_ pot: Int, currency: String) -> some View {
        VStack(spacing: Spacing.sm) {
            Text("In play")
                .font(.pokerCaption)
                .textCase(.uppercase)
                .tracking(0.8)
                .foregroundStyle(Color.pokerPurpleLight)
            MoneyText(cents: pot, font: .system(size: netSize, weight: .heavy, design: .rounded).monospacedDigit(), color: .pokerGoldLight)
            Text("You weren't playing in this one.")
                .font(.pokerFootnote)
                .foregroundStyle(.pokerTextSecondary)
        }
        .frame(maxWidth: .infinity)
        .pokerCard(padding: Spacing.xl)
        .accessibilityIdentifier("result.pot")
    }

    @ViewBuilder
    private var syncBanner: some View {
        if store.pendingCount == 0 {
            InlineBanner(kind: .success, message: "Saved to your account.")
        } else {
            InlineBanner(kind: .info, message: "Saved on this iPhone. It will back up to your account when you're online.")
        }
    }

    private func everyoneCard(_ entries: [NetEntry], night: GameNight) -> some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            SectionHeader(title: "Everyone")
            ForEach(Array(entries.enumerated()), id: \.offset) { _, entry in
                HStack {
                    Text(entry.name).foregroundStyle(.pokerTextPrimary)
                    if entry.id == nil {
                        Text("(house)").font(.pokerFootnote).foregroundStyle(.pokerTextTertiary)
                    }
                    Spacer(minLength: Spacing.sm)
                    MoneyText(
                        cents: entry.netMinor,
                        signed: true,
                        font: .pokerNumeric(.body),
                        color: entry.netMinor == 0 ? .pokerTextSecondary : (entry.netMinor > 0 ? .pokerPositive : .pokerNegative)
                    )
                }
                .frame(minHeight: Spacing.minTapTarget)
                .accessibilityElement(children: .combine)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .pokerCard()
        .accessibilityIdentifier("result.everyone")
    }

    private func paymentsCard(_ payments: [Payment], night: GameNight) -> some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            SectionHeader(title: "Payments")
            ForEach(payments) { payment in
                HStack {
                    Text("\(payment.fromName) → \(payment.toName)").foregroundStyle(.pokerTextPrimary)
                    Spacer(minLength: Spacing.sm)
                    MoneyText(cents: payment.amountMinor, font: .pokerNumeric(.body), color: .pokerGoldLight)
                }
                .frame(minHeight: Spacing.minTapTarget)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(payment.fromName) pays \(payment.toName)")
                .accessibilityValue(Money.spoken(cents: payment.amountMinor, currencyCode: night.currency))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .pokerCard()
    }

    private func actions(_ night: GameNight, payments: [Payment]) -> some View {
        VStack(spacing: Spacing.md) {
            PokerButton(title: "View Poker Health", systemImage: "heart.text.square") {
                coordinator.push(.pokerHealth)
            }
            .accessibilityIdentifier("result.health")

            ShareLink(item: SettleUpView.shareText(for: night, payments: payments)) {
                Label("Share payments", systemImage: "square.and.arrow.up")
                    .pokerSecondaryLabel()
            }
            .accessibilityIdentifier("result.share")

            ShareCardButton(title: "Share a night summary", previewTitle: "Game night", key: "\(night.updatedAt.timeIntervalSince1970)", card: NightSummaryCard(night: night))
                .accessibilityIdentifier("result.shareSummary")

            PokerButton(title: "Reopen to fix a mistake", kind: .secondary) {
                store.mutate(night.id) { $0.reopen() }
                coordinator.path = [.night(night.id)]
            }
            .accessibilityIdentifier("result.reopen")

            PokerButton(title: "Done", kind: .quiet) {
                coordinator.popToRoot()
            }
            .accessibilityIdentifier("result.done")
        }
    }
}
