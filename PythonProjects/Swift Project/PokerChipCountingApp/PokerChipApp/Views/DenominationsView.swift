//
//  DenominationsView.swift
//  PokerChipApp
//
//  Created by Pranav on 4/2/25.
//
//  The "Suggested" chip values screen. The solver itself lives in
//  Denominations/DenominationEngine.swift; this file runs it (off the main
//  thread, cached by input) and shows what it found: the stack each player gets,
//  other ways to deal the same buy-in, how much of the person's own set it uses,
//  and blinds that can be paid with the smallest chip.
//

import SwiftUI

@MainActor
final class SuggestedViewModel: ObservableObject {
    struct Row: Identifiable, Hashable {
        let color: String
        let valueCents: Int
        let count: Int

        var id: String { color }
        var subtotalCents: Int { valueCents * count }
    }

    struct Suggestion: Hashable {
        let kind: ChipOption.Kind
        let rows: [Row]

        init(option: ChipOption, colors: [String]) {
            kind = option.kind
            rows = colors.compactMap { color in
                guard let value = option.valuesCents[color], let count = option.counts[color] else { return nil }
                return Row(color: color, valueCents: value, count: count)
            }
        }

        var totalChips: Int { rows.reduce(0) { $0 + $1.count } }
        var totalCents: Int { rows.reduce(0) { $0 + $1.subtotalCents } }
        var smallestChipCents: Int { rows.map(\.valueCents).min() ?? 0 }
        var valuesMinor: [String: Int] {
            Dictionary(uniqueKeysWithValues: rows.map { ($0.color, $0.valueCents) })
        }
        var counts: [String: Int] {
            Dictionary(uniqueKeysWithValues: rows.map { ($0.color, $0.count) })
        }

        var title: String {
            switch kind {
            case .recommended: return "Recommended"
            case .fewerChips: return "Fewer chips to count"
            case .finerChips: return "A smaller smallest chip"
            }
        }
    }

    enum Outcome: Hashable {
        /// The recommended stack first, then any other ways to deal the same buy-in.
        case ready([Suggestion])
        /// The buy-in can't be spread across that many colours with real chip
        /// values. `nextWorkingCents` is the next amount up that can, if one
        /// is nearby — so the message can say what to try, not just "no".
        case tooSmall(nextWorkingCents: Int?)
        /// It works with unlimited chips, but not with the set the person owns.
        case setTooSmall([ChipAlternative])
        /// Chips with printed values can't add up to exactly this amount.
        case noExactSplit(nearbyCents: [Int])
        /// The values fixed or printed can't be ordered low to high down the colours.
        case valuesConflict
        case noColors
    }

    @Published private(set) var state: LoadState<Outcome> = .idle
    /// Which of the options is showing.
    @Published var selected = 0

    /// Solver results by input, so coming back to this screen is instant.
    private static var cache: [String: Outcome] = [:]

    func load(for setup: GameSetup) async {
        if let cached = Self.cache[Self.cacheKey(for: setup)] {
            selected = 0
            state = .loaded(cached)
            return
        }
        // Re-solving after a change keeps the old answer on screen until the new one is ready.
        if case .loaded = state {} else { state = .loading }
        let outcome = await Self.outcome(for: setup)
        guard !Task.isCancelled else { return }
        selected = 0
        state = .loaded(outcome)
    }

    /// The option on screen, if there is one.
    var current: Suggestion? {
        guard case .loaded(.ready(let options)) = state, !options.isEmpty else { return nil }
        return options[min(selected, options.count - 1)]
    }

    var optionCount: Int {
        if case .loaded(.ready(let options)) = state { return options.count }
        return 0
    }

    func nextOption() {
        guard optionCount > 1 else { return }
        selected = (selected + 1) % optionCount
    }

    /// Everything the answer depends on.
    static func cacheKey(for setup: GameSetup) -> String {
        func pairs(_ values: [String: Int]) -> String {
            values.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: ",")
        }
        let owned = setup.inventory.map { "\(pairs($0.owned))|\(pairs($0.printedValues ?? [:]))" } ?? "-"
        return "\(Money.cents(setup.buyIn))|\(setup.players)|\(setup.colors.joined(separator: ","))|\(owned)|\(pairs(setup.lockedValues))"
    }

    /// Runs the solver off the main thread (its worst case is ~15 ms, but a
    /// render path is no place for it) and remembers the answer.
    static func outcome(for setup: GameSetup) async -> Outcome {
        let key = cacheKey(for: setup)
        if let cached = cache[key] { return cached }

        let buyIn = setup.buyIn
        let players = setup.players
        let colors = setup.availableColors
        let inventory = setup.inventory
        let locked = setup.lockedValues
        let plan = await Task.detached(priority: .userInitiated) {
            ChipPlanner.plan(buyIn: buyIn, players: players, colors: colors, inventory: inventory, lockedValues: locked)
        }.value

        let outcome: Outcome
        if !plan.options.isEmpty {
            outcome = .ready(plan.options.map { Suggestion(option: $0, colors: setup.colors) })
        } else {
            switch plan.failure {
            case .noColors: outcome = .noColors
            case .setTooSmall: outcome = .setTooSmall(plan.alternatives)
            case .noExactSplit(let nearby): outcome = .noExactSplit(nearbyCents: nearby)
            case .valuesConflict: outcome = .valuesConflict
            case .tooSmall(let next): outcome = .tooSmall(nextWorkingCents: next)
            case nil: outcome = .tooSmall(nextWorkingCents: nil)
            }
        }
        cache[key] = outcome
        return outcome
    }
}

struct CombinedDenominationsView: View {
    @EnvironmentObject private var coordinator: NavigationCoordinator
    @EnvironmentObject private var store: NightStore
    @StateObject private var viewModel = SuggestedViewModel()

    /// The setup being worked on. Fixing a value or taking one of the alternatives
    /// changes it, and the chips are worked out again around the change.
    @State private var setup: GameSetup
    @State private var blinds: Blinds?
    @State private var showsWhy = false
    @State private var showsTableCard = false

    init(setup: GameSetup) {
        _setup = State(initialValue: setup)
    }

    private var solveKey: String { SuggestedViewModel.cacheKey(for: setup) }

    /// Values a colour can be fixed at, in cents. The value on screen is always offered too.
    private static let valueChoices = [5, 10, 25, 50, 100, 200, 500, 1_000, 2_000, 2_500, 5_000, 10_000]

    var body: some View {
        ScrollView {
            VStack(spacing: Spacing.lg) {
                StepIndicator(current: 1)

                switch viewModel.state {
                case .idle, .loading:
                    loadingPlaceholder
                case .failed(let message):
                    InlineBanner(kind: .error, message: message)
                case .loaded(.ready):
                    if let suggestion = viewModel.current {
                        suggestionContent(suggestion)
                    }
                case .loaded(.tooSmall(let nextWorking)):
                    EmptyState(
                        icon: "exclamationmark.triangle",
                        title: "This buy-in is too small to split",
                        message: tooSmallMessage(nextWorking: nextWorking),
                        actionTitle: "Change buy-in"
                    ) {
                        coordinator.path = [.buyIn(setup)]
                    }
                    .accessibilityIdentifier("suggested.tooSmall")
                case .loaded(.setTooSmall(let alternatives)):
                    setTooSmall(alternatives)
                case .loaded(.noExactSplit(let nearby)):
                    noExactSplit(nearby)
                case .loaded(.valuesConflict):
                    EmptyState(
                        icon: "arrow.up.arrow.down",
                        title: "Those values don't go together",
                        message: "Chip values have to rise from the lowest colour to the highest, with fewer chips of each higher one. Check the values you fixed or printed on the chips.",
                        actionTitle: setup.lockedValues.isEmpty ? "Change my chip set" : "Let the app choose"
                    ) {
                        if setup.lockedValues.isEmpty {
                            coordinator.path = [.buyIn(setup)]
                        } else {
                            setup.lockedValues = [:]
                        }
                    }
                    .accessibilityIdentifier("suggested.conflict")
                case .loaded(.noColors):
                    EmptyState(
                        icon: "circle.slash",
                        title: "No chip colours chosen",
                        message: "Choose at least one colour of chip on the first screen.",
                        actionTitle: "Back to the buy-in"
                    ) {
                        coordinator.path = [.buyIn(setup)]
                    }
                }
            }
            .padding(.horizontal, Spacing.gutter)
            .padding(.vertical, Spacing.lg)
            .pokerReadableWidth()
        }
        .background(PokerBackground())
        .navigationTitle("Suggested")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: solveKey) { await viewModel.load(for: setup) }
        .onChange(of: viewModel.current) { suggestion in
            blinds = suggestion.flatMap {
                BlindsPlanner.suggested(stackCents: $0.totalCents, smallestChipCents: $0.smallestChipCents)
            }
        }
        .fullScreenCover(isPresented: $showsTableCard) {
            if let suggestion = viewModel.current {
                TableCardView(content: TableCardContent(suggestion: suggestion, blinds: blinds))
            }
        }
    }

    // MARK: When it doesn't work

    private func tooSmallMessage(nextWorking: Int?) -> String {
        var message = setup.colors.count > 1
            ? "\(Money.format(setup.buyIn)) can't be spread across \(setup.colors.count) chip colours with each colour worth more and fewer of them."
            : "\(Money.format(setup.buyIn)) can't be made from chips of real values."
        if let nextWorking {
            message += " The next amount that works is \(Money.format(cents: nextWorking))"
            message += setup.colors.count > 1 ? ", or use fewer colours." : "."
        } else {
            message += " Try a larger buy-in\(setup.colors.count > 1 ? " or fewer colours" : "")."
        }
        return message
    }

    private func setTooSmall(_ alternatives: [ChipAlternative]) -> some View {
        VStack(spacing: Spacing.md) {
            EmptyState(
                icon: "square.stack.3d.up.slash",
                title: "Your set is too small for this table",
                message: "\(setup.players) players with \(Money.format(setup.buyIn)) each in \(setup.colors.count) colour\(setup.colors.count == 1 ? "" : "s") would need more chips of some colour than your \(setup.inventory?.totalOwned ?? 0)-chip set has."
                    + (alternatives.isEmpty ? "" : " Here's what would work:")
            )
            .accessibilityIdentifier("suggested.setTooSmall")

            ForEach(alternatives) { alternative in
                PokerButton(title: Self.text(for: alternative), kind: .secondary) {
                    apply(alternative)
                }
                .accessibilityIdentifier("suggested.alt.\(alternative.id)")
            }
            PokerButton(title: "Change my chip set", kind: .quiet) {
                coordinator.path = [.buyIn(setup)]
            }
            .accessibilityIdentifier("suggested.changeSet")
        }
    }

    private static func text(for alternative: ChipAlternative) -> String {
        switch alternative.kind {
        case .fewerPlayers(let players): return "Play with \(players) players"
        case .lowerBuyIn(let cents): return "Lower the buy-in to \(Money.format(cents: cents))"
        case .dropColor(let color): return "Leave out the \(color) chips"
        }
    }

    private func apply(_ alternative: ChipAlternative) {
        setup = setup.applying(alternative)
        Stores.gameSetup.save(setup)
        Haptics.selection()
    }

    private func noExactSplit(_ nearby: [Int]) -> some View {
        VStack(spacing: Spacing.md) {
            EmptyState(
                icon: "equal.circle",
                title: "Those chips can't make exactly \(Money.format(setup.buyIn))",
                message: nearby.isEmpty
                    ? "With the values printed on them, no mix of your chips adds up to that amount."
                    : "With the values printed on them, only certain amounts add up. These are the closest that do:"
            )
            .accessibilityIdentifier("suggested.noExact")
            ForEach(nearby, id: \.self) { cents in
                PokerButton(title: "Make it \(Money.format(cents: cents))", kind: .secondary) {
                    setup.buyIn = Double(cents) / 100
                    Stores.gameSetup.save(setup)
                    Haptics.selection()
                }
            }
            PokerButton(title: "Change my chip set", kind: .quiet) {
                coordinator.path = [.buyIn(setup)]
            }
        }
    }

    private var loadingPlaceholder: some View {
        VStack(spacing: Spacing.md) {
            ForEach(0..<max(setup.colors.count, 1), id: \.self) { _ in
                SkeletonView(cornerRadius: Radius.control)
                    .frame(height: 64)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Working out chip values")
    }

    // MARK: A suggestion

    private func suggestionContent(_ suggestion: SuggestedViewModel.Suggestion) -> some View {
        VStack(spacing: Spacing.lg) {
            optionHeader(suggestion)

            VStack(spacing: 0) {
                ForEach(Array(suggestion.rows.enumerated()), id: \.element.id) { index, row in
                    if index > 0 {
                        Divider().overlay(Color.white.opacity(0.10))
                    }
                    rowView(row)
                }
            }
            .pokerCard(padding: Spacing.md)

            totalLine(suggestion)

            if Money.cents(setup.buyIn) != suggestion.totalCents {
                InlineBanner(
                    kind: .info,
                    message: "Your \(Money.format(setup.buyIn)) buy-in was rounded to \(Money.format(cents: suggestion.totalCents)) so the chips divide cleanly."
                )
                .accessibilityIdentifier("suggested.rounded")
            }

            if let inventory = setup.inventory {
                Text("That's \(suggestion.totalChips * setup.players) of your \(inventory.totalOwned) chips.")
                    .font(.pokerFootnote)
                    .foregroundStyle(.pokerTextSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityIdentifier("suggested.usage")
            }

            blindsCard(suggestion)

            whyCard(suggestion)

            VStack(spacing: Spacing.md) {
                PokerButton(title: "Start game", systemImage: "play.fill") {
                    let night = store.startNight(
                        from: setup,
                        buyInMinor: suggestion.totalCents,
                        denominationsMinor: suggestion.valuesMinor,
                        startingCounts: suggestion.counts,
                        blinds: blinds
                    )
                    coordinator.open(night: night.id)
                }
                .accessibilityIdentifier("suggested.start")

                PokerButton(title: "Show a card for the table", systemImage: "rectangle.landscape.rotate", kind: .secondary) {
                    showsTableCard = true
                }
                .accessibilityIdentifier("suggested.tableCard")

                PokerButton(title: "Customize values", kind: .secondary) {
                    coordinator.push(.custom(setup))
                }
                .accessibilityIdentifier("suggested.customize")
            }
        }
    }

    private func optionHeader(_ suggestion: SuggestedViewModel.Suggestion) -> some View {
        let titles = VStack(alignment: .leading, spacing: Spacing.xs) {
            Text(suggestion.title)
                .font(.pokerHeadline)
                .foregroundStyle(.pokerTextPrimary)
                .accessibilityIdentifier("suggested.optionTitle")
            if viewModel.optionCount > 1 {
                Text("Option \(viewModel.selected + 1) of \(viewModel.optionCount)")
                    .font(.pokerFootnote)
                    .foregroundStyle(.pokerTextSecondary)
            }
        }
        let another = Button {
            viewModel.nextOption()
            Haptics.selection()
        } label: {
            Label("Another option", systemImage: "arrow.triangle.2.circlepath")
                .font(.pokerFootnote.weight(.semibold))
                .foregroundStyle(Color.pokerGoldLight)
                .padding(.horizontal, Spacing.md)
                .frame(minHeight: Spacing.minTapTarget)
                .background(Color.pokerGold.opacity(0.12))
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("suggested.another")

        // Side by side while they fit; the button goes under the title at large text sizes.
        return ViewThatFits(in: .horizontal) {
            HStack(alignment: .center, spacing: Spacing.md) {
                titles
                Spacer(minLength: Spacing.sm)
                if viewModel.optionCount > 1 { another }
            }
            VStack(alignment: .leading, spacing: Spacing.sm) {
                titles
                if viewModel.optionCount > 1 { another }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func rowView(_ row: SuggestedViewModel.Row) -> some View {
        let name = Text(row.color)
            .font(.pokerHeadline)
            .foregroundStyle(.pokerTextPrimary)
        let each = valueMenu(row)
        let count = Text("× \(row.count)")
            .font(.pokerNumeric(.title3))
            .foregroundStyle(Color.pokerGoldLight)
            .accessibilityLabel("\(row.count) chips")
        let owned = ownedLine(row)

        // One line while it fits; stacked at large text sizes so nothing wraps mid-phrase.
        return ViewThatFits(in: .horizontal) {
            HStack(spacing: Spacing.md) {
                ChipView(color: row.color, size: 44)
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    name
                    each
                    owned
                }
                Spacer(minLength: Spacing.sm)
                VStack(alignment: .trailing, spacing: Spacing.xs) {
                    count
                    MoneyText(cents: row.subtotalCents, font: .pokerNumeric(.footnote, weight: .regular), color: .pokerTextSecondary)
                }
            }
            VStack(alignment: .leading, spacing: Spacing.sm) {
                HStack(spacing: Spacing.md) {
                    ChipView(color: row.color, size: 44)
                    name
                }
                each
                owned
                HStack {
                    count
                    Spacer(minLength: Spacing.sm)
                    MoneyText(cents: row.subtotalCents, font: .pokerNumeric(.body, weight: .regular), color: .pokerTextSecondary)
                }
            }
        }
        .padding(.vertical, Spacing.sm)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("suggested.row.\(row.color)")
    }

    /// The value, which can be fixed so the rest is worked out around it.
    private func valueMenu(_ row: SuggestedViewModel.Row) -> some View {
        let isPrinted = setup.inventory?.printedValues?[row.color] != nil
        let isFixed = setup.lockedValues[row.color] != nil && !isPrinted
        let choices = Set(Self.valueChoices + [row.valueCents]).sorted()
        return Menu {
            if isPrinted {
                Text("Printed on the chips")
            } else {
                ForEach(choices, id: \.self) { cents in
                    Button {
                        setup.lockedValues[row.color] = cents
                        Haptics.selection()
                    } label: {
                        if cents == row.valueCents {
                            Label(Money.format(cents: cents), systemImage: "checkmark")
                        } else {
                            Text(Money.format(cents: cents))
                        }
                    }
                }
                if isFixed {
                    Button(role: .destructive) {
                        setup.lockedValues[row.color] = nil
                        Haptics.selection()
                    } label: {
                        Label("Let the app choose", systemImage: "lock.open")
                    }
                }
            }
        } label: {
            HStack(spacing: Spacing.xs) {
                Text("\(Money.format(cents: row.valueCents)) each")
                Image(systemName: isFixed || isPrinted ? "lock.fill" : "chevron.up.chevron.down")
                    .font(.caption2)
                    .accessibilityHidden(true)
            }
            .font(.pokerFootnote)
            .foregroundStyle(isFixed || isPrinted ? Color.pokerGoldLight : Color.pokerTextSecondary)
            .frame(minHeight: Spacing.minTapTarget, alignment: .leading)
            .contentShape(Rectangle())
        }
        .accessibilityLabel("\(row.color) chip value, \(Money.format(cents: row.valueCents)) each")
        .accessibilityValue(isPrinted ? "Printed on the chips" : (isFixed ? "Fixed" : "Chosen by the app"))
        .accessibilityHint(isPrinted ? "" : "Choose a value to fix it while the rest is worked out")
        .accessibilityIdentifier("suggested.value.\(row.color)")
    }

    @ViewBuilder
    private func ownedLine(_ row: SuggestedViewModel.Row) -> some View {
        if let owned = setup.inventory?.owned[row.color] {
            let needed = row.count * setup.players
            Text("Uses \(needed) of your \(owned)")
                .font(.pokerCaption)
                .foregroundStyle(needed * 10 >= owned * 9 ? Color.pokerWarning : Color.pokerTextTertiary)
                .accessibilityIdentifier("suggested.uses.\(row.color)")
        }
    }

    private func totalLine(_ suggestion: SuggestedViewModel.Suggestion) -> some View {
        let label = Text("Each player gets")
            .font(.pokerCallout)
            .foregroundStyle(.pokerTextSecondary)
        let value = HStack(spacing: Spacing.sm) {
            Text("\(suggestion.totalChips) chips · \(Money.format(cents: suggestion.totalCents))")
                .font(.pokerNumeric(.headline))
                .foregroundStyle(.pokerTextPrimary)
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(Color.pokerPositive)
                .accessibilityHidden(true)
        }
        return ViewThatFits(in: .horizontal) {
            HStack(spacing: Spacing.sm) {
                label
                Spacer(minLength: Spacing.sm)
                value
            }
            VStack(alignment: .leading, spacing: Spacing.xs) {
                label
                value
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .pokerCard(padding: Spacing.md)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Each player gets \(suggestion.totalChips) chips worth \(Money.format(cents: suggestion.totalCents)) in total")
        .accessibilityIdentifier("suggested.total")
    }

    // MARK: Blinds and the reasoning

    @ViewBuilder
    private func blindsCard(_ suggestion: SuggestedViewModel.Suggestion) -> some View {
        if let blinds {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                SectionHeader(title: "Blinds")
                let amounts = Text("\(Money.format(cents: blinds.smallMinor)) / \(Money.format(cents: blinds.bigMinor))")
                    .font(.pokerNumeric(.title3))
                    .foregroundStyle(Color.pokerGoldLight)
                    .accessibilityLabel("Blinds, \(Money.format(cents: blinds.smallMinor)) small, \(Money.format(cents: blinds.bigMinor)) big")
                    .accessibilityIdentifier("suggested.blinds")
                let steps = HStack(spacing: Spacing.md) {
                    blindsStepButton("minus", delta: -1, suggestion: suggestion)
                    blindsStepButton("plus", delta: 1, suggestion: suggestion)
                }
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: Spacing.md) {
                        amounts
                        Spacer(minLength: Spacing.sm)
                        steps
                    }
                    VStack(alignment: .leading, spacing: Spacing.sm) {
                        amounts
                        steps
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Text("About \(BlindsPlanner.bigBlinds(inStackCents: suggestion.totalCents, blinds: blinds)) big blinds in a starting stack, and every bet can be paid with your smallest chip.")
                    .font(.pokerFootnote)
                    .foregroundStyle(.pokerTextSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .pokerCard(padding: Spacing.md)
        }
    }

    private func blindsStepButton(_ symbol: String, delta: Int, suggestion: SuggestedViewModel.Suggestion) -> some View {
        Button {
            if let current = blinds {
                blinds = BlindsPlanner.stepped(current, by: delta, smallestChipCents: suggestion.smallestChipCents)
                Haptics.selection()
            }
        } label: {
            Image(systemName: symbol)
                .font(.body.weight(.bold))
                .foregroundStyle(Color.pokerGoldLight)
                .frame(width: Spacing.minTapTarget, height: Spacing.minTapTarget)
                .background(Color.pokerGold.opacity(0.14))
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(delta > 0 ? "Raise the blinds" : "Lower the blinds")
        .accessibilityIdentifier("suggested.blinds.\(symbol)")
    }

    private func whyCard(_ suggestion: SuggestedViewModel.Suggestion) -> some View {
        DisclosureGroup(isExpanded: $showsWhy) {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                Text("Every stack adds up to exactly the buy-in. Each colour is worth more than the one before it, and there are fewer of them, the way a real set is racked. Values come from a clean ladder — 5¢, 10¢, then multiples of 25¢ — wherever the buy-in allows, so a stack is easy to check in your head.")
                Text("The smallest chip is \(Money.format(cents: suggestion.smallestChipCents)), so that's the smallest bet and the unit the blinds are built from. Aim for 20–30 chips a player: fewer is quicker to count and rack, more gives finer change.")
                if let inventory = setup.inventory {
                    Text(inventory.printedValues == nil
                         ? "Counts stay within your \(inventory.totalOwned)-chip set."
                         : "Counts stay within your \(inventory.totalOwned)-chip set, and each colour keeps the value printed on it.")
                }
                if !setup.lockedValues.isEmpty {
                    Text("Values with a lock are the ones you fixed; the rest is worked out around them.")
                }
            }
            .font(.pokerFootnote)
            .foregroundStyle(.pokerTextSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, Spacing.sm)
        } label: {
            Text("Why these values?")
                .font(.pokerHeadline)
                .foregroundStyle(.pokerTextPrimary)
        }
        .tint(.pokerGoldLight)
        .pokerCard(padding: Spacing.md)
        .accessibilityIdentifier("suggested.why")
    }
}

struct CombinedDenominationsView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationStack {
            CombinedDenominationsView(setup: GameSetup(buyIn: 25, players: 6, availableColors: Set(allChipColors)))
                .environmentObject(NavigationCoordinator())
                .environmentObject(NightStore(repository: MemoryNightRepository()))
        }
    }
}
