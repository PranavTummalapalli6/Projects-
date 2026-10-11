import PickleCore
import SwiftUI

/// Pick what changed, answer one small follow-up, submit. Edits apply after independent confirmation.
struct SuggestEditSheet: View {
    let facility: Facility
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss

    @State private var type: EditType?
    @State private var courts = 4
    @State private var pickleballCourts = 4
    @State private var indoorOutdoor: IndoorOutdoor = .outdoor
    @State private var access: AccessType = .publicWalkOn
    @State private var cost: AccessCostType = .free
    @State private var price = ""
    @State private var reservationRequired = false
    @State private var reservationAvailable = true
    @State private var playSystem: PlaySystem = .paddleStack
    @State private var lights = true
    @State private var restrooms = false
    @State private var note = ""
    @State private var submitting = false
    @State private var resultMessage: String?

    var body: some View {
        NavigationStack {
            Group {
                if let resultMessage {
                    VStack(spacing: 12) {
                        Image(systemName: "checkmark.circle.fill").font(.system(size: 48)).foregroundStyle(Theme.available)
                        Text(resultMessage).font(.title3.weight(.semibold)).multilineTextAlignment(.center)
                        Button("Done") { dismiss() }.buttonStyle(PrimaryButtonStyle()).padding(.top)
                    }
                    .padding()
                } else if let type {
                    form(for: type)
                } else {
                    typeList
                }
            }
            .background(Theme.groupedBackground)
            .navigationTitle("Suggest an edit")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(type == nil || resultMessage != nil ? "Cancel" : "Back") {
                        if type == nil || resultMessage != nil { dismiss() } else { type = nil }
                    }
                }
            }
        }
        .onAppear(perform: prefill)
    }

    private var typeList: some View {
        List(EditType.allCases) { t in
            Button { type = t } label: {
                Label(t.label, systemImage: t.symbol).font(.body).frame(minHeight: 44)
            }
            .foregroundStyle(.primary)
        }
    }

    @ViewBuilder
    private func form(for t: EditType) -> some View {
        Form {
            Section { Label(t.label, systemImage: t.symbol).font(.headline) }
            switch t {
            case .courtCountChanged, .pickleballCourtsAdded:
                Stepper("Physical courts: \(courts)", value: $courts, in: 1...60)
                Stepper("Set up for pickleball: \(pickleballCourts)", value: $pickleballCourts, in: 0...60)
            case .stripedForPickleball, .convertedToDedicated:
                Stepper("Pickleball courts: \(pickleballCourts)", value: $pickleballCourts, in: 1...60)
            case .indoorOutdoorChanged:
                Picker("Setting", selection: $indoorOutdoor) {
                    Text("Outdoor").tag(IndoorOutdoor.outdoor)
                    Text("Indoor").tag(IndoorOutdoor.indoor)
                    Text("Both").tag(IndoorOutdoor.both)
                }
                .pickerStyle(.segmented)
            case .accessChanged:
                Picker("Who can play", selection: $access) {
                    ForEach(AccessType.allCases.filter { $0 != .unknown }, id: \.self) { Text($0.displayName).tag($0) }
                }
            case .costChanged:
                Picker("Cost", selection: $cost) {
                    Text("Free").tag(AccessCostType.free)
                    Text("Day pass").tag(AccessCostType.dayPass)
                    Text("Reservation fee").tag(AccessCostType.reservationFee)
                    Text("Membership").tag(AccessCostType.membership)
                }
                if cost == .dayPass || cost == .reservationFee {
                    TextField("Price (e.g. 10)", text: $price).keyboardType(.decimalPad)
                }
            case .reservationPolicyChanged:
                Toggle("Reservations available", isOn: $reservationAvailable)
                Toggle("Reservation required to play", isOn: $reservationRequired)
            case .playSystemChanged:
                Picker("How play rotates", selection: $playSystem) {
                    Text("Paddle stack").tag(PlaySystem.paddleStack)
                    Text("Rotation board").tag(PlaySystem.rotationBoard)
                    Text("Play until finished").tag(PlaySystem.stayUntilFinished)
                    Text("Organized open play").tag(PlaySystem.organizedOpenPlay)
                    Text("Reservations only").tag(PlaySystem.reservationOnly)
                }
            case .amenitiesChanged:
                Toggle("Lights", isOn: $lights)
                Toggle("Restrooms", isOn: $restrooms)
            case .hoursChanged, .other, .noLongerPickleball, .permanentlyClosed:
                EmptyView()
            }
            Section(t == .hoursChanged ? "New hours" : "Note (optional)") {
                TextField(t == .hoursChanged ? "e.g. 7 AM – 9 PM daily" : "Anything else?", text: $note, axis: .vertical)
                    .lineLimit(2...4)
            }
            Section {
                Button { submit(t) } label: {
                    if submitting { ProgressView() } else { Text("Submit") }
                }
                .buttonStyle(PrimaryButtonStyle())
                .listRowInsets(EdgeInsets())
                .disabled(submitting || (t == .hoursChanged && note.trimmingCharacters(in: .whitespaces).isEmpty))
            } footer: {
                Text("Changes go live after other players confirm them. Closures show a warning right away.")
            }
        }
    }

    private func prefill() {
        courts = facility.totalPhysicalCourts ?? 4
        pickleballCourts = facility.defaultPickleballCourts ?? courts
        indoorOutdoor = facility.indoorOutdoor == .unknown ? .outdoor : facility.indoorOutdoor
        access = facility.access.accessType == .unknown ? .publicWalkOn : facility.access.accessType
        cost = facility.cost.costType == .unknown ? .free : facility.cost.costType
        playSystem = facility.playSystem == .unknown ? .paddleStack : facility.playSystem
        lights = facility.hasLights ?? true
        restrooms = facility.hasRestrooms ?? false
        reservationAvailable = facility.access.reservationAvailable ?? false
        reservationRequired = facility.access.reservationRequired ?? false
    }

    private func proposed(for t: EditType) -> [String: JSONValue] {
        switch t {
        case .courtCountChanged, .pickleballCourtsAdded:
            ["total_physical_courts": .int(courts), "default_pickleball_courts": .int(pickleballCourts)]
        case .stripedForPickleball, .convertedToDedicated: ["default_pickleball_courts": .int(pickleballCourts)]
        case .indoorOutdoorChanged: ["indoor_outdoor": .string(indoorOutdoor.rawValue)]
        case .accessChanged: ["access_type": .string(access.rawValue)]
        case .costChanged:
            ["cost_type": .string(cost.rawValue)].merging(
                Double(price.replacingOccurrences(of: "$", with: "")).map { [cost == .reservationFee ? "reservation_fee" : "day_pass_price": JSONValue.number($0)] } ?? [:]
            ) { $1 }
        case .reservationPolicyChanged: ["reservation_available": .bool(reservationAvailable), "reservation_required": .bool(reservationRequired)]
        case .playSystemChanged: ["play_system": .string(playSystem.rawValue)]
        case .amenitiesChanged: ["has_lights": .bool(lights), "has_restrooms": .bool(restrooms)]
        case .hoursChanged: ["hours_note": .string(note)]
        case .noLongerPickleball, .permanentlyClosed, .other: [:]
        }
    }

    private func submit(_ t: EditType) {
        submitting = true
        Task {
            defer { submitting = false }
            let fix = await env.location.currentFix(timeout: 4)
            do {
                let r = try await env.submissionService.suggestEdit(facility, type: t, proposed: proposed(for: t),
                                                                    note: note.isEmpty ? nil : note, fix: fix)
                resultMessage = r.status == "applied" ? "Thanks — the court info is updated." : "Thanks! We'll update it once others confirm."
                Haptics.success()
            } catch {
                resultMessage = (error as? LocalizedError)?.errorDescription ?? "We couldn't save that."
            }
        }
    }
}
