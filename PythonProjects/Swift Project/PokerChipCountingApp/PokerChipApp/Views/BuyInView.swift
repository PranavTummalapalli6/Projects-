//
//  BuyInView.swift
//  PokerChipApp
//
//  Created by Pranav on 4/2/25.
//

import SwiftUI

struct BuyInView: View {
    @EnvironmentObject private var coordinator: NavigationCoordinator

    @State private var amountText: String
    @State private var players: Int
    @State private var colors: Set<String>
    @State private var triedToContinue = false
    @State private var inventory: ChipInventory?
    @State private var showsChipSet = false
    /// Names and place from the last game (or "Same as last game"), carried to the next screen.
    private let carriedNames: [String]
    private let carriedLocation: String?

    @AppStorage(PrefKey.coolOffUntil) private var coolOffUntil = 0.0
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private let quickPicks: [Double] = [10, 20, 25, 50, 100]

    /// Wide enough for "$100" at the current text size, so larger text means
    /// fewer, wider buttons per row instead of text broken across lines.
    @ScaledMetric(relativeTo: .subheadline) private var quickPickWidth: CGFloat = 60
    private let minimumBuyIn = 0.05
    private let maximumBuyIn = 1_000_000.0

    /// Starts from the last game's values (or whatever "Same as last game"
    /// handed over), so the usual game is a single tap on Next.
    init(prefill: GameSetup?) {
        let start = prefill ?? Stores.gameSetup.load()
        _amountText = State(initialValue: start.map { Money.plain($0.buyIn) } ?? "")
        _players = State(initialValue: start?.players ?? 6)
        _colors = State(initialValue: start?.availableColors ?? [])
        _inventory = State(initialValue: start?.inventory ?? Stores.chipInventory.load())
        carriedNames = start?.playerNames ?? []
        carriedLocation = start?.location
    }

    // MARK: Validation

    private var amount: Double? { Money.parse(amountText) }

    private var amountProblem: String? {
        guard !amountText.isEmpty || triedToContinue else { return nil }
        guard let amount else {
            return "Enter an amount like \(Money.plain(25.5))."
        }
        if amount < minimumBuyIn { return "The buy-in must be at least \(Money.format(minimumBuyIn))." }
        if amount > maximumBuyIn { return "The buy-in can't be more than \(Money.compact(maximumBuyIn))." }
        return nil
    }

    private var colorsProblem: String? {
        triedToContinue && colors.isEmpty ? "Tap every chip colour you have." : nil
    }

    // MARK: Body

    /// A break the person committed to also holds at this door, whichever way they came in.
    private var breakEnd: Date? {
        coolOffUntil > Date().timeIntervalSince1970 ? Date(timeIntervalSince1970: coolOffUntil) : nil
    }

    var body: some View {
        if let end = breakEnd {
            EmptyState(
                icon: "moon.zzz.fill",
                title: "You're taking a break",
                message: "You chose to pause new nights until \(end.formatted(date: .abbreviated, time: .shortened)). Your history is all still here, and any night in progress can be finished.",
                actionTitle: "Back"
            ) { coordinator.pop() }
            .accessibilityIdentifier("buyin.onBreak")
            .padding(Spacing.gutter)
            .pokerReadableWidth()
            .frame(maxHeight: .infinity)
            .background(PokerBackground())
            .navigationTitle("Buy-in")
            .navigationBarTitleDisplayMode(.inline)
        } else {
            form
        }
    }

    private var form: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.xl) {
                StepIndicator(current: 0)

                buyInSection
                playersSection
                chipsSection
                chipSetSection
            }
            .padding(.horizontal, Spacing.gutter)
            .padding(.vertical, Spacing.lg)
            .pokerReadableWidth()
        }
        .scrollDismissesKeyboard(.interactively)
        .background(PokerBackground())
        .navigationTitle("Buy-in")
        .navigationBarTitleDisplayMode(.inline)
        .keyboardDoneButton()
        .safeAreaInset(edge: .bottom, spacing: 0) {
            PokerButton(title: "Next", action: next)
                .accessibilityIdentifier("buyin.next")
                .pokerBottomBar()
        }
    }

    private var buyInSection: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            SectionHeader(title: "Buy-in amount")

            HStack(spacing: Spacing.sm) {
                Text(Money.currencySymbol())
                    .font(.pokerNumeric(.title2))
                    .foregroundStyle(Color.pokerGoldLight)
                    .accessibilityHidden(true)
                TextField("0.00", text: $amountText)
                    .keyboardType(.decimalPad)
                    .font(.pokerNumeric(.title2))
                    .accessibilityLabel("Buy-in amount")
                    .accessibilityIdentifier("buyin.amount")
            }
            .pokerTextField(isError: amountProblem != nil)

            if let amountProblem {
                Label(amountProblem, systemImage: "exclamationmark.circle.fill")
                    .font(.pokerFootnote)
                    .foregroundStyle(.pokerNegative)
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: quickPickWidth), spacing: Spacing.sm)], spacing: Spacing.sm) {
                ForEach(quickPicks, id: \.self) { value in
                    quickPick(value)
                }
            }
        }
    }

    private func quickPick(_ value: Double) -> some View {
        let isCurrent = amount == value
        return Button {
            amountText = Money.plain(value)
            Haptics.selection()
        } label: {
            Text(Money.compact(value))
                .font(.pokerNumeric(.subheadline))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .foregroundStyle(isCurrent ? Color.black : Color.pokerGoldLight)
                .frame(maxWidth: .infinity, minHeight: Spacing.minTapTarget)
                .background(isCurrent ? Color.pokerGold : Color.pokerGold.opacity(0.12))
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(Money.format(value)) buy-in")
        .accessibilityAddTraits(isCurrent ? .isSelected : [])
        .accessibilityIdentifier("buyin.quick.\(Int(value))")
    }

    private var playersSection: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            SectionHeader(title: "Number of players")
            StepperField(value: $players, range: 2...10, accessibilityLabel: "players", identifier: "buyin.players")
            Text("Fewer players means more chips each; more players means fewer.")
                .font(.pokerFootnote)
                .foregroundStyle(.pokerTextTertiary)
        }
    }

    private var chipsSection: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            HStack {
                SectionHeader(title: "Chips you have")
                Button {
                    colors = colors.count == allChipColors.count ? [] : Set(allChipColors)
                    Haptics.selection()
                } label: {
                    Text(colors.count == allChipColors.count ? "Clear" : "Select all")
                        .font(.pokerFootnote.weight(.semibold))
                        .foregroundStyle(Color.pokerGoldLight)
                        .frame(minWidth: Spacing.minTapTarget, minHeight: Spacing.minTapTarget)
                        .contentShape(Rectangle())
                }
                .accessibilityIdentifier("buyin.selectAll")
            }

            // Five across is right until the names stop fitting; at accessibility
            // text sizes each colour gets its own full-width row.
            Group {
                if dynamicTypeSize.isAccessibilitySize {
                    VStack(spacing: Spacing.sm) {
                        ForEach(allChipColors, id: \.self) { color in
                            chipToggle(color, layout: .row)
                        }
                    }
                } else {
                    HStack(spacing: 0) {
                        ForEach(allChipColors, id: \.self) { color in
                            chipToggle(color, layout: .column)
                                .frame(maxWidth: .infinity)
                        }
                    }
                }
            }
            .pokerSpring(value: colors)

            if let colorsProblem {
                Label(colorsProblem, systemImage: "exclamationmark.circle.fill")
                    .font(.pokerFootnote)
                    .foregroundStyle(.pokerNegative)
            } else {
                Text("Tap the colours in your set. Chip values are worked out only for these.")
                    .font(.pokerFootnote)
                    .foregroundStyle(.pokerTextTertiary)
            }
        }
    }

    private var chipSetSection: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            SectionHeader(title: "Your chip set")
            Button {
                showsChipSet = true
            } label: {
                ListRow(
                    icon: "square.stack.3d.up",
                    title: inventory.map { "\($0.totalOwned) chips\($0.printedValues != nil ? " · values printed" : "")" } ?? "Tell me what you own",
                    subtitle: inventory == nil
                        ? "So a suggestion never needs more chips than you have. Optional."
                        : "Tap to change. Suggestions stay within this set."
                )
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("buyin.chipSet")
        }
        .sheet(isPresented: $showsChipSet) {
            NavigationStack {
                ChipSetView(inventory: $inventory, colors: allChipColors.filter { colors.contains($0) })
            }
        }
    }

    private func chipToggle(_ color: String, layout: ChipToggle.Layout) -> some View {
        ChipToggle(color: color, isSelected: colors.contains(color), layout: layout) {
            if colors.contains(color) {
                colors.remove(color)
            } else {
                colors.insert(color)
            }
            Haptics.selection()
        }
    }

    // MARK: Actions

    private func next() {
        triedToContinue = true
        guard amountProblem == nil, let amount, !colors.isEmpty else {
            Haptics.warning()
            return
        }
        let setup = GameSetup(
            buyIn: amount, players: players, availableColors: colors,
            playerNames: carriedNames, location: carriedLocation, inventory: inventory
        )
        Stores.gameSetup.save(setup)
        coordinator.push(.players(setup))
    }
}

/// A tappable chip: dimmed until the player says they have that colour, then
/// full colour with a check badge. The name under it and the badge mean
/// colour is never the only signal, and the whole column is a 44-pt-plus target.
private struct ChipToggle: View {
    enum Layout { case column, row }

    let color: String
    let isSelected: Bool
    let layout: Layout
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            switch layout {
            case .column:
                VStack(spacing: Spacing.xs) {
                    ChipView(color: color, size: 44, isDimmed: !isSelected)
                        .overlay(alignment: .topTrailing) {
                            if isSelected {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 16))
                                    .foregroundStyle(Color.black, Color.pokerGoldLight)
                                    .offset(x: 4, y: -4)
                            }
                        }
                    Text(color)
                        .font(.caption2.weight(.semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .foregroundStyle(isSelected ? Color.pokerTextPrimary : Color.pokerTextTertiary)
                }
                .frame(maxWidth: .infinity, minHeight: 68)
                .contentShape(Rectangle())

            case .row:
                HStack(spacing: Spacing.lg) {
                    ChipView(color: color, size: 44, isDimmed: !isSelected)
                    Text(color)
                        .font(.pokerHeadline)
                        .foregroundStyle(isSelected ? Color.pokerTextPrimary : Color.pokerTextTertiary)
                    Spacer(minLength: Spacing.sm)
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.title2)
                        .foregroundStyle(isSelected ? Color.pokerGoldLight : Color.pokerTextTertiary)
                }
                .padding(.horizontal, Spacing.md)
                .frame(maxWidth: .infinity, minHeight: 60)
                .background(isSelected ? Color.pokerGold.opacity(0.10) : Color.pokerSurface)
                .clipShape(RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
                .contentShape(Rectangle())
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(color) chips")
        .accessibilityValue(isSelected ? "available" : "not available")
        .accessibilityIdentifier("buyin.color.\(color)")
    }
}

struct BuyInView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationStack {
            BuyInView(prefill: nil)
                .environmentObject(NavigationCoordinator())
        }
    }
}
