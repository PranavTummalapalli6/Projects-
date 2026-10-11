import MapKit
import Observation
import PickleCore
import SwiftUI

@Observable
@MainActor
final class SearchViewModel: NSObject, MKLocalSearchCompleterDelegate {
    var query = "" { didSet { queryChanged() } }
    private(set) var facilities: [Facility] = []
    private(set) var places: [MKLocalSearchCompletion] = []
    private(set) var searching = false

    @ObservationIgnored private let completer = MKLocalSearchCompleter()
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private let env: AppEnvironment

    init(env: AppEnvironment) {
        self.env = env
        super.init()
        completer.delegate = self
        completer.resultTypes = [.address, .pointOfInterest]
    }

    private func queryChanged() {
        let q = query.trimmingCharacters(in: .whitespaces)
        completer.queryFragment = q
        task?.cancel()
        guard q.count >= 2 else { facilities = []; return }
        task = Task {
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            searching = true
            defer { searching = false }
            let near = env.location.isAuthorized ? env.location.lastFix?.point : nil
            facilities = (try? await env.facilityService.search(q, near: near)) ?? []
            env.log("map_search")
        }
    }

    nonisolated func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        let results = Array(completer.results.prefix(6))
        Task { @MainActor in self.places = results }
    }

    nonisolated func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {}

    func resolve(_ completion: MKLocalSearchCompletion) async -> MKCoordinateRegion? {
        let request = MKLocalSearch.Request(completion: completion)
        guard let response = try? await MKLocalSearch(request: request).start() else { return nil }
        var region = response.boundingRegion
        region.span.latitudeDelta = min(max(region.span.latitudeDelta, 0.05), 0.4)
        region.span.longitudeDelta = min(max(region.span.longitudeDelta, 0.05), 0.4)
        return region
    }
}

/// Search by facility name, park, city or ZIP. Works without location permission.
struct SearchView: View {
    let onSelectFacility: (Facility) -> Void
    let onSelectRegion: (MKCoordinateRegion) -> Void

    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss
    @State private var vm: SearchViewModel?

    var body: some View {
        NavigationStack {
            List {
                if let vm {
                    if !vm.facilities.isEmpty {
                        Section("Courts") {
                            ForEach(vm.facilities) { f in
                                Button {
                                    onSelectFacility(f)
                                    dismiss()
                                } label: {
                                    Label {
                                        VStack(alignment: .leading) {
                                            Text(f.name).foregroundStyle(.primary)
                                            if let line = f.localityLine { Text(line).font(.footnote).foregroundStyle(.secondary) }
                                        }
                                    } icon: { Image(systemName: "figure.pickleball").foregroundStyle(Theme.accent) }
                                }
                            }
                        }
                    }
                    if !vm.places.isEmpty {
                        Section("Places") {
                            ForEach(vm.places, id: \.self) { p in
                                Button {
                                    Task {
                                        if let region = await vm.resolve(p) {
                                            onSelectRegion(region)
                                            dismiss()
                                        }
                                    }
                                } label: {
                                    Label {
                                        VStack(alignment: .leading) {
                                            Text(p.title).foregroundStyle(.primary)
                                            if !p.subtitle.isEmpty { Text(p.subtitle).font(.footnote).foregroundStyle(.secondary) }
                                        }
                                    } icon: { Image(systemName: "mappin.circle").foregroundStyle(.secondary) }
                                }
                            }
                        }
                    }
                    if vm.query.count >= 2 && vm.facilities.isEmpty && vm.places.isEmpty && !vm.searching {
                        ContentUnavailableView.search(text: vm.query)
                    }
                    if vm.query.isEmpty {
                        Text("Search a court, park, city or ZIP code.").foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Search")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: Binding(get: { vm?.query ?? "" }, set: { vm?.query = $0 }),
                        placement: .navigationBarDrawer(displayMode: .always), prompt: "Court, park, city or ZIP")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
        }
        .onAppear { if vm == nil { vm = SearchViewModel(env: env) } }
    }
}
