//
//  ShareCards.swift
//  PokerChipApp
//
//  Pictures to send to the group chat. A night's summary holds no names and no
//  results (who pays whom has its own card), and a week of playing is shared by
//  the hours, never by what was won or lost.
//

import SwiftUI
import UIKit

enum ShareCards {
    @MainActor
    static func image<Card: View>(_ card: Card, scale: CGFloat = 3) -> UIImage? {
        let renderer = ImageRenderer(content: card.environment(\.colorScheme, .dark))
        renderer.scale = scale
        return renderer.uiImage
    }
}

/// A button that draws a card once, then offers it to the share sheet as a picture.
struct ShareCardButton<Card: View>: View {
    let title: String
    let previewTitle: String
    /// Draw the card again when this changes.
    let key: String
    let card: Card

    @State private var image: UIImage?

    var body: some View {
        VStack(spacing: 0) {
            if let image {
                ShareLink(item: Image(uiImage: image), preview: SharePreview(previewTitle, image: Image(uiImage: image))) {
                    Label(title, systemImage: "photo").pokerSecondaryLabel()
                }
            }
        }
        // A task on an empty view never starts, so it lives on something that is always there.
        .background(Color.clear.task(id: key) { image = ShareCards.image(card) })
    }
}

// MARK: - A night

/// The date, the place and the shape of the night: how many played, for how long,
/// how much was in play and which chips were used.
struct NightSummaryCard: View {
    let night: GameNight
    var now = Date()

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("GAME NIGHT")
                    .font(.system(.caption, design: .rounded).weight(.heavy))
                    .tracking(1.2)
                    .foregroundStyle(Color.pokerPurpleLight)
                Text(night.startedAt.formatted(.dateTime.weekday(.wide).month(.wide).day()))
                    .font(.system(.title2, design: .rounded).weight(.bold))
                    .foregroundStyle(.white)
                if let place = night.location {
                    Text(place).font(.footnote).foregroundStyle(.white.opacity(0.72))
                }
            }

            Divider().overlay(Color.white.opacity(0.18))

            HStack(alignment: .top, spacing: 0) {
                stat("\(night.players.count)", night.players.count == 1 ? "player" : "players")
                stat(DurationFormat.compact(night.playtimeSeconds(at: now)), "played")
                stat(Money.format(cents: night.totalInMinor, currencyCode: night.currency), "in play")
            }

            let colors = allChipColors.filter { night.denominationsMinor[$0] != nil }
            if !colors.isEmpty {
                Divider().overlay(Color.white.opacity(0.18))
                HStack(spacing: 10) {
                    ForEach(colors, id: \.self) { color in
                        VStack(spacing: 4) {
                            ChipView(color: color, size: 30)
                            Text(Money.format(cents: night.denominationsMinor[color] ?? 0, currencyCode: night.currency))
                                .font(.system(.caption2, design: .rounded).weight(.semibold).monospacedDigit())
                                .foregroundStyle(.white.opacity(0.8))
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
            }

            Text("Chip Counter")
                .font(.system(.caption2, design: .rounded).weight(.semibold))
                .foregroundStyle(.white.opacity(0.5))
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(24)
        .frame(width: 360, alignment: .leading)
        .background(LinearGradient(colors: [.pokerBackgroundTop, .pokerBackgroundBottom], startPoint: .top, endPoint: .bottom))
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).stroke(Color.pokerGold.opacity(0.4), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(.title3, design: .rounded).weight(.bold).monospacedDigit())
                .foregroundStyle(Color.pokerGoldLight)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(label)
                .font(.system(.caption, design: .rounded))
                .foregroundStyle(.white.opacity(0.7))
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - A week

/// Hours at the table over the last seven days, a bar for each, and how that
/// compares with the week before.
struct WeeklyRecapCard: View {
    let summary: WeeklySummary
    let trend: WeekTrend

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("MY WEEK AT THE TABLE")
                    .font(.system(.caption, design: .rounded).weight(.heavy))
                    .tracking(1.2)
                    .foregroundStyle(Color.pokerPurpleLight)
                if let range = Self.rangeText(summary.days) {
                    Text(range).font(.footnote).foregroundStyle(.white.opacity(0.72))
                }
                Text(summary.totalSeconds == 0 ? "No poker" : DurationFormat.compact(summary.totalSeconds))
                    .font(.system(size: 44, weight: .heavy, design: .rounded).monospacedDigit())
                    .foregroundStyle(LinearGradient(colors: [.pokerGoldLight, .pokerGold], startPoint: .top, endPoint: .bottom))
            }

            bars

            Text(trend.comparison)
                .font(.system(.footnote, design: .rounded).weight(.semibold))
                .foregroundStyle(.white.opacity(0.85))

            Text("Chip Counter")
                .font(.system(.caption2, design: .rounded).weight(.semibold))
                .foregroundStyle(.white.opacity(0.5))
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(24)
        .frame(width: 360, alignment: .leading)
        .background(LinearGradient(colors: [.pokerBackgroundTop, .pokerBackgroundBottom], startPoint: .top, endPoint: .bottom))
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).stroke(Color.pokerGold.opacity(0.4), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    private var bars: some View {
        let longest = max(summary.days.map(\.seconds).max() ?? 0, 1)
        return HStack(alignment: .bottom, spacing: 8) {
            ForEach(Array(summary.days.enumerated()), id: \.offset) { _, day in
                VStack(spacing: 6) {
                    Capsule()
                        .fill(day.seconds == 0 ? Color.white.opacity(0.14) : Color.pokerGold)
                        .frame(height: day.seconds == 0 ? 6 : max(10, 90 * CGFloat(day.seconds) / CGFloat(longest)))
                    Text(Self.weekdayLetter(day.date))
                        .font(.system(.caption2, design: .rounded).weight(.semibold))
                        .foregroundStyle(.white.opacity(0.7))
                }
                .frame(maxWidth: .infinity)
            }
        }
        .frame(height: 110, alignment: .bottom)
    }

    private static func date(_ text: String) -> Date? {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: text)
    }

    /// "M", "T", "W"… for a day written yyyy-MM-dd.
    static func weekdayLetter(_ text: String) -> String {
        guard let date = date(text) else { return "" }
        return date.formatted(.dateTime.weekday(.narrow))
    }

    /// "Oct 3 – Oct 9".
    static func rangeText(_ days: [WeeklySummary.DaySummary]) -> String? {
        guard let first = days.first.flatMap({ date($0.date) }), let last = days.last.flatMap({ date($0.date) }) else { return nil }
        let style = Date.FormatStyle.dateTime.month(.abbreviated).day()
        return "\(first.formatted(style)) – \(last.formatted(style))"
    }
}
