//
//  PokerHealthView.swift
//  PokerChipApp
//
//  A lighthearted "how much poker have you played this week" dashboard,
//  reached from the result screen instead of going straight back to Start.
//  The chip graphic decays from a healthy gold chip toward a skeletal one as
//  the week's hours climb — purely for fun, not a real health metric.
//

import Charts
import SwiftUI

struct PokerHealthView: View {
    @EnvironmentObject private var coordinator: NavigationCoordinator
    @EnvironmentObject private var store: NightStore
    @AppStorage(PrefKey.weeklyHoursCap) private var weeklyHoursCap = AppPreferences.defaultWeeklyHoursCap

    var body: some View {
        ScrollView {
            VStack(spacing: Spacing.lg) {
                // Worked out from the nights on this phone, so it is there offline too.
                if store.phase == .loading {
                    loadingPlaceholder
                } else {
                    content(WeeklySummary.make(from: store.nights), trend: WeekTrend(nights: store.nights))
                }

                PokerButton(title: "Play again", systemImage: "arrow.counterclockwise") {
                    coordinator.popToRoot()
                    coordinator.tab = .play
                }
                .accessibilityIdentifier("health.playAgain")
            }
            .padding(.horizontal, Spacing.gutter)
            .padding(.vertical, Spacing.lg)
            .pokerReadableWidth()
        }
        .background(PokerBackground())
        .navigationTitle("Poker Health")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: States

    private var loadingPlaceholder: some View {
        VStack(spacing: Spacing.lg) {
            SkeletonView(cornerRadius: 80).frame(width: 160, height: 160)
            SkeletonView(cornerRadius: Radius.card).frame(height: 110)
            SkeletonView(cornerRadius: Radius.card).frame(height: 170)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Loading this week's playtime")
    }

    private func content(_ summary: WeeklySummary, trend: WeekTrend) -> some View {
        let hours = Double(summary.totalSeconds) / 3600
        let cap = max(weeklyHoursCap, 1)
        let decay = min(1, max(0, hours / cap))

        return VStack(spacing: Spacing.lg) {
            DecayingChipView(decay: decay)
                .frame(width: 160, height: 160)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Poker chip")
                .accessibilityValue(Self.wearDescription(decay))

            Text(Self.caption(decay))
                .font(.pokerCallout.weight(.semibold))
                .foregroundStyle(.pokerTextPrimary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, Spacing.lg)

            totalCard(summary, hours: hours, cap: cap, decay: decay)

            trendCard(trend, cap: cap)

            WeeklyBarChart(days: summary.days)
                .pokerCard()

            ShareCardButton(
                title: "Share my week",
                previewTitle: "My week at the table",
                key: "\(summary.totalSeconds)-\(trend.weeks)",
                card: WeeklyRecapCard(summary: summary, trend: trend)
            )
            .accessibilityIdentifier("health.shareWeek")
        }
    }

    /// This week against last, and the last four weeks beside the limit.
    private func trendCard(_ trend: WeekTrend, cap: Double) -> some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            SectionHeader(title: "Last four weeks")

            Text(trend.comparison)
                .font(.pokerCallout.weight(.semibold))
                .foregroundStyle(.pokerTextPrimary)
                .accessibilityIdentifier("health.comparison")

            Chart {
                ForEach(Array(trend.weeks.enumerated()), id: \.offset) { index, seconds in
                    let hours = Double(seconds) / 3_600
                    BarMark(x: .value("Week", WeekTrend.labels[min(index, WeekTrend.labels.count - 1)]), y: .value("Hours", hours))
                        .foregroundStyle(hours > cap ? Color.pokerWarning : Color.pokerGold)
                        .cornerRadius(4)
                }
                RuleMark(y: .value("Your limit", cap))
                    .foregroundStyle(Color.pokerPurpleLight.opacity(0.8))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    .annotation(position: .top, alignment: .trailing) {
                        Text("Your limit").font(.caption2).foregroundStyle(Color.pokerPurpleLight)
                    }
            }
            .chartYAxis {
                AxisMarks(position: .leading) { value in
                    AxisGridLine().foregroundStyle(Color.white.opacity(0.08))
                    AxisValueLabel {
                        if let hours = value.as(Double.self) { Text("\(Int(hours))h").foregroundStyle(Color.pokerTextSecondary) }
                    }
                }
            }
            .chartXAxis {
                AxisMarks { _ in AxisValueLabel().foregroundStyle(Color.pokerTextSecondary) }
            }
            .frame(height: 150)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Hours played in each of the last four weeks")
            .accessibilityValue(zip(WeekTrend.labels, trend.weeks).map { "\($0): \(DurationFormat.spoken($1))" }.joined(separator: ". ") + ". Your limit is \(Int(cap)) hours a week.")
            .accessibilityIdentifier("health.trend")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .pokerCard()
    }

    private func totalCard(_ summary: WeeklySummary, hours: Double, cap: Double, decay: Double) -> some View {
        VStack(spacing: Spacing.md) {
            Text("This week")
                .font(.pokerCaption)
                .textCase(.uppercase)
                .tracking(0.8)
                .foregroundStyle(Color.pokerPurpleLight)

            DurationText(
                seconds: summary.totalSeconds,
                font: .system(.largeTitle, design: .rounded).weight(.heavy).monospacedDigit(),
                color: .pokerGoldLight
            )

            ProgressBar(fraction: decay)

            Text("\(Int((decay * 100).rounded()))% of your \(Int(cap))\u{2011}hour limit")
                .font(.pokerFootnote)
                .foregroundStyle(.pokerTextSecondary)
        }
        .frame(maxWidth: .infinity)
        .pokerCard()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("This week")
        .accessibilityValue("\(DurationFormat.spoken(summary.totalSeconds)) played, \(Int((decay * 100).rounded())) percent of your \(Int(cap)) hour limit")
        .accessibilityIdentifier("health.total")
    }

    // MARK: Words

    private static func caption(_ decay: Double) -> String {
        switch decay {
        case ..<0.15: return "Chip's looking sharp. Nice and balanced this week."
        case 0.15..<0.4: return "A little wear showing. Maybe pace yourself."
        case 0.4..<0.7: return "Getting worn down — consider a break soon."
        default: return "Fully worn out. Time to step away from the felt for a bit."
        }
    }

    private static func wearDescription(_ decay: Double) -> String {
        switch decay {
        case ..<0.15: return "Like new"
        case 0.15..<0.4: return "A little worn"
        case 0.4..<0.7: return "Badly worn, with cracks"
        default: return "Fully worn, showing a skull"
        }
    }
}

/// A thin capsule showing how much of a limit has been used.
private struct ProgressBar: View {
    let fraction: Double

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.12))
                Capsule()
                    .fill(LinearGradient(colors: [.pokerGoldLight, .pokerGold], startPoint: .leading, endPoint: .trailing))
                    .frame(width: max(8, geometry.size.width * CGFloat(min(1, max(0, fraction)))))
            }
        }
        .frame(height: 8)
        .accessibilityHidden(true)
    }
}

/// Simple 7-bar chart of daily playtime, oldest day on the left.
private struct WeeklyBarChart: View {
    let days: [WeeklySummary.DaySummary]

    private static let parser: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    private static let weekday: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE"
        return formatter
    }()

    private let barAreaHeight: CGFloat = 96

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var maxSeconds: Int {
        max(days.map(\.seconds).max() ?? 0, 1)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            SectionHeader(title: "Daily breakdown")

            if dynamicTypeSize.isAccessibilitySize {
                rows
            } else {
                columns
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Daily playtime for the last seven days")
        .accessibilityValue(spokenSummary)
    }

    /// At accessibility text sizes seven columns can't hold their labels, so
    /// each day becomes a row: weekday, bar, time.
    private var rows: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            ForEach(Array(days.enumerated()), id: \.element.date) { index, day in
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    HStack {
                        Text(Self.weekdayLabel(for: day.date))
                            .font(.pokerHeadline)
                            .foregroundStyle(index == days.count - 1 ? Color.pokerGoldLight : Color.pokerTextPrimary)
                        Spacer(minLength: Spacing.sm)
                        Text(day.seconds > 0 ? DurationFormat.compact(day.seconds) : "—")
                            .font(.pokerNumeric(.body))
                            .foregroundStyle(.pokerTextSecondary)
                    }
                    GeometryReader { geometry in
                        Capsule()
                            .fill(LinearGradient(colors: [.pokerGoldLight, .pokerGold], startPoint: .leading, endPoint: .trailing))
                            .opacity(day.seconds > 0 ? 1 : 0.15)
                            .frame(width: max(8, geometry.size.width * CGFloat(day.seconds) / CGFloat(maxSeconds)))
                    }
                    .frame(height: 8)
                }
            }
        }
    }

    private var columns: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            HStack(alignment: .bottom, spacing: Spacing.sm) {
                ForEach(Array(days.enumerated()), id: \.element.date) { index, day in
                    VStack(spacing: Spacing.xs) {
                        Text(day.seconds > 0 ? Self.shortDuration(day.seconds) : "")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.pokerTextSecondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)

                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [.pokerGoldLight, .pokerGold],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                            .opacity(day.seconds > 0 ? 1 : 0.15)
                            .frame(height: max(4, barAreaHeight * CGFloat(day.seconds) / CGFloat(maxSeconds)))

                        Text(Self.weekdayLabel(for: day.date))
                            .font(.caption2.weight(index == days.count - 1 ? .bold : .semibold))
                            .foregroundStyle(index == days.count - 1 ? Color.pokerGoldLight : Color.pokerTextSecondary)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .frame(minHeight: barAreaHeight + 40, alignment: .bottom)
        }
    }

    private var spokenSummary: String {
        days.map { day in
            let played = day.seconds > 0 ? DurationFormat.spoken(day.seconds) : "none"
            return "\(Self.weekdayLabel(for: day.date)) \(played)"
        }
        .joined(separator: ", ")
    }

    /// "45m" under an hour, "1.5h" from an hour — short enough to sit above a bar.
    private static func shortDuration(_ seconds: Int) -> String {
        if seconds < 3600 { return "\(max(1, seconds / 60))m" }
        let hours = Double(seconds) / 3600
        return String(format: "%.1fh", hours)
    }

    private static func weekdayLabel(for isoDate: String) -> String {
        guard let date = parser.date(from: isoDate) else { return "—" }
        return weekday.string(from: date)
    }
}

/// A poker chip that erodes from a healthy gold disc into a cracked,
/// skull-faced skeletal chip as `decay` (0...1) increases. Drawn entirely
/// with Canvas/Shapes rather than image assets, so it can interpolate
/// smoothly with any decay value instead of jumping between fixed states.
struct DecayingChipView: View {
    var decay: Double

    private var clampedDecay: Double { min(1, max(0, decay)) }

    var body: some View {
        Canvas { context, size in
            let rect = CGRect(origin: .zero, size: size)
            let center = CGPoint(x: rect.midX, y: rect.midY)
            let radius = min(size.width, size.height) / 2 * 0.92

            let discPath = erodedDiscPath(center: center, radius: radius, decay: clampedDecay)

            context.fill(
                discPath,
                with: .linearGradient(
                    Gradient(colors: [diskColor(top: true), diskColor(top: false)]),
                    startPoint: CGPoint(x: rect.midX, y: rect.minY),
                    endPoint: CGPoint(x: rect.midX, y: rect.maxY)
                )
            )
            context.stroke(discPath, with: .color(.white.opacity(0.25)), lineWidth: 1.5)

            drawEdgeStripes(context: context, center: center, radius: radius)
            drawInnerRing(context: context, center: center, radius: radius)

            if clampedDecay > 0.05 {
                drawCracks(context: context, center: center, radius: radius, decay: clampedDecay)
            }

            let skullOpacity = smoothstep(clampedDecay, 0.35, 1.0)
            if skullOpacity > 0.01 {
                drawSkull(context: context, center: center, radius: radius, opacity: skullOpacity)
            }
        }
        .drawingGroup()
        .animation(.easeOut(duration: 0.4), value: decay)
    }

    // MARK: - Geometry

    /// The disc's outline, perturbed by two sine harmonics whose amplitude
    /// scales with decay — an organic, "chipped and worn" rim instead of a
    /// perfect circle, without needing true randomness.
    private func erodedDiscPath(center: CGPoint, radius: CGFloat, decay: Double) -> Path {
        var path = Path()
        let amplitude = radius * CGFloat(decay) * 0.14
        let steps = 120
        for i in 0...steps {
            let theta = Double(i) / Double(steps) * 2 * .pi
            let erosion = 0.5 * sin(3 * theta) + 0.35 * sin(7 * theta + 1.3) + 0.25 * sin(11 * theta + 2.7)
            let r = radius - amplitude * CGFloat(erosion)
            let point = CGPoint(x: center.x + r * CGFloat(cos(theta)), y: center.y + r * CGFloat(sin(theta)))
            if i == 0 {
                path.move(to: point)
            } else {
                path.addLine(to: point)
            }
        }
        path.closeSubpath()
        return path
    }

    private func diskColor(top: Bool) -> Color {
        let healthy: (Double, Double, Double) = top ? (0.96, 0.84, 0.56) : (0.85, 0.68, 0.32)
        let skeletal: (Double, Double, Double) = top ? (0.72, 0.70, 0.66) : (0.46, 0.44, 0.42)
        let t = clampedDecay
        return Color(
            red: healthy.0 + (skeletal.0 - healthy.0) * t,
            green: healthy.1 + (skeletal.1 - healthy.1) * t,
            blue: healthy.2 + (skeletal.2 - healthy.2) * t
        )
    }

    private func drawEdgeStripes(context: GraphicsContext, center: CGPoint, radius: CGFloat) {
        let stripeCount = 8
        for i in 0..<stripeCount {
            // Every other stripe fades out early as decay climbs, so the rim
            // visibly loses pieces rather than just changing color.
            let stripeDecayThreshold = i.isMultiple(of: 2) ? 0.65 : 0.9
            guard clampedDecay < stripeDecayThreshold else { continue }

            let theta = Double(i) / Double(stripeCount) * 2 * .pi
            let inner = CGPoint(x: center.x + (radius * 0.82) * CGFloat(cos(theta)), y: center.y + (radius * 0.82) * CGFloat(sin(theta)))
            let outer = CGPoint(x: center.x + (radius * 0.96) * CGFloat(cos(theta)), y: center.y + (radius * 0.96) * CGFloat(sin(theta)))

            var stripe = Path()
            stripe.move(to: inner)
            stripe.addLine(to: outer)
            context.stroke(stripe, with: .color(.white.opacity(0.5)), lineWidth: 3)
        }
    }

    private func drawInnerRing(context: GraphicsContext, center: CGPoint, radius: CGFloat) {
        let ring = Path(ellipseIn: CGRect(
            x: center.x - radius * 0.62, y: center.y - radius * 0.62,
            width: radius * 1.24, height: radius * 1.24
        ))
        context.stroke(ring, with: .color(.white.opacity(0.22)), lineWidth: 1)
    }

    private func drawCracks(context: GraphicsContext, center: CGPoint, radius: CGFloat, decay: Double) {
        let crackAngles: [Double] = [0.4, 1.7, 2.9, 4.1, 5.0, 5.8]
        let visibleCracks = Int((decay * Double(crackAngles.count)).rounded(.up))

        for i in 0..<visibleCracks {
            let theta = crackAngles[i]
            var crack = Path()
            var point = center
            crack.move(to: point)
            let segments = 3
            for s in 1...segments {
                let jitter = sin(theta * Double(s) * 2.1) * 0.25
                let t = Double(s) / Double(segments)
                let r = radius * CGFloat(t) * (0.55 + CGFloat(decay) * 0.4)
                let angle = theta + jitter
                point = CGPoint(x: center.x + r * CGFloat(cos(angle)), y: center.y + r * CGFloat(sin(angle)))
                crack.addLine(to: point)
            }
            context.stroke(crack, with: .color(.black.opacity(0.35 + 0.25 * decay)), lineWidth: 1.2)
        }
    }

    private func drawSkull(context: GraphicsContext, center: CGPoint, radius: CGFloat, opacity: Double) {
        let skullColor = Color.black.opacity(0.55 * opacity)

        // Eye sockets
        for dx in [-0.28, 0.28] {
            let eye = Path(ellipseIn: CGRect(
                x: center.x + radius * CGFloat(dx) - radius * 0.16,
                y: center.y - radius * 0.12 - radius * 0.16,
                width: radius * 0.32, height: radius * 0.34
            ))
            context.fill(eye, with: .color(skullColor))
        }

        // Nasal cavity
        var nose = Path()
        nose.move(to: CGPoint(x: center.x, y: center.y + radius * 0.06))
        nose.addLine(to: CGPoint(x: center.x - radius * 0.09, y: center.y + radius * 0.26))
        nose.addLine(to: CGPoint(x: center.x + radius * 0.09, y: center.y + radius * 0.26))
        nose.closeSubpath()
        context.fill(nose, with: .color(skullColor))

        // Jaw / teeth line
        var jaw = Path()
        let jawY = center.y + radius * 0.42
        jaw.move(to: CGPoint(x: center.x - radius * 0.34, y: jawY))
        jaw.addLine(to: CGPoint(x: center.x + radius * 0.34, y: jawY))
        context.stroke(jaw, with: .color(skullColor), lineWidth: 1.5)

        for i in -3...3 {
            let x = center.x + radius * 0.34 * CGFloat(i) / 3.5
            var tooth = Path()
            tooth.move(to: CGPoint(x: x, y: jawY))
            tooth.addLine(to: CGPoint(x: x, y: jawY + radius * 0.1))
            context.stroke(tooth, with: .color(skullColor), lineWidth: 1)
        }
    }

    private func smoothstep(_ x: Double, _ edge0: Double, _ edge1: Double) -> Double {
        let t = min(1, max(0, (x - edge0) / (edge1 - edge0)))
        return t * t * (3 - 2 * t)
    }
}

struct PokerHealthView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationStack {
            PokerHealthView()
                .environmentObject(NavigationCoordinator())
                .environmentObject(NightStore(repository: MemoryNightRepository()))
        }
        .preferredColorScheme(.dark)
    }
}

struct DecayingChipView_Previews: PreviewProvider {
    static var previews: some View {
        HStack(spacing: 20) {
            ForEach([0.0, 0.35, 0.7, 1.0], id: \.self) { decay in
                DecayingChipView(decay: decay)
                    .frame(width: 100, height: 100)
            }
        }
        .padding()
        .background(PokerBackground())
        .previewLayout(.sizeThatFits)
    }
}
