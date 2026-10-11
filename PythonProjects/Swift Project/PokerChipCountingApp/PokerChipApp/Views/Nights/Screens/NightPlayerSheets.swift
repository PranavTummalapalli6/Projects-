//
//  NightPlayerSheets.swift
//  PokerChipApp
//
//  The small self-contained tasks on the live night: adding a late player,
//  renaming one, and looking at (and correcting) a player's buy-ins.
//

import SwiftUI

enum PlayerSheet: Identifiable, Hashable {
    case addPlayer
    case rename(UUID)
    case history(UUID)

    var id: String {
        switch self {
        case .addPlayer: return "add"
        case .rename(let id): return "rename-\(id.uuidString)"
        case .history(let id): return "history-\(id.uuidString)"
        }
    }
}

struct PlayerSheetContent: View {
    let sheet: PlayerSheet
    let nightID: UUID

    var body: some View {
        NavigationStack {
            switch sheet {
            case .addPlayer:
                NameSheet(nightID: nightID, playerID: nil)
            case .rename(let playerID):
                NameSheet(nightID: nightID, playerID: playerID)
            case .history(let playerID):
                BuyInHistorySheet(nightID: nightID, playerID: playerID)
            }
        }
        .presentationDetents([.medium, .large])
    }
}

// MARK: - Add or rename

/// One text field for a name. With no `playerID` it adds a late player.
private struct NameSheet: View {
    let nightID: UUID
    let playerID: UUID?

    @EnvironmentObject private var store: NightStore
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @FocusState private var focused: Bool

    private var night: GameNight? { store.night(nightID) }
    private var isAdding: Bool { playerID == nil }

    private var finalName: String {
        PlayerNaming.clean(name, fallbackNumber: (night?.players.count ?? 0) + 1)
    }

    private var isTaken: Bool {
        guard let night else { return false }
        return night.players.contains { $0.id != playerID && $0.name.lowercased() == finalName.lowercased() }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                TextField(isAdding ? "Name" : "New name", text: $name)
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled()
                    .submitLabel(.done)
                    .focused($focused)
                    .onSubmit(save)
                    .pokerTextField(isError: isTaken)
                    .accessibilityLabel(isAdding ? "Name of the new player" : "New name")
                    .accessibilityIdentifier("nameSheet.field")

                if isTaken {
                    Label("Someone here already has that name.", systemImage: "exclamationmark.circle.fill")
                        .font(.pokerFootnote)
                        .foregroundStyle(.pokerNegative)
                } else if isAdding, let night {
                    Text("They join in for \(Money.format(cents: night.defaultBuyInMinor, currencyCode: night.currency)). Leave the name blank to be called \(finalName).")
                        .font(.pokerFootnote)
                        .foregroundStyle(.pokerTextSecondary)
                }

                PokerButton(title: isAdding ? "Add player" : "Save", isEnabled: !isTaken, action: save)
                    .accessibilityIdentifier("nameSheet.save")
            }
            .padding(Spacing.gutter)
            .pokerReadableWidth()
        }
        .background(PokerBackground())
        .navigationTitle(isAdding ? "Add a player" : "Rename")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
        }
        .onAppear {
            if let playerID, let existing = night?.players.first(where: { $0.id == playerID }) {
                name = existing.name
            }
            focused = true
        }
    }

    private func save() {
        guard !isTaken else {
            Haptics.warning()
            return
        }
        if let playerID {
            store.mutate(nightID) { $0.renamePlayer(playerID, to: name) }
        } else {
            store.mutate(nightID) { $0.addPlayer(name: name) }
        }
        Haptics.success()
        dismiss()
    }
}

// MARK: - Buy-ins

private struct BuyInHistorySheet: View {
    let nightID: UUID
    let playerID: UUID

    @EnvironmentObject private var store: NightStore
    @Environment(\.dismiss) private var dismiss
    @State private var amountText = ""

    private var night: GameNight? { store.night(nightID) }
    private var player: PlayerLedger? { night?.players.first { $0.id == playerID } }

    var body: some View {
        ScrollView {
            if let night, let player {
                VStack(alignment: .leading, spacing: Spacing.lg) {
                    HStack {
                        Text("Total in").font(.pokerHeadline).foregroundStyle(.pokerTextPrimary)
                        Spacer()
                        MoneyText(cents: player.totalInMinor, font: .pokerNumeric(.title3), color: .pokerGoldLight)
                    }
                    .accessibilityElement(children: .combine)

                    VStack(spacing: 0) {
                        ForEach(Array(player.buyIns.enumerated()), id: \.element.id) { index, event in
                            if index > 0 { Divider().overlay(Color.white.opacity(0.10)) }
                            row(index: index, event: event, player: player, night: night)
                        }
                    }
                    .pokerCard(padding: Spacing.md)

                    if player.isCashedOut {
                        InlineBanner(kind: .info, message: "\(player.name) has cashed out. Edit the cash-out to change their buy-ins.")
                    } else {
                        addAmount(night: night)
                    }
                }
                .padding(Spacing.gutter)
                .pokerReadableWidth()
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .keyboardDoneButton()
        .background(PokerBackground())
        .navigationTitle(player?.name ?? "Buy-ins")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") { dismiss() }
                    .accessibilityIdentifier("history.done")
            }
        }
    }

    private func row(index: Int, event: BuyInEvent, player: PlayerLedger, night: GameNight) -> some View {
        let words = VStack(alignment: .leading, spacing: Spacing.xs) {
            Text(index == 0 ? "Buy-in" : "Rebuy").font(.pokerCallout).foregroundStyle(.pokerTextPrimary)
            Text(event.at.formatted(.dateTime.hour().minute()))
                .font(.pokerFootnote)
                .foregroundStyle(.pokerTextSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .fixedSize(horizontal: true, vertical: false)
        }
        let amount = MoneyText(cents: event.amountMinor, font: .pokerNumeric(.callout), color: .pokerTextPrimary)
        let remove = Group {
            if index > 0 && !player.isCashedOut {
                Button {
                    store.mutate(nightID) { $0.undoBuyIn(playerID: playerID, eventID: event.id) }
                    Haptics.selection()
                } label: {
                    Image(systemName: "minus.circle.fill")
                        .foregroundStyle(Color.pokerNegative)
                        .frame(width: Spacing.minTapTarget, height: Spacing.minTapTarget)
                }
                .accessibilityLabel("Remove this rebuy of \(Money.spoken(cents: event.amountMinor))")
                .accessibilityIdentifier("history.remove.\(index)")
            }
        }
        // One line while it fits; the amount and the remove button go underneath at large text sizes.
        return ViewThatFits(in: .horizontal) {
            HStack(spacing: Spacing.md) {
                words
                Spacer(minLength: Spacing.sm)
                amount
                remove
            }
            VStack(alignment: .leading, spacing: Spacing.xs) {
                words
                HStack(spacing: Spacing.md) {
                    amount
                    Spacer(minLength: Spacing.sm)
                    remove
                }
            }
        }
        .frame(minHeight: Spacing.minTapTarget)
        .accessibilityElement(children: .combine)
    }

    private func addAmount(night: GameNight) -> some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            SectionHeader(title: "Add a different amount")
            HStack(spacing: Spacing.sm) {
                Text(Money.currencySymbol(currencyCode: night.currency))
                    .font(.pokerNumeric(.title3))
                    .foregroundStyle(Color.pokerGoldLight)
                    .accessibilityHidden(true)
                TextField("0.00", text: $amountText)
                    .keyboardType(.decimalPad)
                    .font(.pokerNumeric(.title3))
                    .accessibilityLabel("Amount")
                    .accessibilityIdentifier("history.amount")
            }
            .pokerTextField()

            PokerButton(title: "Add buy-in", kind: .secondary, isEnabled: parsedCents != nil, action: add)
                .accessibilityIdentifier("history.add")
        }
    }

    private var parsedCents: Int? {
        guard let amount = Money.parse(amountText), amount > 0, amount <= 1_000_000 else { return nil }
        return Money.cents(amount)
    }

    private func add() {
        guard let cents = parsedCents else { return }
        store.mutate(nightID) { $0.rebuy(playerID, amountMinor: cents) }
        amountText = ""
        Haptics.success()
    }
}
