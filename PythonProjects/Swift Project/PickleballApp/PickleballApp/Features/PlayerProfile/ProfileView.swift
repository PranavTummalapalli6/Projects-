import PickleCore
import SwiftUI
import UIKit

struct ProfileView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss
    @State private var relaxDemoChecks = false

    var body: some View {
        @Bindable var prefs = env.preferences
        NavigationStack {
            Form {
                Section {
                    NavigationLink { SkillPickerView() } label: {
                        LabeledContent("Your level", value: prefs.prefs.skill == .unknown ? "Not set" : prefs.prefs.skill.displayName)
                    }
                    Toggle("Prefer beginner-friendly courts", isOn: $prefs.prefs.wantsBeginnerFriendly)
                    Toggle("I enjoy competitive play", isOn: Binding(get: { prefs.prefs.prefersCompetitive == true },
                                                                   set: { prefs.prefs.prefersCompetitive = $0 ? true : nil }))
                } header: { Text("Your game") } footer: { Text("Optional. Used to explain trade-offs — never to hide courts.") }

                Section("Cost") {
                    Picker("Show", selection: $prefs.prefs.costPreference) {
                        Text("Free only").tag(CostPreference.freeOnly)
                        Text("Include paid").tag(CostPreference.includePaid)
                        Text("No preference").tag(CostPreference.noPreference)
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                }

                Section("Recommendations") {
                    Picker("Sort by", selection: $prefs.sortMode) {
                        ForEach(SortMode.allCases) { Text($0.displayName).tag($0) }
                    }
                }

                Section("Live insights") {
                    contributorRow
                }

                Section {
                    LabeledContent("Location", value: locationLabel)
                    if env.location.authorization == .notDetermined {
                        Button("Use my location") { env.location.requestPermission() }
                    } else if !env.location.isAuthorized {
                        Button("Open Settings") {
                            if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                        }
                    }
                    Toggle("Share anonymous visit timing", isOn: $prefs.passiveVisitsEnabled)
                } header: { Text("Privacy") } footer: {
                    Text("We never store a location history. Visit timing shares only when you arrived at and left a court, which helps estimate how long games last. Off by default.")
                }

                if env.isDemo {
                    Section {
                        Toggle("Allow reports from anywhere", isOn: $relaxDemoChecks)
                            .onChange(of: relaxDemoChecks) { _, v in Task { await env.demoBackend?.setRelaxLocationChecks(v) } }
                    } header: { Text("Demo mode") } footer: {
                        Text("You're using fictional demo courts. Add your Supabase keys in Config/Secrets.xcconfig to use the live backend.")
                    }
                }

                Section("About") {
                    LabeledContent("Version", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "–")
                    Text("Court data from players, public recreation datasets and OpenStreetMap (© OpenStreetMap contributors). Wait times are estimates.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("You")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .task {
                await env.contributor.refresh()
                relaxDemoChecks = await env.demoBackend?.relaxLocationChecks ?? false
            }
        }
    }

    private var locationLabel: String {
        switch env.location.authorization {
        case .authorized: "While using the app"
        case .denied: "Off"
        case .restricted: "Restricted"
        case .notDetermined: "Not set"
        }
    }

    @ViewBuilder private var contributorRow: some View {
        let s = env.contributor.status
        if !s.liveGatingEnabled {
            Label("Live insights are open to everyone while the community grows.", systemImage: "dot.radiowaves.left.and.right")
                .font(.subheadline)
        } else if let until = s.insightsUntil, until > Date() {
            Label("Live insights unlocked until \(until.formatted(date: .abbreviated, time: .omitted))", systemImage: "checkmark.seal.fill")
                .foregroundStyle(Theme.available)
        } else {
            Label("Share a quick report from any court to unlock live insights for a week.", systemImage: "hand.tap")
                .font(.subheadline)
        }
        if s.qualifyingContributions > 0 {
            LabeledContent("Your helpful reports", value: "\(s.qualifyingContributions)")
        }
    }
}

/// Large, readable rows instead of tiny radio buttons.
struct SkillPickerView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List {
            Section {
                ForEach(SkillBand.ladder + [.unknown], id: \.self) { band in
                    Button {
                        env.preferences.prefs.skill = band
                        Haptics.select()
                        dismiss()
                    } label: {
                        HStack {
                            Text(band.displayName).font(.body.weight(.medium)).foregroundStyle(.primary)
                            Spacer()
                            if env.preferences.prefs.skill == band { Image(systemName: "checkmark").foregroundStyle(Theme.accent) }
                        }
                        .frame(minHeight: 48)
                    }
                    .accessibilityAddTraits(env.preferences.prefs.skill == band ? .isSelected : [])
                }
            } footer: {
                Text("Not sure? Choose \"Don't care / unknown\". You can change this anytime.")
            }
        }
        .navigationTitle("Your level")
    }
}
