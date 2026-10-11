//
//  TableCard.swift
//  PokerChipApp
//
//  A card to prop up in the middle of the table: each colour of chip, what it
//  is worth, and how many each player starts with — big enough to read from
//  across the table. A picture or a PDF of it can be shared with the group.
//  It carries no names, places or dates, so it is safe to send anywhere.
//

import SwiftUI
import UIKit
import os

/// What the card shows.
struct TableCardContent: Equatable {
    struct Row: Equatable, Identifiable {
        let color: String
        let valueCents: Int
        /// How many each player starts with; nil if the night didn't record a stack.
        let count: Int?

        var id: String { color }
    }

    let rows: [Row]
    let buyInCents: Int
    let blinds: Blinds?
    let currencyCode: String

    /// The size of the starting stack, when every colour says how many.
    var chipsPerPlayer: Int? {
        let counts = rows.compactMap(\.count)
        return !rows.isEmpty && counts.count == rows.count ? counts.reduce(0, +) : nil
    }

    var stackLine: String {
        let money = Money.format(cents: buyInCents, currencyCode: currencyCode)
        if let chips = chipsPerPlayer { return "Each player starts with \(chips) chips · \(money)" }
        return "Buy-in \(money)"
    }

    var blindsLine: String? {
        blinds.map {
            "Blinds \(Money.format(cents: $0.smallMinor, currencyCode: currencyCode)) / \(Money.format(cents: $0.bigMinor, currencyCode: currencyCode))"
        }
    }
}

extension TableCardContent {
    init(suggestion: SuggestedViewModel.Suggestion, blinds: Blinds?, currencyCode: String = Money.defaultCurrencyCode) {
        self.init(
            rows: suggestion.rows.map { Row(color: $0.color, valueCents: $0.valueCents, count: $0.count) },
            buyInCents: suggestion.totalCents,
            blinds: blinds,
            currencyCode: currencyCode
        )
    }

    /// The chips a night is being played with; nil if it has none to show.
    init?(night: GameNight) {
        let rows = allChipColors.compactMap { color -> Row? in
            guard night.colors.contains(color), let value = night.denominationsMinor[color], value > 0 else { return nil }
            return Row(color: color, valueCents: value, count: night.startingCounts?[color])
        }
        guard !rows.isEmpty else { return nil }
        self.init(rows: rows, buyInCents: night.defaultBuyInMinor, blinds: night.blinds, currencyCode: night.currency)
    }
}

// MARK: - The card itself

/// Drawn to whatever size it is given, so the same artwork fills a landscape
/// phone and becomes the picture that is shared. Sizes come from the height, not
/// Dynamic Type: this is made to be read from a distance.
struct TableCardArtwork<Controls: View>: View {
    let content: TableCardContent
    var drawsBackground = false
    @ViewBuilder var controls: () -> Controls

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let height = proxy.size.height
            let columns = CGFloat(max(content.rows.count, 1))
            let chip = max(24, min(height * 0.30, width / columns * 0.60))

            ZStack {
                if drawsBackground { PokerBackground() }
                VStack(spacing: 0) {
                    titleRow(height: height)
                    Spacer(minLength: 0)
                    HStack(alignment: .top, spacing: 0) {
                        ForEach(content.rows) { row in
                            column(row, chip: chip, height: height)
                                .frame(maxWidth: .infinity)
                        }
                    }
                    Spacer(minLength: 0)
                    footer(height: height)
                }
                .padding(.horizontal, width * 0.03)
                .padding(.vertical, height * 0.03)
            }
            .frame(width: width, height: height)
        }
    }

    private func titleRow(height: CGFloat) -> some View {
        ZStack {
            Text("Chip values")
                .font(.system(size: max(18, height * 0.07), weight: .heavy, design: .rounded))
                .foregroundStyle(Color.pokerGoldLight)
                .accessibilityAddTraits(.isHeader)
            controls()
        }
        .frame(height: max(Spacing.minTapTarget, height * 0.10))
    }

    private func column(_ row: TableCardContent.Row, chip: CGFloat, height: CGFloat) -> some View {
        VStack(spacing: height * 0.015) {
            ChipView(color: row.color, size: chip)
            Text(Money.format(cents: row.valueCents, currencyCode: content.currencyCode))
                .font(.system(size: chip * 0.42, weight: .heavy, design: .rounded).monospacedDigit())
                .foregroundStyle(Color.pokerTextPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
            Text(row.color)
                .font(.system(size: max(12, chip * 0.20), weight: .semibold, design: .rounded))
                .foregroundStyle(Color.pokerTextSecondary)
            if let count = row.count {
                Text("\(count) each")
                    .font(.system(size: max(12, chip * 0.20), weight: .regular, design: .rounded).monospacedDigit())
                    .foregroundStyle(Color.pokerTextSecondary)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(row.color) chip")
        .accessibilityValue(
            "\(Money.spoken(cents: row.valueCents, currencyCode: content.currencyCode)) each"
                + (row.count.map { ", \($0) per player" } ?? "")
        )
        .accessibilityIdentifier("tablecard.row.\(row.color)")
    }

    private func footer(height: CGFloat) -> some View {
        VStack(spacing: height * 0.01) {
            Text(content.stackLine)
                .accessibilityIdentifier("tablecard.stack")
            if let blinds = content.blindsLine {
                Text(blinds)
                    .foregroundStyle(Color.pokerGoldLight)
                    .accessibilityIdentifier("tablecard.blinds")
            }
        }
        .font(.system(size: max(13, height * 0.048), weight: .semibold, design: .rounded).monospacedDigit())
        .foregroundStyle(Color.pokerTextSecondary)
        .multilineTextAlignment(.center)
        .lineLimit(1)
        .minimumScaleFactor(0.6)
    }
}

extension TableCardArtwork where Controls == EmptyView {
    init(content: TableCardContent, drawsBackground: Bool = false) {
        self.init(content: content, drawsBackground: drawsBackground) { EmptyView() }
    }
}

// MARK: - Sharing

/// The card as a picture and as a PDF, written to temporary files so the share
/// sheet can hand them to anything.
@MainActor
enum TableCardExporter {
    struct Files {
        let png: URL
        let pdf: URL
        let preview: Image
    }

    private static let log = Logger(subsystem: "Vanarp.PokerChipApp", category: "table-card")
    private static let pageSize = CGSize(width: 800, height: 450)

    static func export(_ content: TableCardContent, directory: URL = FileManager.default.temporaryDirectory) -> Files? {
        let artwork = TableCardArtwork(content: content, drawsBackground: true)
            .frame(width: pageSize.width, height: pageSize.height)
            .environment(\.colorScheme, .dark)
        let renderer = ImageRenderer(content: artwork)
        renderer.scale = 3

        guard let image = renderer.uiImage, let png = image.pngData() else {
            log.error("The table card could not be drawn")
            return nil
        }
        let pngURL = directory.appendingPathComponent("Chip values.png")
        let pdfURL = directory.appendingPathComponent("Chip values.pdf")
        do {
            try png.write(to: pngURL, options: .atomic)
        } catch {
            log.error("Could not save the table card picture: \(error.localizedDescription, privacy: .public)")
            return nil
        }

        var wrotePDF = false
        renderer.render(rasterizationScale: 3) { size, draw in
            var box = CGRect(origin: .zero, size: size)
            guard let context = CGContext(pdfURL as CFURL, mediaBox: &box, nil) else { return }
            context.beginPDFPage(nil)
            draw(context)
            context.endPDFPage()
            context.closePDF()
            wrotePDF = true
        }
        guard wrotePDF else {
            log.error("Could not save the table card PDF")
            return nil
        }
        return Files(png: pngURL, pdf: pdfURL, preview: Image(uiImage: image))
    }
}

// MARK: - On screen

/// Full screen and landscape; the screen stays awake while it is up, because the
/// phone is leaning against a glass.
struct TableCardView: View {
    let content: TableCardContent

    @Environment(\.dismiss) private var dismiss
    @State private var files: TableCardExporter.Files?
    /// Whether the screen was already being kept awake (a night in progress does), to put back as it was.
    @State private var wasKeepingAwake = false

    var body: some View {
        ZStack {
            PokerBackground()
            TableCardArtwork(content: content) {
                HStack {
                    closeButton
                    Spacer(minLength: Spacing.md)
                    shareMenu
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("tablecard")
        .onAppear {
            OrientationLock.allowLandscape()
            wasKeepingAwake = UIApplication.shared.isIdleTimerDisabled
            UIApplication.shared.isIdleTimerDisabled = true
        }
        .onDisappear {
            OrientationLock.restorePortrait()
            UIApplication.shared.isIdleTimerDisabled = wasKeepingAwake
        }
        .task { files = TableCardExporter.export(content) }
    }

    private var closeButton: some View {
        Button {
            dismiss()
        } label: {
            Image(systemName: "xmark")
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(Color.pokerGoldLight)
                .frame(width: Spacing.minTapTarget, height: Spacing.minTapTarget)
                .background(Color.pokerGold.opacity(0.14))
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Close the card")
        .accessibilityIdentifier("tablecard.close")
    }

    @ViewBuilder
    private var shareMenu: some View {
        if let files {
            Menu {
                ShareLink(item: files.png, preview: SharePreview("Chip values", image: files.preview)) {
                    Label("Share as a picture", systemImage: "photo")
                }
                ShareLink(item: files.pdf, preview: SharePreview("Chip values", image: files.preview)) {
                    Label("Share as a PDF", systemImage: "doc.richtext")
                }
            } label: {
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(Color.pokerGoldLight)
                    .frame(width: Spacing.minTapTarget, height: Spacing.minTapTarget)
                    .background(Color.pokerGold.opacity(0.14))
                    .clipShape(Circle())
            }
            .accessibilityLabel("Share the card")
            .accessibilityIdentifier("tablecard.share")
        } else {
            Color.clear.frame(width: Spacing.minTapTarget, height: Spacing.minTapTarget)
        }
    }
}

struct TableCardView_Previews: PreviewProvider {
    static var previews: some View {
        TableCardView(
            content: TableCardContent(
                rows: [
                    .init(color: "White", valueCents: 5, count: 20),
                    .init(color: "Red", valueCents: 10, count: 12),
                    .init(color: "Blue", valueCents: 25, count: 8),
                    .init(color: "Green", valueCents: 50, count: 4),
                    .init(color: "Black", valueCents: 100, count: 2),
                ],
                buyInCents: 2_500,
                blinds: Blinds(smallMinor: 25, bigMinor: 50),
                currencyCode: "USD"
            )
        )
        .previewInterfaceOrientation(.landscapeLeft)
    }
}
