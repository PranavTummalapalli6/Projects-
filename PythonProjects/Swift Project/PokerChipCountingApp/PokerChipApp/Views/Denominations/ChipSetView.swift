//
//  ChipSetView.swift
//  PokerChipApp
//
//  "What chips do you own?" A common set size to start from, a count for each
//  colour, and — if the values are printed on the chips — those too. With this,
//  a suggestion never deals more of a colour than the set holds, and never
//  invents a value the chips don't carry.
//

import SwiftUI

struct ChipSetView: View {
    /// The saved set (nil = unknown, no limits).
    @Binding var inventory: ChipInventory?
    /// The colours in use tonight.
    let colors: [String]

    @Environment(\.dismiss) private var dismiss
    @State private var owned: [String: Int]
    @State private var hasPrintedValues: Bool
    @State private var printedTexts: [String: String]

    init(inventory: Binding<ChipInventory?>, colors: [String]) {
        _inventory = inventory
        let ordered = allChipColors.filter { colors.contains($0) }
        self.colors = ordered
        let current = inventory.wrappedValue
        _owned = State(initialValue: current?.owned ?? ChipInventory.preset(.fiveHundred, colors: ordered).owned)
        _hasPrintedValues = State(initialValue: current?.printedValues != nil)
        _printedTexts = State(initialValue: Dictionary(uniqueKeysWithValues: ordered.map { color in
            (color, current?.printedValues?[color].map { Money.plain(Double($0) / 100) } ?? "")
        }))
    }

    private var total: Int { colors.reduce(0) { $0 + (owned[$1] ?? 0) } }

    private func printedCents(_ color: String) -> Int? {
        guard let value = Money.parse(printedTexts[color] ?? ""), value > 0, value <= 100_000 else { return nil }
        return Money.cents(value)
    }

    private var printedProblem: String? {
        guard hasPrintedValues else { return nil }
        let values = colors.map(printedCents)
        if values.contains(where: { $0 == nil }) { return "Enter the value printed on each colour." }
        let cents = values.compactMap { $0 }
        if !zip(cents, cents.dropFirst()).allSatisfy({ $0 < $1 }) {
            return "Values should rise from the first colour to the last, \(colors.first ?? "") lowest."
        }
        return nil
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.xl) {
                sizeSection
                countsSection
                printedSection
            }
            .padding(.horizontal, Spacing.gutter)
            .padding(.vertical, Spacing.lg)
            .pokerReadableWidth()
        }
        .scrollDismissesKeyboard(.interactively)
        .keyboardDoneButton()
        .background(PokerBackground())
        .navigationTitle("Your chip set")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: Spacing.sm) {
                PokerButton(title: "Use this set", isEnabled: printedProblem == nil && total > 0, action: save)
                    .accessibilityIdentifier("chipset.save")
                if inventory != nil {
                    PokerButton(title: "I don't know — don't limit me", kind: .quiet, action: clear)
                        .accessibilityIdentifier("chipset.clear")
                }
            }
            .pokerBottomBar()
        }
    }

    // MARK: Size

    private var sizeSection: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            SectionHeader(title: "How big is your set?")
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: Spacing.sm)], spacing: Spacing.sm) {
                ForEach(ChipInventory.SetSize.allCases) { size in
                    let isCurrent = total == size.rawValue
                    Button {
                        owned = ChipInventory.preset(size, colors: colors).owned
                        Haptics.selection()
                    } label: {
                        Text("\(size.rawValue) pieces")
                            .font(.pokerNumeric(.subheadline))
                            .foregroundStyle(isCurrent ? Color.black : Color.pokerGoldLight)
                            .frame(maxWidth: .infinity, minHeight: Spacing.minTapTarget)
                            .background(isCurrent ? Color.pokerGold : Color.pokerGold.opacity(0.12))
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(isCurrent ? .isSelected : [])
                    .accessibilityIdentifier("chipset.size.\(size.rawValue)")
                }
            }
            Text("A common set split evenly across your colours. Change any count below to match what's in your case.")
                .font(.pokerFootnote)
                .foregroundStyle(.pokerTextTertiary)
        }
    }

    private var countsSection: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            HStack {
                SectionHeader(title: "How many of each?")
                Text("\(total) in all")
                    .font(.pokerNumeric(.footnote))
                    .foregroundStyle(.pokerTextSecondary)
                    .accessibilityIdentifier("chipset.total")
            }
            ForEach(colors, id: \.self) { color in
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: Spacing.md) {
                        ChipView(color: color, size: 36)
                        Text(color).font(.pokerHeadline).foregroundStyle(.pokerTextPrimary)
                        Spacer(minLength: Spacing.sm)
                        stepper(color, compact: true)
                    }
                    VStack(alignment: .leading, spacing: Spacing.sm) {
                        HStack(spacing: Spacing.md) {
                            ChipView(color: color, size: 36)
                            Text(color).font(.pokerHeadline).foregroundStyle(.pokerTextPrimary)
                        }
                        stepper(color, compact: false)
                    }
                }
                .pokerCard(padding: Spacing.md)
            }
        }
    }

    private func stepper(_ color: String, compact: Bool) -> some View {
        StepperField(
            value: Binding(get: { owned[color] ?? 0 }, set: { owned[color] = $0 }),
            range: 0...2_000,
            accessibilityLabel: "\(color) chips owned",
            identifier: "chipset.count.\(color)",
            isCompact: compact
        )
    }

    // MARK: Printed values

    private var printedSection: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            SectionHeader(title: "Values on the chips")

            Toggle(isOn: $hasPrintedValues) {
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text("My chips have values printed on them").font(.pokerHeadline).foregroundStyle(.pokerTextPrimary)
                    Text("Then only counts are worked out — each colour keeps its printed value.")
                        .font(.pokerFootnote).foregroundStyle(.pokerTextSecondary)
                }
            }
            .tint(.pokerGold)
            .accessibilityIdentifier("chipset.printed")

            if hasPrintedValues {
                ForEach(colors, id: \.self) { color in
                    HStack(spacing: Spacing.md) {
                        ChipView(color: color, size: 32)
                        Text(color).foregroundStyle(.pokerTextPrimary)
                        Spacer(minLength: Spacing.sm)
                        Text(Money.currencySymbol()).foregroundStyle(Color.pokerGoldLight).accessibilityHidden(true)
                        TextField("0.00", text: Binding(get: { printedTexts[color] ?? "" }, set: { printedTexts[color] = $0 }))
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(maxWidth: 110)
                            .accessibilityLabel("Printed value of \(color) chips")
                            .accessibilityIdentifier("chipset.value.\(color)")
                    }
                    .pokerTextField(isError: printedProblem != nil && printedCents(color) == nil)
                }
                if let printedProblem {
                    Label(printedProblem, systemImage: "exclamationmark.circle.fill")
                        .font(.pokerFootnote)
                        .foregroundStyle(.pokerNegative)
                }
            }
        }
    }

    // MARK: Actions

    private func save() {
        var printed: [String: Int]?
        if hasPrintedValues {
            printed = Dictionary(uniqueKeysWithValues: colors.compactMap { color in printedCents(color).map { (color, $0) } })
        }
        // A colour set to none stays at none: a suggestion that needs it is turned down, not quietly given.
        let saved = ChipInventory(owned: owned.filter { colors.contains($0.key) }, printedValues: printed)
        inventory = saved
        Stores.chipInventory.save(saved)
        dismiss()
    }

    private func clear() {
        inventory = nil
        Stores.chipInventory.clear()
        dismiss()
    }
}
