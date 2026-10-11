import PickleCore
import SwiftUI

struct FiltersSheet: View {
    @Binding var filters: FilterState
    @Binding var sortMode: SortMode
    @Environment(\.dismiss) private var dismiss

    private let columns = [GridItem(.adaptive(minimum: 150), spacing: 10)]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
                    section("Sort by") {
                        Picker("Sort by", selection: $sortMode) {
                            ForEach(SortMode.allCases) { Text($0.displayName).tag($0) }
                        }
                        .pickerStyle(.menu)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    section("Show") {
                        LazyVGrid(columns: columns, spacing: 10) {
                            toggle("Likely available", "checkmark.circle", $filters.likelyAvailableOnly)
                            toggle("Free only", "gift", $filters.freeOnly)
                            toggle("Public walk-on", "figure.walk", $filters.publicWalkOnOnly)
                            toggle("Dedicated courts", "figure.pickleball", $filters.dedicatedOnly)
                            toggle("Lights", "lightbulb", $filters.lightsOnly)
                            toggle("Reservations", "calendar.badge.clock", $filters.reservationAvailable)
                            toggle("Open play", "person.3", $filters.openPlayOnly)
                            toggle("Skill match", "chart.bar", $filters.skillMatchOnly)
                        }
                    }
                    section("Setting") {
                        Picker("Setting", selection: $filters.setting) {
                            ForEach(FilterState.Setting.allCases) { Text($0.label).tag($0) }
                        }
                        .pickerStyle(.segmented)
                    }
                    section("Distance") {
                        Picker("Within", selection: $filters.maxMiles) {
                            Text("Any").tag(Double?.none)
                            ForEach([2.0, 5, 10, 25], id: \.self) { Text("\(Int($0)) mi").tag(Double?.some($0)) }
                        }
                        .pickerStyle(.segmented)
                    }
                    section("Minimum courts") {
                        Picker("Minimum courts", selection: $filters.minCourts) {
                            ForEach([0, 2, 4, 8], id: \.self) { Text($0 == 0 ? "Any" : "\($0)+").tag($0) }
                        }
                        .pickerStyle(.segmented)
                    }
                }
                .padding()
            }
            .background(Theme.groupedBackground)
            .navigationTitle("Filters")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Reset") { filters = FilterState() }.disabled(!filters.isActive)
                }
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() }.bold() }
            }
        }
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.headline).accessibilityAddTraits(.isHeader)
            content()
        }
    }

    private func toggle(_ label: String, _ symbol: String, _ binding: Binding<Bool>) -> some View {
        Button {
            binding.wrappedValue.toggle()
            Haptics.select()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: binding.wrappedValue ? "checkmark.circle.fill" : symbol)
                Text(label).font(.subheadline.weight(.semibold)).lineLimit(1).minimumScaleFactor(0.85)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .frame(minHeight: 50)
            .foregroundStyle(binding.wrappedValue ? Color.white : Color.primary)
            .background(binding.wrappedValue ? AnyShapeStyle(Theme.accent) : AnyShapeStyle(Theme.cardBackground),
                        in: RoundedRectangle(cornerRadius: Theme.Radius.s, style: .continuous))
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel(label)
        .accessibilityValue(binding.wrappedValue ? "On" : "Off")
    }
}
