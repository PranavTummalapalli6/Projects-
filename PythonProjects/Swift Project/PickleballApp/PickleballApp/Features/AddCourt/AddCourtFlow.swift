import MapKit
import PhotosUI
import PickleCore
import SwiftUI

/// "+ Add Court": place a pin → minimal basics → (optional details) → duplicate check → done.
struct AddCourtFlow: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss
    @State private var vm: AddCourtViewModel
    @State private var camera: MapCameraPosition
    @State private var searchText = ""
    @State private var photoItem: PhotosPickerItem?

    init(env: AppEnvironment, center: GeoPoint?) {
        _vm = State(initialValue: AddCourtViewModel(env: env, initialCenter: center))
        let c = center ?? GeoPoint(latitude: 39.5, longitude: -98.35)
        _camera = State(initialValue: .region(MKCoordinateRegion(center: c.coordinate, latitudinalMeters: center == nil ? 3_000_000 : 1200,
                                                                 longitudinalMeters: center == nil ? 3_000_000 : 1200)))
    }

    var body: some View {
        NavigationStack {
            Group {
                switch vm.step {
                case .location: locationStep
                case .basics: basicsStep
                case .details: detailsStep
                case .duplicates: duplicatesStep
                case .done: doneStep
                }
            }
            .animation(.default, value: vm.step)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    if vm.step != .done { Button("Cancel") { dismiss() } }
                }
            }
        }
    }

    private var title: String {
        switch vm.step {
        case .location: "Where are the courts?"
        case .basics: "Add a court"
        case .details: "More details"
        case .duplicates: "Already listed?"
        case .done: "Thank you"
        }
    }

    // MARK: Steps

    private var locationStep: some View {
        ZStack {
            Map(position: $camera) { UserAnnotation() }
                .mapStyle(.hybrid(elevation: .flat, pointsOfInterest: .excludingAll))
                .onMapCameraChange(frequency: .continuous) { ctx in
                    vm.pinCenter = GeoPoint(latitude: ctx.region.center.latitude, longitude: ctx.region.center.longitude)
                }
            Image(systemName: "mappin")
                .font(.system(size: 40, weight: .bold))
                .foregroundStyle(Theme.accent)
                .shadow(radius: 3)
                .offset(y: -20)
                .accessibilityHidden(true)
            VStack {
                HStack {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("Search address or park", text: $searchText)
                        .submitLabel(.search)
                        .onSubmit {
                            Task {
                                if let p = await vm.search(searchText) {
                                    withAnimation { camera = .region(MKCoordinateRegion(center: p.coordinate, latitudinalMeters: 800, longitudinalMeters: 800)) }
                                }
                            }
                        }
                }
                .padding(12)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: Theme.Radius.m))
                .padding()
                Spacer()
                VStack(spacing: 10) {
                    Text("Move the map so the pin sits on the courts").font(.subheadline.weight(.semibold))
                    HStack(spacing: 10) {
                        if env.location.isAuthorized {
                            Button {
                                if let p = env.location.lastFix?.point {
                                    withAnimation { camera = .region(MKCoordinateRegion(center: p.coordinate, latitudinalMeters: 300, longitudinalMeters: 300)) }
                                }
                            } label: { Label("My location", systemImage: "location.fill") }
                                .buttonStyle(SecondaryButtonStyle())
                        }
                        Button("Use this spot") { vm.confirmLocation() }
                            .buttonStyle(PrimaryButtonStyle())
                            .accessibilityIdentifier("useThisSpot")
                    }
                }
                .padding()
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: Theme.Radius.l))
                .padding()
            }
        }
    }

    private var basicsStep: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
                question("How many courts?") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 8) {
                        ForEach([1, 2, 3, 4, 6, 8, 10, 12], id: \.self) { n in
                            ChoiceTile(symbol: "number", label: "\(n)", isSelected: vm.draft.courtCount == n) {
                                vm.draft.courtCount = n
                                Haptics.select()
                            }
                        }
                    }
                }
                question("What kind of courts?") {
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                        typeTile(.dedicatedPickleball, "figure.pickleball", "Dedicated pickleball")
                        typeTile(.pickleballLinedTennis, "rectangle.split.2x1", "Tennis + pickleball lines")
                        typeTile(.convertibleTennis, "figure.tennis", "Tennis, portable nets")
                        typeTile(.multiUse, "square.grid.2x2", "Multi-use")
                    }
                }
                question("Indoor or outdoor?") {
                    HStack(spacing: 10) {
                        ChoiceTile(symbol: "tree.fill", label: "Outdoor", isSelected: vm.draft.indoorOutdoor == .outdoor) { vm.draft.indoorOutdoor = .outdoor }
                        ChoiceTile(symbol: "building.2.fill", label: "Indoor", isSelected: vm.draft.indoorOutdoor == .indoor) { vm.draft.indoorOutdoor = .indoor }
                    }
                }
                question("Name (optional)") {
                    TextField("e.g. Oak Park courts", text: $vm.draft.name)
                        .textInputAutocapitalization(.words)
                        .padding(14)
                        .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: Theme.Radius.s))
                }
                if let error = vm.errorMessage { WarningBanner(text: error) }
                VStack(spacing: 10) {
                    Button { Task { await vm.submit() } } label: {
                        if vm.submitting { ProgressView().tint(.white) } else { Text("Submit court") }
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(vm.submitting)
                    .accessibilityIdentifier("submitCourt")
                    Button("Add more details (optional)") { vm.step = .details }
                        .buttonStyle(SecondaryButtonStyle())
                }
            }
            .padding()
        }
        .background(Theme.groupedBackground)
    }

    private var detailsStep: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
                question("Lights?") {
                    HStack(spacing: 10) {
                        ChoiceTile(symbol: "lightbulb.fill", label: "Yes", isSelected: vm.draft.hasLights == true) { vm.draft.hasLights = true }
                        ChoiceTile(symbol: "lightbulb.slash", label: "No", isSelected: vm.draft.hasLights == false) { vm.draft.hasLights = false }
                    }
                }
                question("Who can play?") {
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                        accessTile(.publicWalkOn)
                        accessTile(.publicReservation)
                        accessTile(.residentGuestAllowed)
                        accessTile(.hoa)
                        accessTile(.membershipRequired)
                        accessTile(.dayPassAvailable)
                    }
                }
                question("Cost") {
                    HStack(spacing: 10) {
                        ChoiceTile(symbol: "gift", label: "Free", isSelected: vm.draft.costType == .free) { vm.draft.costType = .free }
                        ChoiceTile(symbol: "dollarsign.circle", label: "Paid", isSelected: vm.draft.costType == .paid) { vm.draft.costType = .paid }
                        ChoiceTile(symbol: "person.crop.circle.badge.checkmark", label: "Members", isSelected: vm.draft.costType == .membership) { vm.draft.costType = .membership }
                    }
                }
                question("How do people rotate?") {
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                        ChoiceTile(symbol: "square.stack.3d.up", label: "Paddle stack", isSelected: vm.draft.playSystem == .paddleStack) { vm.draft.playSystem = .paddleStack }
                        ChoiceTile(symbol: "clock", label: "Play until done", isSelected: vm.draft.playSystem == .stayUntilFinished) { vm.draft.playSystem = .stayUntilFinished }
                        ChoiceTile(symbol: "person.3", label: "Organized open play", isSelected: vm.draft.playSystem == .organizedOpenPlay) { vm.draft.playSystem = .organizedOpenPlay }
                        ChoiceTile(symbol: "calendar", label: "Reservations", isSelected: vm.draft.playSystem == .reservationOnly) { vm.draft.playSystem = .reservationOnly }
                    }
                }
                question("Notes (optional)") {
                    TextField("Hours, gate code policy, anything helpful", text: $vm.draft.notes, axis: .vertical)
                        .lineLimit(2...4)
                        .padding(14)
                        .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: Theme.Radius.s))
                }
                question("Photo (optional)") {
                    let photoLabel = vm.photoData == nil ? "Add a photo of the courts" : "Photo added ✓"
                    PhotosPicker(selection: $photoItem, matching: .images) {
                        Label(photoLabel, systemImage: "camera")
                    }
                    .buttonStyle(SecondaryButtonStyle())
                    .onChange(of: photoItem) { _, item in
                        Task { @MainActor in
                            let data = try? await item?.loadTransferable(type: Data.self)
                            vm.photoData = data
                        }
                    }
                    Text("Location data is removed from photos before upload.").font(.footnote).foregroundStyle(.secondary)
                }
                if let error = vm.errorMessage { WarningBanner(text: error) }
                Button { Task { await vm.submit() } } label: {
                    if vm.submitting { ProgressView().tint(.white) } else { Text("Submit court") }
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(vm.submitting)
            }
            .padding()
        }
        .background(Theme.groupedBackground)
    }

    private var duplicatesStep: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.l) {
                Text("Is this one of these existing locations?").font(.title3.weight(.bold))
                ForEach(vm.duplicates) { c in
                    Button { Task { await vm.chooseExisting(c) } } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(c.name).font(.headline)
                                Text("\(Format.distance(c.distanceMeters)) from your pin").font(.subheadline).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text("Yes, this one").font(.subheadline.weight(.semibold)).foregroundStyle(Theme.accent)
                        }
                        .padding()
                        .frame(minHeight: Theme.largeTap)
                        .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: Theme.Radius.m))
                    }
                    .buttonStyle(PressableStyle())
                    .foregroundStyle(.primary)
                }
                if let error = vm.errorMessage { WarningBanner(text: error) }
                Button { Task { await vm.submit(forceNew: true) } } label: {
                    if vm.submitting { ProgressView() } else { Text("No, it's a different court") }
                }
                .buttonStyle(SecondaryButtonStyle())
                .accessibilityIdentifier("notDuplicate")
            }
            .padding()
        }
        .background(Theme.groupedBackground)
    }

    private var doneStep: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "checkmark.circle.fill").font(.system(size: 64)).foregroundStyle(Theme.available)
            if let name = vm.confirmedExistingName {
                Text("Thanks — you confirmed \(name).").font(.title3.weight(.bold)).multilineTextAlignment(.center)
            } else {
                Text("Court added!").font(.title2.weight(.bold))
                Pill(text: "Community-reported · Verification pending", symbol: "person.2.fill", tint: Theme.restricted)
                Text("It's on the map now. Other players will confirm it as they visit.")
                    .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
            }
            if let until = env.contributor.justUnlockedUntil {
                Text("Thanks for helping nearby players. Live court insights are available \(Format.relativeDays(until: until)).")
                    .font(.subheadline).multilineTextAlignment(.center)
            }
            Spacer()
            Button("Done") { dismiss() }.buttonStyle(PrimaryButtonStyle())
        }
        .padding()
        .accessibilityIdentifier("addCourtDone")
    }

    // MARK: Helpers

    private func question<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.headline).accessibilityAddTraits(.isHeader)
            content()
        }
    }

    private func typeTile(_ t: CourtType, _ symbol: String, _ label: String) -> some View {
        ChoiceTile(symbol: symbol, label: label, isSelected: vm.draft.courtType == t) {
            vm.draft.courtType = t
            Haptics.select()
        }
    }

    private func accessTile(_ a: AccessType) -> some View {
        ChoiceTile(symbol: Icons.access(a), label: a.displayName, isSelected: vm.draft.accessType == a) {
            vm.draft.accessType = a
            Haptics.select()
        }
    }
}
