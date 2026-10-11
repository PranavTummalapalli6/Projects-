//
//  PlayersView.swift
//  PokerChipApp
//
//  Who is playing, and where. Names are optional (blanks become "Player 2",
//  "Player 3"…), the first seat is the person holding the phone, and people
//  who played before are one tap away.
//

import SwiftUI

struct PlayersView: View {
    @EnvironmentObject private var coordinator: NavigationCoordinator
    @EnvironmentObject private var store: NightStore

    private let setup: GameSetup
    @State private var names: [String]
    @State private var place: String
    @FocusState private var focus: Field?

    private enum Field: Hashable {
        case name(Int)
        case place
    }

    init(setup: GameSetup) {
        self.setup = setup
        _names = State(initialValue: setup.namesForTable)
        _place = State(initialValue: setup.location ?? "")
    }

    private var duplicateSeats: Set<Int> { PlayerNaming.duplicateSeats(in: names) }

    // MARK: Body

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.xl) {
                StepIndicator(current: 0)
                namesSection
                placeSection
            }
            .padding(.horizontal, Spacing.gutter)
            .padding(.vertical, Spacing.lg)
            .pokerReadableWidth()
        }
        .scrollDismissesKeyboard(.interactively)
        .background(PokerBackground())
        .navigationTitle("Players")
        .navigationBarTitleDisplayMode(.inline)
        .keyboardDoneButton()
        .safeAreaInset(edge: .bottom, spacing: 0) {
            // While a field is being typed in, the keyboard's own Next and Done keys carry on. A
            // bar riding above the keyboard would sit over the field that comes next.
            if focus == nil {
                PokerButton(title: "Next", isEnabled: duplicateSeats.isEmpty, action: next)
                    .accessibilityIdentifier("players.next")
                    .pokerBottomBar()
            }
        }
    }

    // MARK: Names

    private var namesSection: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            SectionHeader(title: "Who's playing?")

            ForEach(names.indices, id: \.self) { index in
                nameRow(index)
            }

            if !duplicateSeats.isEmpty {
                Label("Each player needs a different name, so payments are clear.", systemImage: "exclamationmark.circle.fill")
                    .font(.pokerFootnote)
                    .foregroundStyle(.pokerNegative)
            }

            regularsRow

            Text("Names are optional. Anyone left blank is called Player 2, Player 3… The first seat is you.")
                .font(.pokerFootnote)
                .foregroundStyle(.pokerTextTertiary)
        }
    }

    private func nameRow(_ index: Int) -> some View {
        HStack(spacing: Spacing.md) {
            Text(index == 0 ? "You" : "\(index + 1)")
                .font(.pokerCaption)
                .foregroundStyle(index == 0 ? Color.black : Color.pokerTextSecondary)
                .frame(minWidth: 28, minHeight: 28)
                .padding(.horizontal, index == 0 ? Spacing.xs : 0)
                .background(index == 0 ? Color.pokerGold : Color.white.opacity(0.10))
                .clipShape(Capsule())
                .accessibilityHidden(true)

            TextField(index == 0 ? "Your name" : "Player \(index + 1)", text: $names[index])
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
                .submitLabel(index == names.count - 1 ? .done : .next)
                .focused($focus, equals: .name(index))
                .onSubmit { advance(from: index) }
                .accessibilityLabel(index == 0 ? "Your name" : "Name of player \(index + 1)")
                .accessibilityIdentifier("players.name.\(index)")
        }
        .pokerTextField(isError: duplicateSeats.contains(index))
    }

    @ViewBuilder
    private var regularsRow: some View {
        let typed: String = { if case .name(let index)? = focus, names.indices.contains(index) { return names[index] } else { return "" } }()
        let choices = Regulars.suggestions(from: Regulars.names(from: store.nights), matching: typed, excluding: names, limit: 8)
        if !choices.isEmpty {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                Text("Regulars")
                    .font(.pokerFootnote.weight(.semibold))
                    .foregroundStyle(.pokerTextSecondary)
                FlowLayout {
                    ForEach(choices, id: \.self) { name in
                        QuickPickChip(title: name) { use(name) }
                            .accessibilityLabel("Add \(name)")
                            .accessibilityIdentifier("players.regular.\(name)")
                    }
                }
            }
        }
    }

    // MARK: Place

    private var placeSection: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            SectionHeader(title: "Where? (optional)")

            TextField("Pat's garage", text: $place)
                .textInputAutocapitalization(.words)
                .submitLabel(.done)
                .focused($focus, equals: .place)
                .pokerTextField()
                .accessibilityLabel("Where you're playing")
                .accessibilityIdentifier("players.place")

            let choices = Regulars.suggestions(from: Regulars.places(from: store.nights), matching: place, excluding: [place], limit: 5)
            if !choices.isEmpty {
                FlowLayout {
                    ForEach(choices, id: \.self) { choice in
                        QuickPickChip(title: choice, systemImage: "mappin.and.ellipse") { place = choice }
                            .accessibilityLabel("Play at \(choice)")
                    }
                }
            }
        }
    }

    // MARK: Actions

    private func use(_ regular: String) {
        let isBlank: (Int) -> Bool = { names[$0].trimmingCharacters(in: .whitespaces).isEmpty }
        let target: Int
        if case .name(let index)? = focus {
            target = index
        } else if let firstBlank = names.indices.first(where: isBlank) {
            target = firstBlank
        } else {
            return
        }
        names[target] = regular
        focus = names.indices.first(where: { $0 > target && isBlank($0) }).map { Field.name($0) }
    }

    private func advance(from index: Int) {
        focus = index + 1 < names.count ? .name(index + 1) : .place
    }

    private func next() {
        guard duplicateSeats.isEmpty else {
            Haptics.warning()
            return
        }
        var updated = setup
        updated.playerNames = names
        updated.location = PlayerNaming.trimmedOrNil(place)
        Stores.gameSetup.save(updated)
        coordinator.push(.chipStyle(updated))
    }
}

struct PlayersView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationStack {
            PlayersView(setup: GameSetup(buyIn: 25, players: 5, availableColors: Set(allChipColors), playerNames: ["Pranav", "Sam"]))
                .environmentObject(NavigationCoordinator())
                .environmentObject(NightStore(repository: MemoryNightRepository()))
        }
    }
}
