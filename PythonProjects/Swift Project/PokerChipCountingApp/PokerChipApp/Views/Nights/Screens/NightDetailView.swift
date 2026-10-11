//
//  NightDetailView.swift
//  PokerChipApp
//
//  One night in full: when and where, what each player put in, took out and
//  finished with, who paid whom, the chip photos taken at cash-out, and notes
//  the person can keep adding to. A night that was settled can be reopened to
//  fix a mistake; one that wasn't can be picked back up.
//

import SwiftUI

struct NightDetailView: View {
    let nightID: UUID

    @EnvironmentObject private var store: NightStore
    @EnvironmentObject private var coordinator: NavigationCoordinator
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    @State private var notes = ""
    @State private var place = ""
    @State private var fieldsLoaded = false
    @State private var confirmDelete = false
    @State private var photos: PhotoState = .idle
    @FocusState private var focus: Field?

    private enum Field: Hashable { case place, notes }

    enum PhotoState: Equatable {
        case idle
        case loading
        case found([Found])
        case none
        case failed(String)

        struct Found: Equatable, Identifiable {
            let name: String
            let url: URL
            var id: String { url.absoluteString }
        }
    }

    var body: some View {
        Group {
            if let night = store.night(nightID) {
                content(night)
            } else {
                EmptyState(
                    icon: "questionmark.folder",
                    title: "This night isn't here any more",
                    message: "It may have been deleted on another device.",
                    actionTitle: "Back"
                ) { dismiss() }
                .padding(Spacing.gutter)
                .pokerReadableWidth()
            }
        }
        .background(PokerBackground())
        .navigationTitle("Night")
        .navigationBarTitleDisplayMode(.inline)
        .keyboardDoneButton()
        .onChange(of: focus) { newFocus in
            if newFocus == nil { commitFields() }
        }
        .onDisappear(perform: commitFields)
        .confirmationDialog("Delete this night?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete night", role: .destructive) {
                store.delete(nightID)
                dismiss()
            }
            Button("Keep it", role: .cancel) {}
        } message: {
            Text("Everything recorded for it — buy-ins, cash-outs and notes — goes with it. You can undo for a few seconds.")
        }
    }

    // MARK: Content

    private func content(_ night: GameNight) -> some View {
        let summary = NightSummary(night: night)
        let entries = night.settlementEntries() ?? []
        let payments = night.payments() ?? []

        return ScrollView {
            VStack(spacing: Spacing.lg) {
                header(night, summary: summary)

                if night.isSettled, let net = summary.myNetMinor {
                    resultTile(net: net, summary: summary, currency: night.currency)
                }

                playersCard(night, entries: entries)

                if !payments.isEmpty {
                    paymentsCard(payments, night: night)
                }

                if night.isSettled {
                    ShareCardButton(title: "Share a night summary", previewTitle: "Game night", key: "\(night.updatedAt.timeIntervalSince1970)", card: NightSummaryCard(night: night))
                        .accessibilityIdentifier("detail.shareSummary")
                }

                detailsCard(night)

                photosCard(night)

                actions(night)
            }
            .padding(.horizontal, Spacing.gutter)
            .padding(.vertical, Spacing.lg)
            .pokerReadableWidth()
        }
        .scrollDismissesKeyboard(.interactively)
        .onAppear { loadFields(from: night) }
    }

    // MARK: Header and result

    private func header(_ night: GameNight, summary: NightSummary) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack(alignment: .firstTextBaseline) {
                Text(night.startedAt.formatted(.dateTime.weekday(.wide).month(.wide).day().year()))
                    .font(.pokerTitle)
                    .foregroundStyle(.pokerTextPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: Spacing.sm)
                statusBadge(night)
            }
            if let place = night.location {
                Label(place, systemImage: "mappin.and.ellipse")
                    .font(.pokerCallout)
                    .foregroundStyle(.pokerTextSecondary)
            }
            Text("\(DurationFormat.compact(summary.playtimeSeconds)) · \(Money.format(cents: night.totalInMinor, currencyCode: night.currency)) in play · \(night.players.count) players")
                .font(.pokerFootnote)
                .foregroundStyle(.pokerTextSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .pokerCard()
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("detail.header")
    }

    @ViewBuilder
    private func statusBadge(_ night: GameNight) -> some View {
        if !night.isSettled {
            Text(night.isLive ? "In progress" : "Cashing out")
                .font(.pokerCaption)
                .foregroundStyle(Color.black)
                .padding(.horizontal, Spacing.sm)
                .padding(.vertical, 3)
                .background(Color.pokerGold)
                .clipShape(Capsule())
        }
    }

    private func resultTile(net: Int, summary: NightSummary, currency: String) -> some View {
        HStack(spacing: Spacing.md) {
            StatTile(
                label: "Your result",
                value: Money.formatSigned(cents: net, currencyCode: currency),
                valueColor: net == 0 ? .pokerTextPrimary : (net > 0 ? .pokerPositive : .pokerNegative),
                spokenValue: net == 0 ? "Even" : "\(net > 0 ? "Up" : "Down") \(Money.spoken(cents: abs(net), currencyCode: currency))"
            )
            StatTile(
                label: "Per hour",
                value: summary.perHourMinor.map { Money.formatSigned(cents: $0, currencyCode: currency) } ?? "—",
                valueColor: summary.perHourMinor.map { $0 >= 0 ? Color.pokerPositive : Color.pokerNegative } ?? Color.pokerTextSecondary
            )
        }
        .accessibilityIdentifier("detail.result")
    }

    // MARK: Players

    private func playersCard(_ night: GameNight, entries: [NetEntry]) -> some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            SectionHeader(title: "Players")

            if dynamicTypeSize.isAccessibilitySize {
                ForEach(night.players) { player in
                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        Text(player.name + (night.myPlayerID == player.id ? " (you)" : ""))
                            .font(.pokerHeadline).foregroundStyle(.pokerTextPrimary)
                        Text("In \(Money.format(cents: player.totalInMinor, currencyCode: night.currency))")
                        Text(player.cashOutMinor.map { "Out \(Money.format(cents: $0, currencyCode: night.currency))" } ?? "Not cashed out")
                        if let net = net(of: player, in: entries) {
                            MoneyText(cents: net, signed: true, font: .pokerNumeric(.body), color: color(for: net))
                        }
                    }
                    .font(.pokerFootnote)
                    .foregroundStyle(.pokerTextSecondary)
                    .accessibilityElement(children: .combine)
                }
            } else {
                Grid(alignment: .trailing, horizontalSpacing: Spacing.md, verticalSpacing: Spacing.sm) {
                    GridRow {
                        Text("").gridColumnAlignment(.leading)
                        Text("In"); Text("Out"); Text("Result")
                    }
                    .font(.pokerCaption)
                    .foregroundStyle(.pokerTextTertiary)

                    ForEach(night.players) { player in
                        GridRow {
                            HStack(spacing: Spacing.xs) {
                                Text(player.name).lineLimit(1)
                                if night.myPlayerID == player.id {
                                    Text("you").font(.pokerCaption).foregroundStyle(Color.pokerGoldLight)
                                }
                            }
                            .gridColumnAlignment(.leading)
                            .font(.pokerCallout)
                            .foregroundStyle(.pokerTextPrimary)

                            MoneyText(cents: player.totalInMinor, font: .pokerNumeric(.footnote, weight: .regular), color: .pokerTextSecondary)
                            if let out = player.cashOutMinor {
                                MoneyText(cents: out, font: .pokerNumeric(.footnote, weight: .regular), color: .pokerTextSecondary)
                            } else {
                                Text("—").font(.pokerNumeric(.footnote)).foregroundStyle(.pokerTextTertiary)
                            }
                            if let net = net(of: player, in: entries) {
                                MoneyText(cents: net, signed: true, font: .pokerNumeric(.footnote), color: color(for: net))
                            } else {
                                Text("—").font(.pokerNumeric(.footnote)).foregroundStyle(.pokerTextTertiary)
                            }
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .pokerCard()
        .accessibilityIdentifier("detail.players")
    }

    private func net(of player: PlayerLedger, in entries: [NetEntry]) -> Int? {
        entries.first { $0.id == player.id }?.netMinor
    }

    private func color(for net: Int) -> Color {
        net == 0 ? .pokerTextSecondary : (net > 0 ? .pokerPositive : .pokerNegative)
    }

    private func paymentsCard(_ payments: [Payment], night: GameNight) -> some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            SectionHeader(title: "Who paid whom")
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
            ShareLink(item: SettleUpView.shareText(for: night, payments: payments)) {
                Label("Share payments", systemImage: "square.and.arrow.up").pokerSecondaryLabel()
            }
            .accessibilityIdentifier("detail.share")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .pokerCard()
    }

    // MARK: Place and notes

    private func detailsCard(_ night: GameNight) -> some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            SectionHeader(title: "Place and notes")

            TextField("Where was it?", text: $place)
                .textInputAutocapitalization(.words)
                .submitLabel(.done)
                .focused($focus, equals: .place)
                .onSubmit { focus = nil }
                .pokerTextField()
                .accessibilityLabel("Place")
                .accessibilityIdentifier("detail.place")

            let choices = Regulars.suggestions(from: Regulars.places(from: store.nights), matching: place, excluding: [place], limit: 4)
            if focus == .place, !choices.isEmpty {
                FlowLayout {
                    ForEach(choices, id: \.self) { choice in
                        QuickPickChip(title: choice, systemImage: "mappin.and.ellipse") { place = choice }
                    }
                }
            }

            TextField("Notes — anything worth remembering", text: $notes, axis: .vertical)
                .lineLimit(2...8)
                .focused($focus, equals: .notes)
                .pokerTextField()
                .accessibilityLabel("Notes")
                .accessibilityIdentifier("detail.notes")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .pokerCard()
    }

    private func loadFields(from night: GameNight) {
        guard !fieldsLoaded else { return }
        fieldsLoaded = true
        place = night.location ?? ""
        notes = night.notes ?? ""
    }

    /// Saves what was typed, if it changed. Runs when a field loses focus and when the screen goes.
    private func commitFields() {
        guard fieldsLoaded else { return }
        let newPlace = PlayerNaming.trimmedOrNil(place)
        let newNotes = PlayerNaming.notesOrNil(notes)
        store.mutate(nightID) { night in
            night.location = newPlace
            night.notes = newNotes
        }
    }

    // MARK: Chip photos

    private func photosCard(_ night: GameNight) -> some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            SectionHeader(title: "Chip photos")

            switch photos {
            case .idle:
                Text("Photos taken when players cashed out are kept privately for 30 days.")
                    .font(.pokerFootnote)
                    .foregroundStyle(.pokerTextSecondary)
                PokerButton(title: "Look for photos", systemImage: "photo.on.rectangle", kind: .secondary) {
                    Task { await loadPhotos(night) }
                }
                .accessibilityIdentifier("detail.photos")
            case .loading:
                HStack(spacing: Spacing.md) {
                    ProgressView().tint(.pokerGoldLight)
                    Text("Looking for photos…").font(.pokerCallout).foregroundStyle(.pokerTextPrimary)
                }
                .accessibilityElement(children: .combine)
            case .none:
                Text("No photos are stored for this night. Photos are only kept when a player's chips were counted from one, and for 30 days.")
                    .font(.pokerFootnote)
                    .foregroundStyle(.pokerTextSecondary)
                    .accessibilityIdentifier("detail.noPhotos")
            case .failed(let message):
                InlineBanner(kind: .warning, message: message, actionTitle: "Try again") {
                    Task { await loadPhotos(night) }
                }
            case .found(let found):
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: Spacing.md) {
                        ForEach(found) { photo in
                            VStack(alignment: .leading, spacing: Spacing.xs) {
                                AsyncImage(url: photo.url) { phase in
                                    switch phase {
                                    case .success(let image):
                                        image.resizable().scaledToFill()
                                    case .failure:
                                        Image(systemName: "photo.badge.exclamationmark").font(.title).foregroundStyle(.pokerTextTertiary)
                                    default:
                                        SkeletonView(cornerRadius: Radius.control)
                                    }
                                }
                                .frame(width: 150, height: 150)
                                .background(Color.white.opacity(0.06))
                                .clipShape(RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
                                Text(photo.name).font(.pokerFootnote).foregroundStyle(.pokerTextSecondary)
                            }
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel("Photo of \(photo.name)'s chips")
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .pokerCard()
    }

    private func loadPhotos(_ night: GameNight) async {
        photos = .loading
        var found: [PhotoState.Found] = []
        do {
            for player in night.players where player.isCashedOut {
                let sessionID = "\(night.id.uuidString)-\(player.id.uuidString.prefix(8))"
                if let url = try await ChipVisionAPIClient.shared.fetchPhotoURL(sessionId: sessionID) {
                    found.append(PhotoState.Found(name: player.name, url: url))
                }
            }
            photos = found.isEmpty ? .none : .found(found)
        } catch {
            let reason = (error as? ChipVisionAPIError)?.errorDescription ?? error.localizedDescription
            photos = .failed("Couldn't look for photos. \(reason)")
        }
    }

    // MARK: Actions

    private func actions(_ night: GameNight) -> some View {
        VStack(spacing: Spacing.md) {
            if night.isOpen {
                PokerButton(title: "Resume this night", systemImage: "play.fill") {
                    coordinator.open(night: night.id)
                    coordinator.tab = .play
                }
                .accessibilityIdentifier("detail.resume")
            } else if night.isSettled {
                PokerButton(title: "Reopen to fix a mistake", kind: .secondary) {
                    store.mutate(night.id) { $0.reopen() }
                    coordinator.open(night: night.id)
                    coordinator.tab = .play
                }
                .accessibilityIdentifier("detail.reopen")
            }

            PokerButton(title: "Delete this night", kind: .destructive) { confirmDelete = true }
                .accessibilityIdentifier("detail.delete")
        }
    }
}
