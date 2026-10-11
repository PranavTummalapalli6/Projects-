import Charts
import PickleCore
import SwiftUI

/// Full facility page with progressive disclosure. Every section labels what kind of information it is.
struct FacilityDetailView: View {
    let rec: FacilityRecommendation
    var onReported: () -> Void = {}

    @Environment(AppEnvironment.self) private var env
    @State private var vm: FacilityDetailViewModel?
    @State private var showEdit = false
    @State private var showIssue = false
    @State private var showReport = false

    private var f: Facility { vm?.detail?.facility ?? rec.facility }

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.Spacing.l) {
                if case .failed(let message) = vm?.state {
                    WarningBanner(text: message, symbol: "wifi.exclamationmark", tint: Theme.unknown)
                }
                availability
                bestTimeSection
                playerFit
                accessSection
                playability
                facilitySection
                communitySection
                sourcesSection
            }
            .padding()
        }
        .background(Theme.groupedBackground)
        .navigationTitle(f.name)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if vm == nil { vm = FacilityDetailViewModel(rec: rec, env: env) }
            await vm?.load()
        }
        .refreshable { await vm?.load() }
        .sheet(isPresented: $showEdit) { SuggestEditSheet(facility: f) }
        .sheet(isPresented: $showIssue) { IssueReportSheet(facility: f) }
        .sheet(isPresented: $showReport) { QuickReportSheet(facility: f, onReported: onReported) }
    }

    // MARK: Sections

    private var availability: some View {
        Card(title: "Availability", symbol: "clock") {
            InfoRow(symbol: "hourglass", title: "Estimated wait", value: rec.prediction.wait.label)
            InfoRow(symbol: "square.grid.2x2", title: "Courts usable now",
                    value: "\(rec.prediction.usableCourts)" + (f.totalPhysicalCourts.map { " of \($0)" } ?? ""),
                    caption: courtSourceCaption)
            if let p = rec.prediction.paddleStack, f.playSystem.isRotation {
                InfoRow(symbol: Icons.paddle(p), title: "Paddle stack", value: p.displayName)
            }
            HStack {
                ConfidenceIndicator(level: rec.prediction.confidence)
                Spacer()
                Text(rec.prediction.basis.displayName).font(.footnote).foregroundStyle(.secondary)
            }
            ForEach(rec.prediction.explanation, id: \.self) { line in
                Label(line, systemImage: "info.circle").font(.footnote).foregroundStyle(.secondary)
            }
            if !rec.prediction.hasLiveData {
                Text(env.contributor.status.liveGatingEnabled && !env.contributor.status.hasLiveInsights
                     ? "Share a quick report from any court to unlock live insights for a week."
                     : "No recent reports — this is an estimate from usual patterns.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Button { showReport = true } label: { Label("Report status", systemImage: "hand.tap") }
                .buttonStyle(SecondaryButtonStyle())
        }
    }

    private var courtSourceCaption: String {
        switch rec.prediction.usableCourtsSource {
        case .reported: "Recently reported by players"
        case .configured: "Courts normally set up for pickleball"
        case .physical: "Physical courts — pickleball setup unconfirmed"
        case .assumed: "Court count unknown"
        }
    }

    @ViewBuilder private var bestTimeSection: some View {
        if let best = vm?.bestTime, !best.slots.isEmpty {
            Card(title: "Busy times today", symbol: "chart.bar.fill") {
                if let s = best.bestStart, let e = best.bestEnd {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Best time today").font(.subheadline).foregroundStyle(.secondary)
                        Text(Format.timeRange(s, e)).font(.title3.weight(.bold))
                    }
                    .accessibilityElement(children: .combine)
                }
                Chart(best.slots) { slot in
                    BarMark(x: .value("Time", slot.start, unit: .minute), y: .value("Busy", min(1.1, slot.occupancy)), width: .fixed(8))
                        .foregroundStyle(color(for: slot.level))
                        .accessibilityLabel(Format.time(slot.start))
                        .accessibilityValue(slot.level.displayName + (slot.note.map { ", \($0)" } ?? ""))
                }
                .chartYAxis(.hidden)
                .chartXAxis { AxisMarks(values: .stride(by: .hour, count: 2)) { _ in AxisValueLabel(format: .dateTime.hour()) } }
                .frame(height: 120)
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(summarySlots(best.slots)) { slot in
                        HStack {
                            Text(Format.time(slot.start)).monospacedDigit().frame(width: 80, alignment: .leading)
                            Text(slot.level.displayName).fontWeight(.semibold).foregroundStyle(color(for: slot.level))
                            if let note = slot.note { Text("· \(note)").foregroundStyle(.secondary) }
                            Spacer()
                        }
                        .font(.subheadline)
                    }
                }
                HStack(spacing: 6) {
                    InfoKindTag(kind: best.basedOnHistory ? .historical : .prediction)
                    Text(best.basedOnHistory ? "From this facility's usual pattern" : "General estimate — not enough history yet")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
        }
    }

    /// Hourly samples so the list stays short.
    private func summarySlots(_ slots: [TimeSlot]) -> [TimeSlot] {
        slots.enumerated().filter { $0.offset % 2 == 0 }.map(\.element).prefix(6).map { $0 }
    }

    private func color(for level: SlotLevel) -> Color {
        switch level {
        case .good: Theme.available
        case .moderate: Theme.moderate
        case .busy, .veryBusy: Theme.busy
        case .poorWeather: Theme.surfaceIssue
        case .unavailable: Theme.unknown
        }
    }

    private var playerFit: some View {
        Card(title: "Player fit", symbol: "figure.pickleball") {
            if let h = rec.fit.headline { Label(h, systemImage: "hand.thumbsup.fill").font(.headline).foregroundStyle(Theme.accent) }
            if let t = rec.fit.tradeoff { Label(t, systemImage: "arrow.left.arrow.right").font(.subheadline.weight(.semibold)) }
            if let s = f.skill, let label = s.typicalLabel {
                InfoRow(symbol: "chart.bar", title: "Typical play", value: label,
                        caption: "Based on \(s.observationCount) reports · \(s.confidence.displayName)")
                InfoKindTag(kind: .communityEstimate)
            } else {
                Text("Not enough reports about play level yet.").font(.subheadline).foregroundStyle(.secondary)
            }
            if !f.culture.isEmpty || !rec.fit.cultureNotes.isEmpty {
                FlowLayout(spacing: 8) {
                    ForEach(f.culture.filter { $0.share >= 0.3 }, id: \.tag) { c in
                        Pill(text: c.tag.displayName, symbol: Icons.culture(c.tag), tint: Theme.accent)
                    }
                    if f.courtType == .dedicatedPickleball { Pill(text: "Dedicated courts", symbol: "checkmark.seal", tint: .secondary) }
                }
            }
            if env.preferences.prefs.skill == .unknown {
                NavigationLink { SkillPickerView() } label: {
                    Label("Set your level for better matches", systemImage: "slider.horizontal.3").font(.subheadline.weight(.semibold))
                }
            }
        }
    }

    private var accessSection: some View {
        Card(title: "Access & cost", symbol: "person.badge.key") {
            InfoRow(symbol: Icons.access(f.access.accessType), title: f.access.accessType.displayName,
                    caption: f.access.accessNotes)
            InfoRow(symbol: Icons.cost(rec.costFit), title: costTitle, value: priceText,
                    caption: f.cost.pricingNotes ?? f.cost.lastVerifiedAt.map { "Price checked \($0.formatted(.relative(presentation: .named)))" })
            if f.access.reservationRequired == true { InfoRow(symbol: "calendar.badge.clock", title: "Reservation required") }
            else if f.access.reservationAvailable == true { InfoRow(symbol: "calendar", title: "Reservations available") }
            if f.access.permitRequired == true { InfoRow(symbol: "doc.text", title: "Permit required") }
            HStack(spacing: 6) {
                InfoKindTag(kind: f.access.verificationStatus == .verified ? .verifiedFact : .communityEstimate)
                Text("Access info: \(f.access.verificationStatus == .verified ? "verified" : "not yet verified")")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            if !f.access.accessType.isOpenToOrdinaryPlayers {
                Toggle(isOn: Binding(get: { env.preferences.prefs.accessGrantedFacilityIDs.contains(f.id) },
                                     set: { env.preferences.setAccessGranted(f.id, $0) })) {
                    Text("I'm a member / resident here").font(.subheadline.weight(.semibold))
                }
                .tint(Theme.accent)
            }
        }
    }

    private var costTitle: String {
        switch f.cost.costType {
        case .free: "Free"
        case .dayPass: "Day pass"
        case .reservationFee: "Reservation fee"
        case .membership: "Membership"
        case .paid: "Paid"
        case .unknown: "Cost unknown"
        }
    }

    private var priceText: String? {
        (f.cost.dayPassPrice ?? f.cost.reservationFee).map(Format.money)
    }

    @ViewBuilder private var playability: some View {
        if f.indoorOutdoor != .indoor || f.surface != nil {
            Card(title: "Playability", symbol: "sun.max") {
                if let s = f.surface {
                    InfoRow(symbol: Icons.surface(s.condition), title: "Surface", value: s.condition.displayName,
                            caption: "Reported \(Format.age(minutes: s.ageMinutes))")
                } else {
                    InfoRow(symbol: "questionmark.circle", title: "Surface", value: "No recent report")
                }
                if f.indoorOutdoor != .indoor {
                    InfoRow(symbol: Icons.wind(rec.weather.windCategory), title: "Wind",
                            value: "\(Int(rec.weather.effectiveWindMph.rounded())) mph", caption: rec.weather.windCategory.displayName)
                    if let headline = rec.weather.headline { WarningBanner(text: headline, symbol: "cloud.sun", tint: Theme.moderate) }
                    Text("Recent player reports outweigh forecasts.").font(.footnote).foregroundStyle(.secondary)
                }
            }
        }
    }

    private var facilitySection: some View {
        Card(title: "Facility", symbol: "building.2") {
            InfoRow(symbol: "rectangle.split.2x1", title: f.courtType.displayName,
                    value: f.totalPhysicalCourts.map { "\($0) courts" })
            InfoRow(symbol: f.indoorOutdoor == .indoor ? "building.2.fill" : "tree.fill", title: f.indoorOutdoor.rawValue.capitalized)
            InfoRow(symbol: "arrow.triangle.2.circlepath", title: "How play rotates", value: playSystemLabel)
            amenityRow("lightbulb.fill", "Lights", f.hasLights)
            amenityRow("toilet", "Restrooms", f.hasRestrooms)
            amenityRow("drop.fill", "Water", f.hasWater)
            amenityRow("car.fill", "Parking", f.hasParking)
            if !f.hours.isEmpty {
                DisclosureGroup("Hours") {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(Array(f.hours.enumerated()), id: \.offset) { _, h in
                            HStack {
                                Text(Calendar.current.weekdaySymbols[h.dayOfWeek]).frame(width: 110, alignment: .leading)
                                Text("\(h.opens)–\(h.closes)").monospacedDigit()
                            }
                            .font(.subheadline)
                        }
                    }
                    .padding(.top, 6)
                }
                .font(.subheadline.weight(.semibold))
            }
            if let rules = vm?.detail?.rules, !rules.isEmpty {
                DisclosureGroup("Rules & notes") {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(rules, id: \.self) { Text("• \($0.text)").font(.subheadline) }
                    }
                    .padding(.top, 6)
                }
                .font(.subheadline.weight(.semibold))
            }
        }
    }

    private var playSystemLabel: String {
        switch f.playSystem {
        case .paddleStack: "Paddle stack"
        case .rotationBoard: "Rotation board"
        case .stayUntilFinished: "Play until finished"
        case .reservationOnly: "Reservations"
        case .organizedOpenPlay: "Organized open play"
        case .unknown: "Unknown"
        }
    }

    @ViewBuilder
    private func amenityRow(_ symbol: String, _ title: String, _ value: Bool?) -> some View {
        if let value { InfoRow(symbol: symbol, title: title, value: value ? "Yes" : "No") }
    }

    private var communitySection: some View {
        Card(title: "Keep this accurate", symbol: "person.2") {
            if f.isCommunityReported {
                Text(vm?.confirmation == nil ? "Is this court here?" : "Thanks for confirming.")
                    .font(.headline)
                if vm?.confirmation == nil {
                    HStack(spacing: 10) {
                        Button { Task { await vm?.confirm(exists: true) } } label: { Label("Yes", systemImage: "checkmark") }
                            .buttonStyle(PrimaryButtonStyle(tint: Theme.available))
                        Button { Task { await vm?.confirm(exists: false) } } label: { Label("No", systemImage: "xmark") }
                            .buttonStyle(PrimaryButtonStyle(tint: Theme.unavailable))
                    }
                }
            }
            if let message = vm?.confirmMessage { Text(message).font(.footnote).foregroundStyle(.secondary) }
            Button { showEdit = true } label: { Label("Suggest an edit", systemImage: "pencil") }
                .buttonStyle(SecondaryButtonStyle())
            Button { showIssue = true } label: { Label("Report a problem", systemImage: "exclamationmark.triangle") }
                .buttonStyle(SecondaryButtonStyle())
        }
    }

    private var sourcesSection: some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: 8) {
                InfoRow(symbol: "checkmark.seal", title: "Facility exists", value: verificationLabel(f.existenceStatus))
                InfoRow(symbol: "person.badge.key", title: "Access rules", value: verificationLabel(f.access.verificationStatus))
                if let count = vm?.detail?.confirmationCount, count > 0 {
                    InfoRow(symbol: "person.2", title: "Player confirmations", value: "\(count)")
                }
                let sources = vm?.detail?.sources ?? [f.source].compactMap { $0 }
                if !sources.isEmpty {
                    Text("Sources: " + sources.map(sourceLabel).joined(separator: ", ")).font(.footnote).foregroundStyle(.secondary)
                }
                if sources.contains("osm") { Text("Map data © OpenStreetMap contributors").font(.caption).foregroundStyle(.secondary) }
            }
            .padding(.top, 8)
        } label: {
            Label("Data sources & verification", systemImage: "checkmark.shield").font(.headline)
        }
        .padding()
        .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: Theme.Radius.l))
    }

    private func verificationLabel(_ s: VerificationStatus) -> String {
        switch s {
        case .verified: "Verified"
        case .partiallyVerified: "Partly verified"
        case .communityReported: "Community-reported"
        case .pending: "Pending"
        case .rejected: "Rejected"
        case .closed: "Closed"
        }
    }

    private func sourceLabel(_ s: String) -> String {
        switch s {
        case "osm": "OpenStreetMap"
        case "community": "Player submission"
        case "demo": "Demo data"
        case "manual", "manual_seed": "Manually verified"
        default: s.hasPrefix("city:") ? "Local recreation dataset" : s
        }
    }
}

/// Simple wrapping layout for tags.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, maxX: CGFloat = 0
        for s in subviews {
            let size = s.sizeThatFits(.unspecified)
            if x + size.width > width, x > 0 { x = 0; y += rowHeight + spacing; rowHeight = 0 }
            x += size.width + spacing
            maxX = max(maxX, x - spacing)
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: maxX, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for s in subviews {
            let size = s.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX { x = bounds.minX; y += rowHeight + spacing; rowHeight = 0 }
            s.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
