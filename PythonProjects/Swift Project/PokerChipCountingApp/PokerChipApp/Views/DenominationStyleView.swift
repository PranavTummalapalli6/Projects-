//
//  DenominationStyleView.swift
//  PokerChipApp
//
//  Created by Pranav on 4/2/25.
//

import SwiftUI

/// "Chip values": how this game's chips get their values. Suggested works
/// them out, Custom lets the host decide, and — when the last night used the
/// same stack — "Same chips as last time" reuses them as they were.
struct DenominationStyleView: View {
    let setup: GameSetup

    @EnvironmentObject private var coordinator: NavigationCoordinator
    @EnvironmentObject private var store: NightStore

    /// Only offered when the last night's chips are still the right ones for this stack.
    private var sameChipsNight: GameNight? { store.lastNight(matching: setup) }

    var body: some View {
        ScrollView {
            VStack(spacing: Spacing.lg) {
                StepIndicator(current: 1)

                summaryCard

                NavigationLink(value: AppRoute.suggested(setup)) {
                    ListRow(
                        icon: "sparkles",
                        title: "Suggested",
                        subtitle: "Chip values and counts worked out for this buy-in"
                    )
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("style.suggested")

                NavigationLink(value: AppRoute.custom(setup)) {
                    ListRow(
                        icon: "slider.horizontal.3",
                        title: "Custom",
                        subtitle: "Set your own chip values and counts"
                    )
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("style.custom")

                if let last = sameChipsNight {
                    Button {
                        let night = store.startNight(
                            from: setup,
                            buyInMinor: last.defaultBuyInMinor,
                            denominationsMinor: last.denominationsMinor,
                            startingCounts: last.startingCounts
                        )
                        coordinator.open(night: night.id)
                    } label: {
                        ListRow(
                            icon: "arrow.counterclockwise",
                            title: "Same chips as last time",
                            subtitle: "Start the night with the chip values and counts you used on \(last.startedAt.formatted(.dateTime.month().day())).",
                            showsChevron: false
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("style.sameChips")
                }
            }
            .padding(.horizontal, Spacing.gutter)
            .padding(.vertical, Spacing.lg)
            .pokerReadableWidth()
        }
        .background(PokerBackground())
        .navigationTitle("Chip values")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var summaryCard: some View {
        HStack(spacing: Spacing.lg) {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text(Money.format(setup.buyIn))
                    .font(.pokerNumeric(.title2))
                    .foregroundStyle(Color.pokerGoldLight)
                Text("\(setup.players) players")
                    .font(.pokerFootnote)
                    .foregroundStyle(.pokerTextSecondary)
            }
            Spacer(minLength: Spacing.sm)
            HStack(spacing: -10) {
                ForEach(setup.colors, id: \.self) { color in
                    ChipView(color: color, size: 30)
                }
            }
            .accessibilityHidden(true)
        }
        .pokerCard()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(Money.format(setup.buyIn)) buy-in, \(setup.players) players, \(setup.colors.joined(separator: ", ")) chips")
    }
}

struct DenominationStyleView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationStack {
            DenominationStyleView(setup: GameSetup(buyIn: 50, players: 4, availableColors: Set(allChipColors)))
                .environmentObject(NavigationCoordinator())
                .environmentObject(NightStore(repository: MemoryNightRepository()))
        }
    }
}
