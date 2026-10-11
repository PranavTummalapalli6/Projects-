//
//  SettleUpView.swift
//  PokerChipApp
//
//  Who pays whom. Everyone's net is turned into the fewest payments that settle
//  the table exactly — the person owed the most is matched with the person who
//  owes the most — and can be shared as text or as an image for the group chat.
//  The app only works the numbers out; it never moves money.
//

import SwiftUI
import UIKit

struct SettleUpView: View {
    let nightID: UUID

    @EnvironmentObject private var store: NightStore
    @EnvironmentObject private var coordinator: NavigationCoordinator
    @Environment(\.displayScale) private var displayScale
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    @State private var shareImage: UIImage?

    var body: some View {
        Group {
            if let night = store.night(nightID) {
                if let entries = night.settlementEntries() {
                    content(night, entries: entries)
                } else {
                    EmptyState(
                        icon: "scalemass",
                        title: "The bank doesn't balance yet",
                        message: "Cash everyone out and settle the difference first.",
                        actionTitle: "Check the bank"
                    ) { coordinator.pop() }
                    .padding(Spacing.gutter)
                    .pokerReadableWidth()
                }
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
        .navigationTitle("Settle up")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: Content

    private func content(_ night: GameNight, entries: [NetEntry]) -> some View {
        let payments = Settlement.payments(for: entries).payments
        return ScrollView {
            VStack(spacing: Spacing.lg) {
                StepIndicator(current: 4)

                paymentsCard(night, payments: payments)

                resultsCard(night, entries: entries)

                shareButtons(night, payments: payments, entries: entries)

                // At accessibility sizes the note would take a third of the screen in the pinned bar.
                if dynamicTypeSize.isAccessibilitySize { closingNote }
            }
            .padding(.horizontal, Spacing.gutter)
            .padding(.vertical, Spacing.lg)
            .pokerReadableWidth()
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: Spacing.sm) {
                PokerButton(title: "Close the night", systemImage: "checkmark.seal") { close(night) }
                    .accessibilityIdentifier("settle.close")
                if !dynamicTypeSize.isAccessibilitySize { closingNote }
            }
            .pokerBottomBar()
        }
        .task(id: payments) { render(night, entries: entries, payments: payments) }
    }

    private var closingNote: some View {
        Text("Closing saves the night to your history. You can reopen it to fix a mistake.")
            .font(.pokerFootnote)
            .foregroundStyle(.pokerTextSecondary)
            .multilineTextAlignment(dynamicTypeSize.isAccessibilitySize ? .leading : .center)
            .frame(maxWidth: .infinity, alignment: dynamicTypeSize.isAccessibilitySize ? .leading : .center)
    }

    private func paymentsCard(_ night: GameNight, payments: [Payment]) -> some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            SectionHeader(title: "Payments")
                .accessibilityIdentifier("settle.payments")

            if payments.isEmpty {
                Label("Everyone broke even. Nobody owes anything.", systemImage: "equal.circle.fill")
                    .font(.pokerCallout)
                    .foregroundStyle(.pokerTextPrimary)
                    .accessibilityIdentifier("settle.noPayments")
            } else {
                ForEach(payments) { payment in
                    paymentRow(payment, currency: night.currency)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .pokerCard()
    }

    private func paymentRow(_ payment: Payment, currency: String) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: Spacing.sm) {
                Text(payment.fromName).font(.pokerHeadline).foregroundStyle(.pokerTextPrimary)
                Image(systemName: "arrow.right").font(.caption.weight(.bold)).foregroundStyle(.pokerTextTertiary).accessibilityHidden(true)
                Text(payment.toName).font(.pokerHeadline).foregroundStyle(.pokerTextPrimary)
                Spacer(minLength: Spacing.sm)
                MoneyText(cents: payment.amountMinor, font: .pokerNumeric(.headline), color: .pokerGoldLight)
            }
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text("\(payment.fromName) pays \(payment.toName)").font(.pokerHeadline).foregroundStyle(.pokerTextPrimary)
                MoneyText(cents: payment.amountMinor, font: .pokerNumeric(.headline), color: .pokerGoldLight)
            }
        }
        .frame(minHeight: Spacing.minTapTarget)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(payment.fromName) pays \(payment.toName)")
        .accessibilityValue(Money.spoken(cents: payment.amountMinor, currencyCode: currency))
        .accessibilityIdentifier("settle.pay.\(payment.fromName).\(payment.toName)")
    }

    private func resultsCard(_ night: GameNight, entries: [NetEntry]) -> some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            SectionHeader(title: "Results")
                .accessibilityIdentifier("settle.results")
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

            if let resolution = night.activeResolution {
                Text(resolutionNote(resolution, night: night))
                    .font(.pokerFootnote)
                    .foregroundStyle(.pokerTextSecondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .pokerCard()
    }

    private func resolutionNote(_ resolution: BankResolution, night: GameNight) -> String {
        let amount = Money.format(cents: abs(resolution.deltaMinor), currencyCode: night.currency)
        switch resolution.kind {
        case .tip:
            return "The \(amount) shortfall was recorded as a tip or rake."
        case .assign:
            let name = night.players.first { $0.id == resolution.playerID }?.name ?? "one player"
            return "The \(amount) difference was put on \(name)'s count."
        case .split:
            return "The \(amount) difference was shared out evenly, cent by cent."
        }
    }

    // MARK: Sharing

    private func shareButtons(_ night: GameNight, payments: [Payment], entries: [NetEntry]) -> some View {
        VStack(spacing: Spacing.md) {
            ShareLink(item: Self.shareText(for: night, payments: payments)) {
                Label("Share as text", systemImage: "text.bubble")
                    .pokerSecondaryLabel()
            }
            .accessibilityIdentifier("settle.shareText")

            if let image = shareImage {
                ShareLink(
                    item: Image(uiImage: image),
                    preview: SharePreview("Settle up", image: Image(uiImage: image))
                ) {
                    Label("Share as image", systemImage: "photo")
                        .pokerSecondaryLabel()
                }
                .accessibilityIdentifier("settle.shareImage")
            }
        }
    }

    /// "Game night, Oct 9 · Pat's garage" then one "Sam → Alex $23.50" per line.
    static func shareText(for night: GameNight, payments: [Payment]) -> String {
        var header = "Game night, " + night.startedAt.formatted(.dateTime.month(.abbreviated).day())
        if let place = night.location { header += " · \(place)" }
        let body = payments.isEmpty
            ? "Everyone broke even."
            : Settlement.text(for: payments, currency: night.currency)
        return header + "\n" + body
    }

    @MainActor
    private func render(_ night: GameNight, entries: [NetEntry], payments: [Payment]) {
        let renderer = ImageRenderer(content: SettlementCard(night: night, payments: payments).environment(\.colorScheme, .dark))
        renderer.scale = displayScale
        shareImage = renderer.uiImage
    }

    // MARK: Actions

    private func close(_ night: GameNight) {
        var closed = false
        store.mutate(night.id) { closed = $0.settle() }
        guard closed || store.night(night.id)?.isSettled == true else {
            Haptics.warning()
            return
        }
        Haptics.success()
        coordinator.path = [.result(night.id)]
    }
}

// MARK: - The shareable card

/// What gets shared as an image: a clean card with the date, the place and
/// who pays whom.
struct SettlementCard: View {
    let night: GameNight
    let payments: [Payment]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("SETTLE UP")
                    .font(.system(.caption, design: .rounded).weight(.heavy))
                    .tracking(1.2)
                    .foregroundStyle(Color.pokerPurpleLight)
                Text(night.startedAt.formatted(.dateTime.weekday(.wide).month(.wide).day()))
                    .font(.system(.title2, design: .rounded).weight(.bold))
                    .foregroundStyle(.white)
                if let place = night.location {
                    Text(place).font(.footnote).foregroundStyle(.white.opacity(0.72))
                }
            }

            Divider().overlay(Color.white.opacity(0.18))

            if payments.isEmpty {
                Text("Everyone broke even.")
                    .font(.headline)
                    .foregroundStyle(.white)
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(payments) { payment in
                        HStack(spacing: 8) {
                            Text(payment.fromName).font(.headline).foregroundStyle(.white)
                            Image(systemName: "arrow.right").font(.caption.weight(.bold)).foregroundStyle(.white.opacity(0.6))
                            Text(payment.toName).font(.headline).foregroundStyle(.white)
                            Spacer(minLength: 12)
                            Text(Money.format(cents: payment.amountMinor, currencyCode: night.currency))
                                .font(.system(.headline, design: .rounded).weight(.bold).monospacedDigit())
                                .foregroundStyle(Color.pokerGoldLight)
                        }
                    }
                }
            }

            Text("Chip Counter")
                .font(.system(.caption2, design: .rounded).weight(.semibold))
                .foregroundStyle(.white.opacity(0.5))
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(24)
        .frame(width: 360, alignment: .leading)
        .background(
            LinearGradient(colors: [.pokerBackgroundTop, .pokerBackgroundBottom], startPoint: .top, endPoint: .bottom)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous).stroke(Color.pokerGold.opacity(0.4), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
    }
}
