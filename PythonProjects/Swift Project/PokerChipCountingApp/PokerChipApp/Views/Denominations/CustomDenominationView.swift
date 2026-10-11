//
//  CustomDenominationView.swift
//  PokerChipApp
//
//  The host sets each colour's value and each player's starting count. The
//  running total is checked against the buy-in as they type, and the counts
//  they enter are the stacks the game starts with.
//

import SwiftUI

struct CustomDenominationView: View {
    let setup: GameSetup

    @EnvironmentObject private var coordinator: NavigationCoordinator
    @EnvironmentObject private var store: NightStore

    @State private var valueTexts: [String: String] = [:]
    @State private var counts: [String: Int] = [:]
    @State private var didPrefill = false

    /// Most home sets are 500 pieces — about 100 of each colour — so asking
    /// for more than that across the table is probably a typo.
    private let typicalChipsPerColor = 100
    private let maximumChipValue = 100_000.0

    private var buyInCents: Int { Money.cents(setup.buyIn) }

    // MARK: Derived values

    private func valueCents(_ color: String) -> Int? {
        guard
            let text = valueTexts[color],
            let value = Money.parse(text),
            value > 0, value <= maximumChipValue
        else { return nil }
        return Money.cents(value)
    }

    private func subtotalCents(_ color: String) -> Int {
        (valueCents(color) ?? 0) * (counts[color] ?? 0)
    }

    private var totalCents: Int {
        setup.colors.reduce(0) { $0 + subtotalCents($1) }
    }

    private var allValuesValid: Bool {
        setup.colors.allSatisfy { valueCents($0) != nil }
    }

    private var matchesBuyIn: Bool { allValuesValid && totalCents == buyInCents }

    private var valuesAreOrdered: Bool {
        let values = setup.colors.compactMap { valueCents($0) }
        guard values.count == setup.colors.count else { return true }
        return zip(values, values.dropFirst()).allSatisfy { $0 < $1 }
    }

    // MARK: Body

    var body: some View {
        ScrollView {
            VStack(spacing: Spacing.lg) {
                StepIndicator(current: 1)

                ForEach(setup.colors, id: \.self) { color in
                    colorCard(color)
                }

                if !valuesAreOrdered {
                    InlineBanner(kind: .info, message: "Chip values usually increase from White to Black.")
                }
            }
            .padding(.horizontal, Spacing.gutter)
            .padding(.vertical, Spacing.lg)
            .pokerReadableWidth()
        }
        .scrollDismissesKeyboard(.interactively)
        .background(PokerBackground())
        .navigationTitle("Custom")
        .navigationBarTitleDisplayMode(.inline)
        .keyboardDoneButton()
        .safeAreaInset(edge: .bottom, spacing: 0) { bottomBar }
        .task { await prefillFromSuggestion() }
    }

    // MARK: Pieces

    private func colorCard(_ color: String) -> some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            HStack(spacing: Spacing.md) {
                ChipView(color: color, size: 44)
                Text(color)
                    .font(.pokerHeadline)
                    .foregroundStyle(.pokerTextPrimary)
                Spacer(minLength: Spacing.sm)
                MoneyText(cents: subtotalCents(color), font: .pokerNumeric(.body), color: .pokerTextSecondary)
            }

            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: Spacing.md) {
                    valueField(color)
                    countField(color)
                }
                VStack(alignment: .leading, spacing: Spacing.md) {
                    valueField(color)
                    countField(color)
                }
            }

            if let warning = chipCountWarning(color) {
                Label(warning, systemImage: "exclamationmark.triangle.fill")
                    .font(.pokerFootnote)
                    .foregroundStyle(.pokerWarning)
            }
        }
        .pokerCard()
    }

    private func valueField(_ color: String) -> some View {
        let text = valueTexts[color] ?? ""
        let hasProblem = !text.isEmpty && valueCents(color) == nil
        return VStack(alignment: .leading, spacing: Spacing.xs) {
            Text("Value each").font(.pokerCaption).foregroundStyle(.pokerTextSecondary)
            HStack(spacing: Spacing.xs) {
                Text(Money.currencySymbol())
                    .font(.pokerNumeric(.body))
                    .foregroundStyle(Color.pokerGoldLight)
                    .accessibilityHidden(true)
                TextField("0.00", text: Binding(
                    get: { valueTexts[color] ?? "" },
                    set: { valueTexts[color] = $0 }
                ))
                .keyboardType(.decimalPad)
                .font(.pokerNumeric(.body))
                .accessibilityLabel("\(color) chip value")
                .accessibilityIdentifier("custom.value.\(color)")
            }
            .pokerTextField(isError: hasProblem)
            .frame(minWidth: 120)

            if hasProblem {
                Text("Enter an amount above \(Money.format(0)).")
                    .font(.pokerFootnote)
                    .foregroundStyle(.pokerNegative)
            }
        }
    }

    private func countField(_ color: String) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text("Chips per player").font(.pokerCaption).foregroundStyle(.pokerTextSecondary)
            StepperField(
                value: Binding(
                    get: { counts[color] ?? 0 },
                    set: { counts[color] = $0 }
                ),
                range: 0...200,
                accessibilityLabel: "\(color) chips per player",
                identifier: "custom.count.\(color)"
            )
        }
    }

    private func chipCountWarning(_ color: String) -> String? {
        let needed = (counts[color] ?? 0) * setup.players
        guard needed > typicalChipsPerColor else { return nil }
        return "This needs \(needed) \(color) chips for \(setup.players) players. Most sets have up to \(typicalChipsPerColor) of each colour."
    }

    private var bottomBar: some View {
        VStack(spacing: Spacing.sm) {
            statusLine

            PokerButton(
                title: matchesBuyIn ? "Start game" : "Start anyway",
                systemImage: "play.fill",
                kind: matchesBuyIn ? .primary : .secondary,
                isEnabled: allValuesValid,
                action: start
            )
            .accessibilityIdentifier("custom.start")
        }
        .pokerBottomBar()
    }

    @ViewBuilder
    private var statusLine: some View {
        if !allValuesValid {
            Text("Enter a value for every colour to start.")
                .font(.pokerFootnote)
                .foregroundStyle(.pokerTextSecondary)
        } else if matchesBuyIn {
            Label("Each player's chips add up to \(Money.format(setup.buyIn))", systemImage: "checkmark.circle.fill")
                .font(.pokerFootnote.weight(.semibold))
                .foregroundStyle(.pokerPositive)
        } else {
            let difference = totalCents - buyInCents
            Label(
                "\(Money.format(cents: totalCents)) is \(Money.format(cents: abs(difference))) \(difference < 0 ? "under" : "over") the \(Money.format(setup.buyIn)) buy-in",
                systemImage: "exclamationmark.triangle.fill"
            )
            .font(.pokerFootnote.weight(.semibold))
            .foregroundStyle(.pokerWarning)
        }
    }

    // MARK: Actions

    /// Customizing is usually tweaking the suggestion, so start from it.
    private func prefillFromSuggestion() async {
        guard !didPrefill else { return }
        didPrefill = true
        guard case .ready(let options) = await SuggestedViewModel.outcome(for: setup), let suggestion = options.first else { return }
        for row in suggestion.rows {
            valueTexts[row.color] = Money.plain(Double(row.valueCents) / 100)
            counts[row.color] = row.count
        }
    }

    private func start() {
        guard allValuesValid else { return }
        var denominationsMinor: [String: Int] = [:]
        var startingCounts: [String: Int] = [:]
        for color in setup.colors {
            guard let cents = valueCents(color) else { return }
            denominationsMinor[color] = cents
            startingCounts[color] = counts[color] ?? 0
        }
        let night = store.startNight(
            from: setup,
            buyInMinor: buyInCents,
            denominationsMinor: denominationsMinor,
            startingCounts: startingCounts
        )
        coordinator.open(night: night.id)
    }
}

struct CustomDenominationView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationStack {
            CustomDenominationView(setup: GameSetup(buyIn: 25, players: 6, availableColors: Set(allChipColors)))
                .environmentObject(NavigationCoordinator())
                .environmentObject(NightStore(repository: MemoryNightRepository()))
        }
    }
}
