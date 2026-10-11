//
//  HistoryView.swift
//  PokerChipApp
//
//  Every night, newest first, grouped by month. Search finds a night by place,
//  player, notes or date; chips above the list narrow it by time, place and
//  stake. A swipe deletes a night and offers Undo for a few seconds.
//

import SwiftUI

struct HistoryView: View {
    @EnvironmentObject private var store: NightStore
    @EnvironmentObject private var coordinator: NavigationCoordinator

    @State private var filter = HistoryFilter()

    private var matches: [GameNight] { filter.apply(to: store.nights) }

    var body: some View {
        let sections = HistorySections.group(matches)
        Group {
            if store.phase == .loading {
                loading
            } else if store.nights.isEmpty {
                ScrollView {
                    VStack(spacing: Spacing.lg) {
                        StoreProblemBanners()
                        EmptyState(
                            icon: "clock.arrow.circlepath",
                            title: "No nights yet",
                            message: "Every game night you play is kept here — who played, what everyone won or lost, and who paid whom.",
                            actionTitle: "Start a night"
                        ) {
                            coordinator.tab = .play
                            if coordinator.path.isEmpty { coordinator.push(.buyIn(nil)) }
                        }
                        .accessibilityIdentifier("history.empty")
                    }
                    .padding(Spacing.gutter)
                    .pokerReadableWidth()
                }
            } else {
                list(sections)
            }
        }
        .background(PokerBackground())
        .navigationTitle("History")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $filter.query, placement: .navigationBarDrawer(displayMode: .automatic), prompt: "Place, player or note")
        .undoDeleteBanner()
    }

    // MARK: List

    private func list(_ sections: [HistorySection]) -> some View {
        List {
            Section {
                VStack(spacing: Spacing.md) {
                    StoreProblemBanners()
                    filterBar
                }
                .listRowInsets(EdgeInsets(top: Spacing.sm, leading: Spacing.gutter, bottom: Spacing.sm, trailing: Spacing.gutter))
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            }

            if sections.isEmpty {
                Section {
                    EmptyState(
                        icon: "magnifyingglass",
                        title: "Nothing matches",
                        message: "No night has all of that. Try fewer words, or clear the filters.",
                        actionTitle: "Clear search and filters"
                    ) { filter.clear() }
                    .accessibilityIdentifier("history.noMatches")
                    .listRowInsets(EdgeInsets(top: Spacing.md, leading: Spacing.gutter, bottom: Spacing.md, trailing: Spacing.gutter))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                }
            }

            ForEach(sections) { section in
                Section {
                    ForEach(section.nights) { night in
                        row(night, index: flatIndex(of: night, in: sections))
                    }
                } header: {
                    sectionHeader(section)
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .refreshable { await refresh() }
        .accessibilityIdentifier("history.list")
    }

    private func flatIndex(of night: GameNight, in sections: [HistorySection]) -> Int {
        sections.flatMap(\.nights).firstIndex { $0.id == night.id } ?? 0
    }

    private func sectionHeader(_ section: HistorySection) -> some View {
        HStack {
            Text(section.monthStart.formatted(.dateTime.month(.wide).year()).uppercased())
                .font(.pokerCaption)
                .tracking(0.8)
                .foregroundStyle(Color.pokerPurpleLight)
            Spacer()
            if let net = section.netMinor {
                MoneyText(cents: net, signed: true, font: .pokerNumeric(.footnote), color: net >= 0 ? .pokerPositive : .pokerNegative)
            }
        }
        .padding(.horizontal, Spacing.gutter)
        .padding(.vertical, Spacing.xs)
        .background(Color.pokerBackgroundTop.opacity(0.92))
        .textCase(nil)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    private func row(_ night: GameNight, index: Int) -> some View {
        // The link sits invisibly over the row, so the list doesn't add its own chevron.
        ZStack {
            HistoryRow(night: night)
                .accessibilityIdentifier("history.row.\(index)")
            NavigationLink {
                NightDetailView(nightID: night.id)
            } label: {
                EmptyView()
            }
            .opacity(0)
            .accessibilityHidden(true)
        }
        .listRowInsets(EdgeInsets(top: 6, leading: Spacing.gutter, bottom: 6, trailing: Spacing.gutter))
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive) { delete(night) } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    private func delete(_ night: GameNight) {
        store.delete(night.id)
        Haptics.warning()
    }

    /// Pulling down checks in with the server now rather than waiting for the next change.
    private func refresh() async {
        store.retrySaving()
        try? await Task.sleep(nanoseconds: 400_000_000)
    }

    // MARK: Filters

    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Spacing.sm) {
                filterMenu(
                    title: filter.range == .all ? "Any time" : filter.range.rawValue,
                    isOn: filter.range != .all,
                    identifier: "history.filter.range"
                ) {
                    ForEach(HistoryFilter.DateRange.allCases) { range in
                        menuItem(range.rawValue, isSelected: filter.range == range) { filter.range = range }
                    }
                }

                let places = HistoryFilter.places(in: store.nights)
                if !places.isEmpty {
                    filterMenu(title: filter.place ?? "Any place", isOn: filter.place != nil, identifier: "history.filter.place") {
                        Button("Any place") { filter.place = nil }
                        ForEach(places, id: \.self) { place in
                            menuItem(place, isSelected: filter.place?.lowercased() == place.lowercased()) { filter.place = place }
                        }
                    }
                }

                let stakes = HistoryFilter.stakes(in: store.nights)
                if stakes.count > 1 {
                    filterMenu(
                        title: filter.stakeMinor.map { Money.format(cents: $0) } ?? "Any stake",
                        isOn: filter.stakeMinor != nil,
                        identifier: "history.filter.stake"
                    ) {
                        Button("Any stake") { filter.stakeMinor = nil }
                        ForEach(stakes, id: \.self) { stake in
                            menuItem(Money.format(cents: stake), isSelected: filter.stakeMinor == stake) { filter.stakeMinor = stake }
                        }
                    }
                }

                if filter.isActive {
                    QuickPickChip(title: "Clear", systemImage: "xmark") { filter.clear() }
                        .accessibilityIdentifier("history.filter.clear")
                }
            }
        }
    }

    @ViewBuilder
    private func menuItem(_ title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            if isSelected {
                Label(title, systemImage: "checkmark")
            } else {
                Text(title)
            }
        }
    }

    private func filterMenu<Content: View>(title: String, isOn: Bool, identifier: String, @ViewBuilder content: () -> Content) -> some View {
        Menu {
            content()
        } label: {
            HStack(spacing: Spacing.xs) {
                Text(title).font(.pokerFootnote.weight(.semibold)).lineLimit(1)
                Image(systemName: "chevron.down").font(.caption2.weight(.bold)).accessibilityHidden(true)
            }
            .foregroundStyle(isOn ? Color.black : Color.pokerGoldLight)
            .padding(.horizontal, Spacing.md)
            .frame(minHeight: Spacing.minTapTarget)
            .background(isOn ? Color.pokerGold : Color.pokerGold.opacity(0.12))
            .clipShape(Capsule())
        }
        .accessibilityIdentifier(identifier)
    }

    // MARK: Loading

    private var loading: some View {
        VStack(spacing: Spacing.md) {
            ForEach(0..<5, id: \.self) { _ in
                SkeletonView(cornerRadius: Radius.card).frame(height: 76)
            }
        }
        .padding(Spacing.gutter)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Loading your nights")
    }
}

// MARK: - One row

struct HistoryRow: View {
    let night: GameNight

    var body: some View {
        let summary = NightSummary(night: night)
        VStack(alignment: .leading, spacing: Spacing.xs) {
            HStack(alignment: .firstTextBaseline, spacing: Spacing.sm) {
                Text(night.startedAt.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()))
                    .font(.pokerHeadline)
                    .foregroundStyle(.pokerTextPrimary)
                Spacer(minLength: Spacing.sm)
                trailing(summary)
            }
            Text(detail(summary))
                .font(.pokerFootnote)
                .foregroundStyle(.pokerTextSecondary)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .pokerCard(padding: Spacing.md)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel(summary))
        .accessibilityAddTraits(.isButton)
    }

    @ViewBuilder
    private func trailing(_ summary: NightSummary) -> some View {
        if night.isSettled {
            if let net = summary.myNetMinor {
                MoneyText(cents: net, signed: true, font: .pokerNumeric(.headline), color: net == 0 ? .pokerTextSecondary : (net > 0 ? .pokerPositive : .pokerNegative))
            } else {
                Text("—").font(.pokerNumeric(.headline)).foregroundStyle(.pokerTextTertiary)
            }
        } else {
            Text(night.isLive ? "In progress" : "Cashing out")
                .font(.pokerCaption)
                .foregroundStyle(Color.black)
                .padding(.horizontal, Spacing.sm)
                .padding(.vertical, 3)
                .background(Color.pokerGold)
                .clipShape(Capsule())
        }
    }

    private func detail(_ summary: NightSummary) -> String {
        var parts: [String] = []
        parts.append(night.location ?? "No place")
        parts.append("\(night.players.count) players")
        parts.append(DurationFormat.compact(summary.playtimeSeconds))
        return parts.joined(separator: " · ")
    }

    private func accessibilityLabel(_ summary: NightSummary) -> String {
        var text = night.startedAt.formatted(.dateTime.weekday(.wide).month(.wide).day()) + ". " + detail(summary).replacingOccurrences(of: " · ", with: ", ") + "."
        if night.isSettled, let net = summary.myNetMinor {
            text += net == 0 ? " You finished even." : (net > 0 ? " You were up \(Money.spoken(cents: net))." : " You were down \(Money.spoken(cents: -net)).")
        } else if !night.isSettled {
            text += night.isLive ? " In progress." : " Cashing out."
        }
        return text
    }
}
