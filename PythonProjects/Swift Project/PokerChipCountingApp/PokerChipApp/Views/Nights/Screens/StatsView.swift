//
//  StatsView.swift
//  PokerChipApp
//
//  How the nights add up: net, time, win rate, streaks, a bankroll curve and net
//  by month, and breakdowns by place, day and stake. Every figure comes from
//  `StatsEngine` — the screen only lays them out — so it works offline and
//  agrees with History. Small samples are labelled as such rather than dressed
//  up: an hourly rate needs ten nights before it means anything.
//

import Charts
import SwiftUI
import UIKit

struct StatsView: View {
    @EnvironmentObject private var store: NightStore
    @EnvironmentObject private var coordinator: NavigationCoordinator
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    @State private var exportFile: ExportFile?
    @State private var exportError: String?

    private struct ExportFile: Identifiable {
        let url: URL
        var id: URL { url }
    }

    private struct MonthBar: Identifiable {
        let date: Date
        let month: StatsReport.MonthTotal
        var id: Int { month.id }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: Spacing.lg) {
                StoreProblemBanners()

                if store.phase == .loading {
                    loading
                } else {
                    let report = StatsEngine.report(for: store.nights)
                    if report.isEmpty {
                        empty
                    } else {
                        content(report)
                    }
                    exportCard
                    pokerHealthLink
                }
            }
            .padding(.horizontal, Spacing.gutter)
            .padding(.vertical, Spacing.lg)
            .pokerReadableWidth()
        }
        .background(PokerBackground())
        .navigationTitle("Stats")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $exportFile) { file in
            ActivityView(items: [file.url])
                .presentationDetents([.medium, .large])
        }
    }

    // MARK: States

    private var loading: some View {
        VStack(spacing: Spacing.lg) {
            HStack(spacing: Spacing.md) {
                SkeletonView(cornerRadius: Radius.card).frame(height: 76)
                SkeletonView(cornerRadius: Radius.card).frame(height: 76)
            }
            SkeletonView(cornerRadius: Radius.card).frame(height: 240)
            SkeletonView(cornerRadius: Radius.card).frame(height: 200)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Loading your stats")
    }

    private var empty: some View {
        EmptyState(
            icon: "chart.line.uptrend.xyaxis",
            title: "No results yet",
            message: store.openNight == nil
                ? "Close your first night — cash everyone out and settle up — and your results, streaks and trends appear here."
                : "Finish the night in progress — cash everyone out and settle up — and your results, streaks and trends appear here.",
            actionTitle: store.openNight == nil ? "Start a night" : "Back to the night"
        ) {
            if let open = store.openNight {
                coordinator.open(night: open.id)
            } else if coordinator.path.isEmpty {
                coordinator.push(.buyIn(nil))
            }
            coordinator.tab = .play
        }
        .accessibilityIdentifier("stats.empty")
    }

    // MARK: Content

    private func content(_ report: StatsReport) -> some View {
        VStack(spacing: Spacing.lg) {
            summaryTiles(report)

            if !report.hasEnoughForPerHour {
                InlineBanner(
                    kind: .info,
                    message: "An hourly rate needs at least \(StatsReport.minimumNightsForPerHour) nights to mean much — you have \(report.nights). Until then it's mostly luck, so it's left out."
                )
                .accessibilityIdentifier("stats.perHourCaveat")
            }

            bankrollCard(report)
            monthlyCard(report)
            streaksCard(report)
            breakdown("By place", report.byLocation, currency: report.currency, identifier: "stats.byPlace")
            breakdown("By day of the week", report.byWeekday, currency: report.currency, identifier: "stats.byDay")
            if report.byStake.count > 1 {
                breakdown("By stake", report.byStake, currency: report.currency, identifier: "stats.byStake")
            }
        }
    }

    private func summaryTiles(_ report: StatsReport) -> some View {
        let columns = dynamicTypeSize.isAccessibilitySize
            ? [GridItem(.flexible())]
            : [GridItem(.adaptive(minimum: 150), spacing: Spacing.md)]
        return LazyVGrid(columns: columns, spacing: Spacing.md) {
            StatTile(
                label: "Net",
                value: Money.formatSigned(cents: report.totalNetMinor, currencyCode: report.currency),
                valueColor: tone(report.totalNetMinor),
                spokenValue: spoken(report.totalNetMinor, currency: report.currency)
            )
            .accessibilityIdentifier("stats.net")
            StatTile(label: "Nights", value: "\(report.nights)")
            StatTile(
                label: "Win rate",
                value: report.winRate.map { "\(Int(($0 * 100).rounded()))%" } ?? "—",
                spokenValue: report.winRate.map { "\(Int(($0 * 100).rounded())) percent" } ?? "none yet"
            )
            StatTile(
                label: "Per hour",
                value: report.perHourMinor.map { Money.formatSigned(cents: $0, currencyCode: report.currency) } ?? "—",
                valueColor: report.perHourMinor.map(tone) ?? .pokerTextSecondary,
                spokenValue: report.perHourMinor.map { spoken($0, currency: report.currency) } ?? "not enough nights yet"
            )
            .accessibilityIdentifier("stats.perHour")
            StatTile(
                label: "Average buy-in",
                value: report.averageBuyInMinor.map { Money.format(cents: $0, currencyCode: report.currency) } ?? "—"
            )
            StatTile(
                label: "Time played",
                value: DurationFormat.compact(report.totalSeconds),
                spokenValue: DurationFormat.spoken(report.totalSeconds)
            )
        }
    }

    // MARK: Charts

    private func bankrollCard(_ report: StatsReport) -> some View {
        let points = report.bankroll
        let values = points.map { Double($0.cumulativeMinor) / 100 }
        return VStack(alignment: .leading, spacing: Spacing.md) {
            SectionHeader(title: "Bankroll")

            Chart {
                ForEach(points) { point in
                    AreaMark(x: .value("Night", point.date), y: .value("Net", Double(point.cumulativeMinor) / 100))
                        .foregroundStyle(LinearGradient(colors: [Color.pokerGold.opacity(0.32), Color.pokerGold.opacity(0)], startPoint: .top, endPoint: .bottom))
                        .interpolationMethod(.monotone)
                    LineMark(x: .value("Night", point.date), y: .value("Net", Double(point.cumulativeMinor) / 100))
                        .foregroundStyle(Color.pokerGoldLight)
                        .interpolationMethod(.monotone)
                        .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                    PointMark(x: .value("Night", point.date), y: .value("Net", Double(point.cumulativeMinor) / 100))
                        .foregroundStyle(point.cumulativeMinor >= 0 ? Color.pokerPositive : Color.pokerNegative)
                        .symbolSize(points.count > 20 ? 14 : 36)
                }
                RuleMark(y: .value("Break-even", 0))
                    .foregroundStyle(Color.white.opacity(0.30))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
            }
            .chartYAxis {
                AxisMarks(position: .leading) { value in
                    AxisGridLine().foregroundStyle(Color.white.opacity(0.08))
                    AxisValueLabel {
                        if let amount = value.as(Double.self) {
                            Text(Money.compact(amount, currencyCode: report.currency)).foregroundStyle(Color.pokerTextSecondary)
                        }
                    }
                }
            }
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                    AxisValueLabel(format: .dateTime.month(.abbreviated).day()).foregroundStyle(Color.pokerTextSecondary)
                }
            }
            .frame(height: 200)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Bankroll over \(report.nights) nights")
            .accessibilityValue(bankrollSpoken(report, low: values.min() ?? 0, high: values.max() ?? 0))
            .accessibilityIdentifier("stats.bankroll")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .pokerCard()
    }

    private func bankrollSpoken(_ report: StatsReport, low: Double, high: Double) -> String {
        let currency = report.currency
        return "Now \(spoken(report.totalNetMinor, currency: currency)). Highest \(Money.spoken(cents: Int((high * 100).rounded()), currencyCode: currency)), lowest \(Money.spoken(cents: Int((low * 100).rounded()), currencyCode: currency))."
    }

    private func monthlyCard(_ report: StatsReport) -> some View {
        let calendar = Calendar.current
        let months: [MonthBar] = report.byMonth.compactMap { month in
            calendar.date(from: DateComponents(year: month.year, month: month.month, day: 1)).map { MonthBar(date: $0, month: month) }
        }
        return VStack(alignment: .leading, spacing: Spacing.md) {
            SectionHeader(title: "Net by month")

            Chart {
                ForEach(months) { entry in
                    BarMark(x: .value("Month", entry.date, unit: .month), y: .value("Net", Double(entry.month.netMinor) / 100))
                        .foregroundStyle(entry.month.netMinor >= 0 ? Color.pokerPositive : Color.pokerNegative)
                        .cornerRadius(4)
                }
                RuleMark(y: .value("Break-even", 0)).foregroundStyle(Color.white.opacity(0.30))
            }
            .chartYAxis {
                AxisMarks(position: .leading) { value in
                    AxisGridLine().foregroundStyle(Color.white.opacity(0.08))
                    AxisValueLabel {
                        if let amount = value.as(Double.self) {
                            Text(Money.compact(amount, currencyCode: report.currency)).foregroundStyle(Color.pokerTextSecondary)
                        }
                    }
                }
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: .month)) { _ in
                    AxisValueLabel(format: .dateTime.month(.narrow)).foregroundStyle(Color.pokerTextSecondary)
                }
            }
            .frame(height: 160)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Net by month")
            .accessibilityValue(report.byMonth.map { month in
                let name = calendar.date(from: DateComponents(year: month.year, month: month.month, day: 1))
                    .map { $0.formatted(.dateTime.month(.wide).year()) } ?? ""
                return "\(name): \(spoken(month.netMinor, currency: report.currency))"
            }.joined(separator: ". "))
            .accessibilityIdentifier("stats.monthly")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .pokerCard()
    }

    // MARK: Streaks, best and worst

    private func streaksCard(_ report: StatsReport) -> some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            SectionHeader(title: "Streaks and extremes")

            infoRow("Current streak", streakText(report.currentStreak))
            infoRow("Longest winning streak", report.longestWinStreak == 0 ? "—" : "\(report.longestWinStreak) night\(report.longestWinStreak == 1 ? "" : "s")")
            infoRow("Longest losing streak", report.longestLossStreak == 0 ? "—" : "\(report.longestLossStreak) night\(report.longestLossStreak == 1 ? "" : "s")")
            if let best = report.best, let worst = report.worst {
                Divider().overlay(Color.white.opacity(0.12))
                nightRow("Best night", best, currency: report.currency)
                nightRow("Worst night", worst, currency: report.currency)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .pokerCard()
        .accessibilityIdentifier("stats.streaks")
    }

    private func streakText(_ streak: Int) -> String {
        switch streak {
        case 0: return "—"
        case 1...: return "\(streak) win\(streak == 1 ? "" : "s") in a row"
        default: return "\(-streak) loss\(streak == -1 ? "" : "es") in a row"
        }
    }

    private func infoRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label).foregroundStyle(.pokerTextSecondary)
            Spacer(minLength: Spacing.sm)
            Text(value).font(.pokerNumeric(.callout)).foregroundStyle(.pokerTextPrimary).multilineTextAlignment(.trailing)
        }
        .font(.pokerCallout)
        .accessibilityElement(children: .combine)
    }

    private func nightRow(_ label: String, _ night: PlayedNight, currency: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(label).foregroundStyle(.pokerTextSecondary).font(.pokerCallout)
                Text(night.startedAt.formatted(.dateTime.month(.abbreviated).day().year()) + (night.location.map { " · \($0)" } ?? ""))
                    .font(.pokerFootnote).foregroundStyle(.pokerTextTertiary)
            }
            Spacer(minLength: Spacing.sm)
            MoneyText(cents: night.netMinor, signed: true, font: .pokerNumeric(.callout), color: tone(night.netMinor))
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: Breakdowns

    private func breakdown(_ title: String, _ rows: [StatsReport.Breakdown], currency: String, identifier: String) -> some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            SectionHeader(title: title)
            ForEach(rows) { row in
                HStack(alignment: .firstTextBaseline, spacing: Spacing.md) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(row.label).font(.pokerCallout).foregroundStyle(.pokerTextPrimary)
                        Text("\(row.nights) night\(row.nights == 1 ? "" : "s") · \(DurationFormat.compact(row.seconds))")
                            .font(.pokerFootnote)
                            .foregroundStyle(.pokerTextSecondary)
                    }
                    Spacer(minLength: Spacing.sm)
                    MoneyText(cents: row.netMinor, signed: true, font: .pokerNumeric(.callout), color: tone(row.netMinor))
                }
                .frame(minHeight: Spacing.minTapTarget)
                .accessibilityElement(children: .combine)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .pokerCard()
        .accessibilityIdentifier(identifier)
    }

    // MARK: Export and links

    private var exportCard: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            SectionHeader(title: "Your records")
            Text("Export every night as a spreadsheet — one row per player per night. For your own records, not tax advice.")
                .font(.pokerFootnote)
                .foregroundStyle(.pokerTextSecondary)
            if let exportError {
                InlineBanner(kind: .error, message: exportError)
            }
            PokerButton(title: "Export CSV", systemImage: "square.and.arrow.up", kind: .secondary, isEnabled: !store.nights.isEmpty, action: export)
                .accessibilityIdentifier("stats.export")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .pokerCard()
    }

    private func export() {
        exportError = nil
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(NightCSV.fileName())
        do {
            try NightCSV.text(for: store.nights).write(to: url, atomically: true, encoding: .utf8)
            exportFile = ExportFile(url: url)
        } catch {
            exportError = "Couldn't make the file. Free up some space on this iPhone and try again."
        }
    }

    private var pokerHealthLink: some View {
        NavigationLink {
            PokerHealthView()
        } label: {
            ListRow(icon: "heart.text.square", title: "Poker Health", subtitle: "This week's playtime and how it compares")
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("stats.health")
    }

    // MARK: Helpers

    private func tone(_ cents: Int) -> Color {
        cents == 0 ? .pokerTextPrimary : (cents > 0 ? .pokerPositive : .pokerNegative)
    }

    private func spoken(_ cents: Int, currency: String) -> String {
        cents == 0 ? "even" : "\(cents > 0 ? "up" : "down") \(Money.spoken(cents: abs(cents), currencyCode: currency))"
    }
}

/// The system share sheet, for a file made at the moment it's asked for.
struct ActivityView: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
