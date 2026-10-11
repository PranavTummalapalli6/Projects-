import MapKit
import PickleCore
import SwiftUI

/// Draggable sheet shown when a marker is tapped. Ordered by what decides "should I go?".
struct FacilitySheet: View {
    let rec: FacilityRecommendation
    var onReported: () -> Void = {}

    @Environment(AppEnvironment.self) private var env
    @State private var showReport = false
    @State private var showDetail = false

    private var f: Facility { rec.facility }
    private var status: FacilityStatus { FacilityStatus(rec) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.l) {
                header
                if rec.eligibility.status != .eligible, let reason = rec.eligibility.reason {
                    WarningBanner(text: reason,
                                  symbol: rec.eligibility.status == .restricted ? "lock.fill" : status.symbol,
                                  tint: status.color)
                }
                ForEach(rec.warnings.filter { $0 != rec.eligibility.reason }, id: \.self) { w in
                    WarningBanner(text: w, tint: Theme.moderate)
                }
                if f.isCommunityReported {
                    WarningBanner(text: "Community-reported court · Verification pending", symbol: "person.2.fill", tint: Theme.restricted)
                }
                fitBlock
                availabilityBlock
                conditionsBlock
                accessBlock
                actions
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 32)
        }
        .scrollBounceBehavior(.basedOnSize)
        .navigationDestination(isPresented: $showDetail) { FacilityDetailView(rec: rec, onReported: onReported) }
        .sheet(isPresented: $showReport) { QuickReportSheet(facility: f, onReported: onReported) }
        .onAppear { env.log("facility_open", facilityID: f.id) }
        .accessibilityIdentifier("facilitySheet")
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !rec.badges.isEmpty {
                Text(rec.badges.map(\.displayName).joined(separator: " · "))
                    .font(.caption.weight(.heavy)).tracking(0.6).foregroundStyle(Theme.accent)
            }
            HStack(alignment: .top) {
                Text(f.name).font(.title2.weight(.bold)).fixedSize(horizontal: false, vertical: true)
                Spacer()
                Button {
                    env.preferences.toggleSaved(f.id)
                    Haptics.tap()
                } label: {
                    Image(systemName: env.preferences.savedFacilityIDs.contains(f.id) ? "bookmark.fill" : "bookmark")
                        .font(.title3).frame(width: 44, height: 44)
                }
                .accessibilityLabel(env.preferences.savedFacilityIDs.contains(f.id) ? "Remove from saved" : "Save court")
                ShareLink(item: shareURL, subject: Text(f.name), message: Text("Pickleball at \(f.name)")) {
                    Image(systemName: "square.and.arrow.up").font(.title3).frame(width: 44, height: 44)
                }
                .accessibilityLabel("Share")
            }
            HStack(spacing: 8) {
                StatusChip(status: status)
                if let travel = Format.travel(rec.travel) {
                    Pill(text: travel, symbol: "car.fill", tint: .secondary)
                }
            }
        }
    }

    @ViewBuilder private var fitBlock: some View {
        if rec.fit.headline != nil || rec.fit.tradeoff != nil || rec.fit.skillEvidence != nil {
            VStack(alignment: .leading, spacing: 4) {
                if let h = rec.fit.headline { Label(h, systemImage: "hand.thumbsup.fill").font(.headline).foregroundStyle(Theme.accent) }
                if let t = rec.fit.tradeoff { Label(t, systemImage: "arrow.left.arrow.right").font(.subheadline.weight(.semibold)) }
                if let label = f.skill?.typicalLabel {
                    HStack(spacing: 6) {
                        Text("Typical play: \(label)").font(.subheadline)
                        InfoKindTag(kind: .communityEstimate)
                    }
                    .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var availabilityBlock: some View {
        Card(fill: Theme.raisedFill) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(rec.eligibility.status == .unavailable ? "—" : rec.prediction.wait.label)
                        .font(.title.weight(.bold)).monospacedDigit()
                    Text("estimated wait").font(.footnote).foregroundStyle(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    Text(courtsLine).font(.headline).monospacedDigit()
                    Text("courts usable").font(.footnote).foregroundStyle(.secondary)
                }
            }
            .accessibilityElement(children: .combine)
            HStack {
                ConfidenceIndicator(level: rec.prediction.confidence)
                Spacer()
                if let age = rec.prediction.newestLiveAgeMinutes {
                    HStack(spacing: 4) {
                        InfoKindTag(kind: .live)
                        Text("Updated \(Format.age(minutes: age))").font(.footnote).foregroundStyle(.secondary)
                    }
                } else {
                    InfoKindTag(kind: rec.prediction.basis == .historical ? .historical : .prediction)
                }
            }
            if let paddle = rec.prediction.paddleStack, f.playSystem.isRotation {
                InfoRow(symbol: Icons.paddle(paddle), title: "Paddle stack", value: paddle.displayName)
            }
        }
    }

    private var courtsLine: String {
        let usable = rec.prediction.usableCourts
        if let total = f.totalPhysicalCourts, total != usable { return "\(usable) / \(total)" }
        return rec.prediction.usableCourtsSource == .assumed ? "?" : "\(usable)"
    }

    @ViewBuilder private var conditionsBlock: some View {
        let showSurface = f.surface != nil
        let showWeather = f.indoorOutdoor != .indoor && rec.weather.effectiveWindMph > 0
        if showSurface || showWeather {
            HStack(spacing: 10) {
                if let s = f.surface {
                    Pill(text: "\(s.condition.displayName) · \(Format.age(minutes: s.ageMinutes))", symbol: Icons.surface(s.condition),
                         tint: s.condition.isUnplayable ? Theme.surfaceIssue : Theme.available)
                }
                if showWeather {
                    Pill(text: "Wind \(Int(rec.weather.effectiveWindMph.rounded())) mph · \(rec.weather.windCategory.displayName)",
                         symbol: Icons.wind(rec.weather.windCategory),
                         tint: rec.weather.windCategory == .veryWindy || rec.weather.windCategory == .windy ? Theme.moderate : .secondary)
                }
            }
        } else if f.indoorOutdoor == .indoor {
            Pill(text: "Indoor — weather-proof", symbol: "building.2.fill", tint: .secondary)
        }
    }

    private var accessBlock: some View {
        HStack(spacing: 10) {
            Pill(text: f.access.accessType.displayName, symbol: Icons.access(f.access.accessType), tint: .secondary)
            Pill(text: costText, symbol: Icons.cost(rec.costFit), tint: rec.costFit == .free ? Theme.available : .secondary)
        }
    }

    private var costText: String {
        switch rec.costFit {
        case .paid(let p?): return Format.money(p)
        default: return rec.costFit.label
        }
    }

    private var actions: some View {
        VStack(spacing: 10) {
            Button { openDirections() } label: {
                Label("Directions", systemImage: "arrow.triangle.turn.up.right.diamond.fill")
            }
            .buttonStyle(PrimaryButtonStyle())
            .accessibilityIdentifier("directionsButton")
            HStack(spacing: 10) {
                Button { showDetail = true } label: { Label("Court Details", systemImage: "info.circle") }
                    .buttonStyle(SecondaryButtonStyle())
                    .accessibilityIdentifier("detailsButton")
                Button { showReport = true } label: { Label("Report Status", systemImage: "hand.tap") }
                    .buttonStyle(SecondaryButtonStyle())
                    .accessibilityIdentifier("reportButton")
            }
        }
    }

    private var shareURL: URL {
        var c = URLComponents(string: "https://maps.apple.com/")!
        c.queryItems = [.init(name: "ll", value: "\(f.latitude),\(f.longitude)"), .init(name: "q", value: f.name)]
        return c.url!
    }

    private func openDirections() {
        env.log("directions_tap", facilityID: f.id)
        let item = MKMapItem(placemark: MKPlacemark(coordinate: f.clCoordinate))
        item.name = f.name
        item.openInMaps(launchOptions: [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDefault])
    }
}
