import PickleCore
import SwiftUI
import UIKit

/// "Report status": one contextual question first; optional detail only if the user asks for it.
struct QuickReportSheet: View {
    let facility: Facility
    var onReported: () -> Void = {}

    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss
    @State private var kind: PromptKind = .howBusy
    @State private var selected: String?
    @State private var submitting = false
    @State private var result: (ok: Bool, message: String)?
    @State private var showDetail = false
    @State private var showIssue = false

    private var check: LocationCheck { env.reports.locationCheck(for: facility) }
    private var needsLocation: Bool { kind != .confirmExists && !check.allowsLiveReport }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.l) {
                    if let result, result.ok {
                        successView(result.message)
                    } else {
                        if needsLocation { locationGate } else { questionView }
                        if let result, !result.ok { WarningBanner(text: result.message) }
                        otherReports
                    }
                }
                .padding()
            }
            .background(Theme.groupedBackground)
            .navigationTitle(facility.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .sheet(isPresented: $showIssue) { IssueReportSheet(facility: facility) }
        }
        .onAppear { kind = defaultKind() }
    }

    private func defaultKind() -> PromptKind {
        if facility.isCommunityReported { return .confirmExists }
        let ctx = PromptContext(facility: facility, visitID: UUID(), isNearby: true, prediction: nil, weather: nil, now: Date())
        return env.reports.policy.chooseKind(ctx, state: FacilityPromptState()) ?? (facility.playSystem.isRotation ? .paddleWait : .howBusy)
    }

    private var questionView: some View {
        let question = ReportQuestion.make(kind)
        return VStack(alignment: .leading, spacing: 12) {
            Text(question.title).font(.title2.weight(.bold))
            QuestionTiles(question: question, selected: selected, disabled: submitting) { option in
                selected = option.value
                submitting = true
                Task {
                    let r = await QuickAnswer.submit(option, question: question, facility: facility, reports: env.reports, prompted: false)
                    submitting = false
                    withAnimation(.spring) { result = r }
                    if r.ok { Haptics.success(); onReported() } else { Haptics.warning() }
                }
            }
            if submitting { ProgressView().frame(maxWidth: .infinity) }
        }
    }

    private var locationGate: some View {
        Card(title: "You're not at the courts", symbol: "location.slash") {
            Text(check.userMessage).font(.body).foregroundStyle(.secondary)
            Text("Live reports come from people at the facility, which keeps them trustworthy for everyone.")
                .font(.footnote).foregroundStyle(.secondary)
            if check == .unavailable {
                if env.location.authorization == .notDetermined {
                    Button("Use my location") { env.location.requestPermission() }.buttonStyle(PrimaryButtonStyle())
                } else {
                    Button("Open Settings") {
                        if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                    }
                    .buttonStyle(SecondaryButtonStyle())
                }
            }
            if env.reports.allowsSimulatedPresence {
                Button {
                    env.visits.simulateArrival(at: facility, prompt: false)
                } label: {
                    Label("Demo: pretend I'm here", systemImage: "location.fill.viewfinder")
                }
                .buttonStyle(SecondaryButtonStyle())
                .accessibilityIdentifier("pretendHere")
            }
        }
    }

    private func successView(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.l) {
            VStack(spacing: 10) {
                Image(systemName: "checkmark.circle.fill").font(.system(size: 48)).foregroundStyle(Theme.available)
                Text(message).font(.title3.weight(.semibold)).multilineTextAlignment(.center)
                if let until = env.contributor.justUnlockedUntil {
                    Text("Live court insights are available \(Format.relativeDays(until: until)).")
                        .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
                        .onDisappear { env.contributor.justUnlockedUntil = nil }
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical)
            if kind != .confirmExists {
                DisclosureGroup(isExpanded: $showDetail) {
                    OptionalDetailView(facility: facility).padding(.top, 8)
                } label: {
                    Label("Add more detail (optional)", systemImage: "plus.circle").font(.headline)
                }
                .padding()
                .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: Theme.Radius.l))
            }
            Button("Done") { dismiss() }.buttonStyle(PrimaryButtonStyle())
        }
    }

    private var otherReports: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Report something else").font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach([PromptKind.howBusy, .paddleWait, .courtSurface, .confirmExists].filter { $0 != kind }, id: \.self) { k in
                        Button { kind = k; selected = nil; result = nil } label: {
                            Pill(text: ReportQuestion.make(k).title.replacingOccurrences(of: "?", with: ""), symbol: symbol(k), tint: Theme.accent)
                        }
                    }
                    Button { showIssue = true } label: {
                        Pill(text: "Problem here", symbol: "exclamationmark.triangle", tint: Theme.busy)
                    }
                }
            }
        }
    }

    private func symbol(_ k: PromptKind) -> String {
        switch k {
        case .howBusy: "person.3"
        case .paddleWait: "square.stack.3d.up"
        case .courtSurface: "drop"
        case .confirmExists: "mappin.and.ellipse"
        }
    }
}

/// Only for motivated users. Each section is independent and optional.
struct OptionalDetailView: View {
    let facility: Facility
    @Environment(AppEnvironment.self) private var env
    @State private var sent: Set<String> = []
    @State private var usableCourts: Int
    @State private var cultureTags: Set<PlayCultureTag> = []

    init(facility: Facility) {
        self.facility = facility
        _usableCourts = State(initialValue: facility.defaultPickleballCourts ?? facility.totalPhysicalCourts ?? 2)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            if facility.playSystem.isRotation {
                group("How many paddles?", key: "paddles") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 3), spacing: 8) {
                        ForEach(PaddleCountRange.allCases.filter { $0 != .unknown }, id: \.self) { range in
                            Button(range.rawValue) {
                                send("paddles", .paddleStack, value: PaddleStackLevel.from(paddles: range.midpoint ?? 0).rawValue,
                                     count: Int((range.midpoint ?? 0).rounded()))
                            }
                            .buttonStyle(SecondaryButtonStyle())
                        }
                    }
                }
            }
            group("Courts set up for pickleball right now", key: "courts") {
                HStack {
                    Stepper("\(usableCourts) courts", value: $usableCourts, in: 0...max(1, facility.totalPhysicalCourts ?? 30))
                        .font(.body.weight(.semibold))
                    Button("Send") { send("courts", .usableCourts, value: nil, count: usableCourts) }
                        .buttonStyle(.borderedProminent)
                }
            }
            group("Typical level here", key: "skill") {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 3), spacing: 8) {
                    ForEach(SkillBand.ladder, id: \.self) { band in
                        Button(band == .beginner ? "Beginner" : band.displayName) { send("skill", .skill, value: band.rawValue) }
                            .buttonStyle(SecondaryButtonStyle())
                    }
                }
            }
            group("Play style", key: "culture") {
                FlowTags(tags: [.openPlay, .mostlyDoubles, .singlesAvailable, .beginnerFriendly, .casual, .competitive, .challengeCourt],
                         selected: $cultureTags)
                Button("Send") { send("culture", .culture, value: cultureTags.map(\.rawValue).joined(separator: ",")) }
                    .buttonStyle(.borderedProminent)
                    .disabled(cultureTags.isEmpty)
            }
        }
    }

    @ViewBuilder
    private func group<Content: View>(_ title: String, key: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.subheadline.weight(.semibold))
            if sent.contains(key) {
                Label("Thanks!", systemImage: "checkmark.circle.fill").foregroundStyle(Theme.available)
            } else {
                content()
            }
        }
    }

    private func send(_ key: String, _ kind: LiveReportKind, value: String?, count: Int? = nil) {
        Task {
            if let r = try? await env.reports.submit(kind, value: value, count: count, at: facility, promptKind: nil), r.accepted {
                sent.insert(key)
                Haptics.success()
            } else {
                Haptics.warning()
            }
        }
    }
}

struct FlowTags: View {
    let tags: [PlayCultureTag]
    @Binding var selected: Set<PlayCultureTag>

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 8)], spacing: 8) {
            ForEach(tags, id: \.self) { tag in
                let on = selected.contains(tag)
                Button {
                    if on { selected.remove(tag) } else { selected.insert(tag) }
                    Haptics.select()
                } label: {
                    Label(tag.displayName, systemImage: Icons.culture(tag))
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .foregroundStyle(on ? Color.white : Theme.accent)
                        .background(on ? AnyShapeStyle(Theme.accent) : AnyShapeStyle(Theme.accentSoft), in: Capsule())
                }
                .buttonStyle(PressableStyle())
                .accessibilityValue(on ? "Selected" : "")
            }
        }
    }
}
