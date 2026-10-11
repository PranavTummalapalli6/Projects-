import MapKit
import PickleCore
import SwiftUI

struct MapScreen: View {
    private enum ActiveSheet: String, Identifiable {
        case search, filters, addCourt, profile
        var id: String { rawValue }
    }

    private struct Selection: Identifiable, Equatable { let id: UUID }

    @Environment(AppEnvironment.self) private var env
    @State private var vm: MapViewModel
    @State private var position: MapCameraPosition
    @State private var selection: Selection?
    @State private var activeSheet: ActiveSheet?
    @State private var showPrimer = false
    @State private var centeredOnUser = false

    init(env: AppEnvironment) {
        _vm = State(initialValue: MapViewModel(env: env))
        let stored = env.store.load(GeoBoundingBox.self, key: StoreKeys.lastRegion)
        let fallback = env.isDemo
            ? GeoBoundingBox(center: GeoPoint(latitude: 38.853, longitude: -77.300), latitudeDelta: 0.12, longitudeDelta: 0.12)
            : GeoBoundingBox(center: GeoPoint(latitude: 39.5, longitude: -98.35), latitudeDelta: 30, longitudeDelta: 30)
        let box = env.config.isUITesting ? fallback : (stored ?? fallback)
        _position = State(initialValue: .region(MKCoordinateRegion(
            center: box.center.coordinate, span: MKCoordinateSpan(latitudeDelta: box.latitudeDelta, longitudeDelta: box.longitudeDelta))))
    }

    var body: some View {
        ZStack {
            map
            VStack(spacing: 10) {
                topBar
                statusRow
                Spacer()
                bottomContent
            }
            .padding(.bottom, 8)
            if env.visits.activePrompt == nil && !showPrimer {
                HStack {
                    Spacer()
                    controls.padding(.trailing, 14)
                }
                .transition(.opacity)
            }
        }
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .search:
                SearchView(onSelectFacility: { f in focus(on: f) }, onSelectRegion: { region in
                    withAnimation { position = .region(region) }
                })
            case .filters:
                FiltersSheet(filters: $vm.filters, sortMode: Bindable(env.preferences).sortMode)
                    .presentationDetents([.medium, .large])
            case .addCourt:
                AddCourtFlow(env: env, center: vm.visibleBox?.center ?? env.location.lastFix?.point)
                    .onDisappear { Task { await vm.refresh() } }
            case .profile:
                ProfileView()
            }
        }
        .onAppear(perform: onAppear)
        .onChange(of: env.location.lastFix?.point, initial: true) { _, point in
            vm.locationChanged(point)
            guard let point, !centeredOnUser, !env.config.isUITesting else { return }
            centeredOnUser = true
            withAnimation { position = .region(MKCoordinateRegion(center: point.coordinate, latitudinalMeters: 16_000, longitudinalMeters: 16_000)) }
        }
        .onChange(of: env.location.authorization) { _, auth in
            if auth == .authorized { env.location.startUpdates(); showPrimer = false }
        }
        .onChange(of: env.preferences.prefs) { _, _ in vm.preferencesChanged() }
        .onChange(of: env.preferences.sortMode) { _, _ in vm.preferencesChanged() }
    }

    // MARK: Map

    private var map: some View {
        Map(position: $position) {
            UserAnnotation()
            ForEach(vm.clusters(in: vm.visibleBox)) { cluster in
                if cluster.isSingle, let rec = vm.recommendation(for: cluster.memberIDs[0]) {
                    Annotation(rec.facility.name, coordinate: rec.facility.clCoordinate, anchor: .bottom) {
                        Button { select(rec.id) } label: {
                            FacilityMarkerView(recommendation: rec, isSelected: selection?.id == rec.id)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("marker_\(rec.facility.name)")
                    }
                    .annotationTitles(.hidden)
                } else {
                    Annotation("", coordinate: cluster.center.coordinate) {
                        Button { zoom(into: cluster) } label: { ClusterMarkerView(count: cluster.memberIDs.count) }
                            .buttonStyle(.plain)
                    }
                    .annotationTitles(.hidden)
                }
            }
        }
        .mapStyle(.standard(pointsOfInterest: .excludingAll))
        .mapControls {
            MapCompass()
            MapScaleView()
        }
        .onMapCameraChange(frequency: .onEnd) { context in
            let box = GeoBoundingBox(region: context.region)
            vm.cameraChanged(to: box)
            if !env.config.isUITesting { env.store.save(box, key: StoreKeys.lastRegion) }
        }
        .sheet(item: $selection) { sel in
            NavigationStack {
                if let rec = vm.recommendation(for: sel.id) {
                    FacilitySheet(rec: rec, onReported: { Task { await vm.refresh() } })
                } else {
                    ProgressView("Loading court…").frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .presentationDetents([.fraction(0.52), .large])
            .presentationBackgroundInteraction(.enabled(upThrough: .fraction(0.52)))
            .presentationDragIndicator(.visible)
            .presentationCornerRadius(Theme.Radius.l)
        }
    }

    // MARK: Chrome

    private var topBar: some View {
        HStack(spacing: 10) {
            Button { activeSheet = .search } label: {
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                    Text("Search courts, parks, city or ZIP").lineLimit(1)
                    Spacer(minLength: 0)
                }
                .font(.body)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 16)
                .frame(minHeight: 50)
                .background(.regularMaterial, in: Capsule())
            }
            .accessibilityIdentifier("searchButton")
            Button { activeSheet = .profile } label: {
                Image(systemName: "person.crop.circle")
                    .font(.title2)
                    .frame(width: 50, height: 50)
                    .background(.regularMaterial, in: Circle())
            }
            .accessibilityLabel("Profile and preferences")
            .accessibilityIdentifier("profileButton")
        }
        .padding(.horizontal, 16)
        .padding(.top, 4)
    }

    private var statusRow: some View {
        HStack(spacing: 8) {
            if env.isDemo { Pill(text: "Demo data", symbol: "theatermasks", tint: Theme.restricted, filled: false) }
            if vm.filters.isActive {
                Button { activeSheet = .filters } label: {
                    Pill(text: vm.filters.summary, symbol: "line.3.horizontal.decrease.circle.fill", tint: Theme.accent, filled: true)
                }
                Button { vm.filters = FilterState() } label: {
                    Image(systemName: "xmark.circle.fill").font(.title3).foregroundStyle(.secondary)
                }
                .accessibilityLabel("Clear filters")
            }
            if vm.loadState == .loading || vm.discoveryInProgress {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text(vm.discoveryInProgress ? "Looking for courts in this area…" : "Finding courts…").font(.footnote.weight(.semibold))
                }
                .padding(.horizontal, 10).padding(.vertical, 6)
                .background(.regularMaterial, in: Capsule())
            }
            if vm.loadState == .offline {
                Button { Task { await vm.refresh() } } label: {
                    Pill(text: "Offline — tap to retry", symbol: "wifi.slash", tint: Theme.unknown)
                }
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .background(.clear)
    }

    private var controls: some View {
        VStack(spacing: 10) {
            controlButton(env.location.isAuthorized ? "location.fill" : "location", label: "Center on my location", id: "locateButton") {
                if env.location.isAuthorized, let p = env.location.lastFix?.point {
                    withAnimation { position = .region(MKCoordinateRegion(center: p.coordinate, latitudinalMeters: 12_000, longitudinalMeters: 12_000)) }
                } else if env.location.authorization == .notDetermined {
                    showPrimer = true
                } else {
                    activeSheet = .search
                }
            }
            controlButton("line.3.horizontal.decrease", label: "Filters", id: "filtersButton", badge: vm.filters.activeCount) {
                activeSheet = .filters
            }
            controlButton("plus", label: "Add a court", id: "addCourtButton") { activeSheet = .addCourt }
        }
    }

    private func controlButton(_ symbol: String, label: String, id: String, badge: Int = 0, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.title3.weight(.semibold))
                .frame(width: 50, height: 50)
                .background(.regularMaterial, in: Circle())
                .overlay(alignment: .topTrailing) {
                    if badge > 0 {
                        Text("\(badge)").font(.caption2.bold()).foregroundStyle(.white)
                            .frame(width: 18, height: 18).background(Theme.accent, in: Circle())
                    }
                }
                .shadow(color: .black.opacity(0.12), radius: 4, y: 2)
        }
        .accessibilityLabel(label)
        .accessibilityIdentifier(id)
    }

    @ViewBuilder private var bottomContent: some View {
        if let prompt = env.visits.activePrompt, selection == nil {
            PromptCard(prompt: prompt, reports: env.reports) { answered in
                withAnimation {
                    if answered { env.visits.completePrompt() } else { env.visits.dismissPrompt() }
                }
                if answered { Task { await vm.refresh() } }
            }
            .transition(.move(edge: .bottom).combined(with: .opacity))
        } else if showPrimer {
            LocationPrimerView(onAllow: {
                env.preferences.hasSeenLocationPrimer = true
                env.location.requestPermission()
                showPrimer = false
            }, onSearchInstead: {
                env.preferences.hasSeenLocationPrimer = true
                showPrimer = false
                activeSheet = .search
            })
            .transition(.move(edge: .bottom).combined(with: .opacity))
        } else {
            switch vm.loadState {
            case .empty where !vm.discoveryInProgress:
                stateCard {
                    EmptyStateView(symbol: "mappin.slash", title: "No known courts nearby.",
                                   message: vm.filters.isActive ? "Try clearing filters — or know one we're missing?" : "Know one we're missing?",
                                   actionTitle: "Add a Court") { activeSheet = .addCourt }
                }
            case .zoomedOut:
                stateCard {
                    EmptyStateView(symbol: "plus.magnifyingglass", title: "Zoom in to see courts",
                                   message: "Or search for a city or ZIP code.", actionTitle: "Search") { activeSheet = .search }
                }
            case .error(let message):
                stateCard {
                    EmptyStateView(symbol: "exclamationmark.icloud", title: "Couldn't load courts", message: message,
                                   actionTitle: "Try again") { Task { await vm.refresh() } }
                }
            default:
                if !vm.picks.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        if vm.origin == nil {
                            Text("Turn on location for travel times").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                                .padding(.horizontal, 20)
                        }
                        RecommendationStrip(picks: vm.picks) { rec in select(rec.id) }
                    }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                } else if vm.loadState == .loaded, !vm.displayed.isEmpty {
                    stateCard {
                        EmptyStateView(symbol: "clock.badge.xmark", title: "Nothing playable right now",
                                       message: "Courts here are closed, restricted or unavailable. Tap a marker to see why.")
                    }
                }
            }
        }
    }

    private func stateCard<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: Theme.Radius.l, style: .continuous))
            .padding(.horizontal, 16)
    }

    // MARK: Actions

    private func onAppear() {
        if env.location.isAuthorized {
            env.location.startUpdates()
            if let p = env.location.lastFix?.point, !env.config.isUITesting {
                centeredOnUser = true
                position = .region(MKCoordinateRegion(center: p.coordinate, latitudinalMeters: 16_000, longitudinalMeters: 16_000))
            }
        } else if env.location.authorization == .notDetermined && !env.preferences.hasSeenLocationPrimer && !env.config.isUITesting {
            showPrimer = true
        }
        Task { await env.contributor.refresh() }
    }

    private func select(_ id: UUID) {
        Haptics.tap()
        selection = Selection(id: id)
    }

    private func zoom(into cluster: MapCluster<UUID>) {
        let span = (vm.visibleBox?.latitudeDelta ?? 0.2) / 3
        withAnimation { position = .region(MKCoordinateRegion(center: cluster.center.coordinate,
                                                              span: MKCoordinateSpan(latitudeDelta: span, longitudeDelta: span))) }
    }

    private func focus(on f: Facility) {
        withAnimation { position = .region(MKCoordinateRegion(center: f.clCoordinate, latitudinalMeters: 4000, longitudinalMeters: 4000)) }
        Task {
            try? await Task.sleep(for: .milliseconds(900))
            selection = Selection(id: f.id)
        }
    }
}
