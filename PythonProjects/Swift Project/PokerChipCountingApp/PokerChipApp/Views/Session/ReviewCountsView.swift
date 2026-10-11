//
//  ReviewCountsView.swift
//  PokerChipApp
//
//  Cashing one player out: count their chips (by hand, or from a photo that is
//  only ever a starting point — stacked chips are genuinely hard to read, so the
//  counts stay editable) or type an amount. Counting by hand works with no
//  signal and no camera.
//

import SwiftUI
import UIKit

@MainActor
final class CashOutViewModel: ObservableObject {
    enum Mode: String, CaseIterable, Identifiable {
        case chips
        case amount

        var id: String { rawValue }
        var title: String { self == .chips ? "Count chips" : "Enter amount" }
    }

    enum PhotoNotice: Equatable {
        /// `ignored` chips were of colours this night isn't using, so they were left out.
        case counted(confidence: String, ignored: Int)
        case failed(String)
    }

    /// A photo that looks like it won't count well, held until the person decides.
    struct QualityPrompt: Identifiable {
        let id = UUID()
        let image: UIImage
        let pose: CameraPose?
        let angle: PhotoAngle
        let issue: PhotoQuality.Issue
    }

    /// The most photos one cash-out can be counted from.
    static let maxPhotos = 4

    let nightID: UUID
    let playerID: UUID
    let playerName: String
    let currency: String
    let colors: [String]
    let valuesMinor: [String: Int]
    /// Chips each player was dealt, shown beside the count — only when every buy-in was the standard one.
    let dealtChips: [String: Int]?
    let totalInMinor: Int
    let isEditing: Bool
    let isMissing: Bool

    @Published var mode: Mode
    @Published var counts: [String: Int]
    @Published var amountText: String
    @Published private(set) var isUploading = false
    @Published private(set) var photoNotice: PhotoNotice?
    /// Every photo counted so far, each with the chips found on it.
    @Published private(set) var captures: [PhotoCapture] = []
    @Published var qualityPrompt: QualityPrompt?
    /// How the next photo is being taken: laid out and shot from above, or piled and shot from the side.
    @Published var photoAngle: PhotoAngle = .above

    private let photoSessionID: String
    private let client: ChipVisionAPIClient
    private var uploadTask: Task<Void, Never>?

    init(target: CashOutTarget, night: GameNight?, client: ChipVisionAPIClient = .shared) {
        self.nightID = target.nightID
        self.playerID = target.playerID
        self.client = client
        let player = night?.players.first { $0.id == target.playerID }
        isMissing = night == nil || player == nil

        playerName = player?.name ?? ""
        currency = night?.currency ?? Money.defaultCurrencyCode
        let values = night?.denominationsMinor ?? [:]
        valuesMinor = values
        colors = allChipColors.filter { values[$0] != nil }
        totalInMinor = player?.totalInMinor ?? 0
        isEditing = player?.isCashedOut ?? false
        photoSessionID = "\(target.nightID.uuidString)-\(target.playerID.uuidString.prefix(8))"

        if let night, let player, player.buyIns.allSatisfy({ $0.amountMinor == night.defaultBuyInMinor }), let dealt = night.startingCounts {
            dealtChips = dealt.mapValues { $0 * player.buyIns.count }
        } else {
            dealtChips = nil
        }

        // Fixing an earlier cash-out only knows the amount, so start there.
        if let existing = player?.cashOutMinor {
            mode = .amount
            amountText = Money.plain(Double(existing) / 100)
        } else {
            mode = values.isEmpty ? .amount : .chips
            amountText = ""
        }
        counts = Dictionary(uniqueKeysWithValues: values.keys.map { ($0, 0) })
    }

    // MARK: Derived

    func valueMinor(_ color: String) -> Int { valuesMinor[color] ?? 0 }
    func subtotalMinor(_ color: String) -> Int { valueMinor(color) * (counts[color] ?? 0) }
    var chipsMinor: Int { colors.reduce(0) { $0 + subtotalMinor($1) } }

    var amountMinor: Int? {
        guard let amount = Money.parse(amountText), amount >= 0, amount <= 1_000_000 else { return nil }
        return Money.cents(amount)
    }

    /// What this player is cashing out, or nil while the amount isn't valid.
    var cashOutMinor: Int? { mode == .chips ? chipsMinor : amountMinor }
    var netMinor: Int? { cashOutMinor.map { $0 - totalInMinor } }

    // MARK: Photo

    var canAddPhoto: Bool { captures.count < Self.maxPhotos }

    /// A photo has arrived from the camera or library. A poor one is held back so
    /// the person can retake it (or use it anyway); anything else is counted.
    /// `pose` is how the camera was held, when the photo says.
    func receive(_ image: UIImage, pose: CameraPose? = nil) {
        if let issue = PhotoQuality.assess(image)?.issues.first {
            qualityPrompt = QualityPrompt(image: image, pose: pose, angle: photoAngle, issue: issue)
            return
        }
        submitPhoto(image, pose: pose)
    }

    func useHeldPhotoAnyway() {
        guard let prompt = qualityPrompt else { return }
        qualityPrompt = nil
        submitPhoto(prompt.image, pose: prompt.pose)
    }

    func discardHeldPhoto() {
        qualityPrompt = nil
    }

    /// Counts a photo. The first one sets the counts; each further photo adds to
    /// them, for chips that wouldn't fit in one frame.
    @discardableResult
    func submitPhoto(_ image: UIImage, pose: CameraPose? = nil) -> Task<Void, Never> {
        isUploading = true
        photoNotice = nil
        uploadTask?.cancel()
        let prepared = image.preparedForUpload()
        let denominations = valuesMinor.mapValues { Double($0) / 100 }
        let sessionID = photoSessionID
        let angle = photoAngle
        let inPlay = colors
        let task = Task { [weak self] in
            guard let self else { return }
            do {
                let result = try await client.uploadPhoto(
                    image: prepared, denominations: denominations, sessionId: sessionID,
                    angle: angle, pose: angle == .side ? pose : nil, colors: angle == .side ? inPlay : []
                )
                guard !Task.isCancelled else { return }
                apply(result, from: prepared, angle: angle)
            } catch {
                if Task.isCancelled || (error as? URLError)?.code == .cancelled { return }
                // Never block anyone on the counting service: say why, and let them count by hand.
                photoNotice = .failed("Automatic counting wasn't available. \(error.localizedDescription) Count by hand instead.")
            }
            isUploading = false
        }
        uploadTask = task
        return task
    }

    private func apply(_ result: ChipDetectionResult, from image: UIImage, angle: PhotoAngle) {
        if angle == .side && result.view != "side" {
            // An older counting service reads every photo as if from above, which would call a pile one chip.
            photoNotice = .failed("The counting service can't read photos from the side yet. Take the photo from above, or count by hand.")
            return
        }

        let marks: [ChipMark]
        let stacks: [StackMark]
        let found: [String: Int]
        let ignored: Int
        if angle == .side {
            marks = []
            stacks = result.stacks.filter { colors.contains($0.color) }.map(StackMark.init)
            found = stacks.reduce(into: [:]) { $0[$1.color, default: 0] += $1.count }
            ignored = result.stacks.filter { !colors.contains($0.color) }.reduce(0) { $0 + max(0, $1.count) }
        } else {
            marks = result.detections.filter { colors.contains($0.color) }.map(ChipMark.init)
            stacks = []
            found = result.counts
            ignored = result.counts.filter { !colors.contains($0.key) }.values.reduce(0) { $0 + max(0, $1) }
        }

        if captures.isEmpty {
            for color in colors { counts[color] = max(0, found[color] ?? 0) }
        } else {
            for color in colors { counts[color] = (counts[color] ?? 0) + max(0, found[color] ?? 0) }
        }
        captures.append(PhotoCapture(image: image, marks: marks, stacks: stacks, angle: angle))
        photoNotice = .counted(confidence: result.confidence, ignored: ignored)
    }

    func cancelUpload() {
        uploadTask?.cancel()
        uploadTask = nil
        isUploading = false
    }

    /// Forgets the photos and their counts, to start again by photo or by hand.
    func startOver() {
        cancelUpload()
        captures = []
        photoNotice = nil
        for color in colors { counts[color] = 0 }
    }

    // MARK: Fixing what the photo found

    /// Changes the colour of a circled chip; the counts follow.
    func recolor(_ markID: UUID, in captureID: UUID, to color: String) {
        guard colors.contains(color), let (c, m) = locate(markID, in: captureID), captures[c].marks[m].color != color else { return }
        let old = captures[c].marks[m].color
        captures[c].marks[m].color = color
        counts[old] = max(0, (counts[old] ?? 0) - 1)
        counts[color] = (counts[color] ?? 0) + 1
    }

    /// Takes a circle away (it wasn't a chip, or was counted twice); the counts follow.
    func removeMark(_ markID: UUID, in captureID: UUID) {
        guard let (c, m) = locate(markID, in: captureID) else { return }
        let old = captures[c].marks[m].color
        captures[c].marks.remove(at: m)
        counts[old] = max(0, (counts[old] ?? 0) - 1)
    }

    /// Marks a chip the photo missed, where the person tapped (fractions of the photo's width).
    @discardableResult
    func addMark(in captureID: UUID, x: Double, y: Double, color: String) -> UUID? {
        guard colors.contains(color), let c = captures.firstIndex(where: { $0.id == captureID }) else { return nil }
        let mark = ChipMark(x: x, y: y, r: captures[c].typicalRadius, color: color)
        captures[c].marks.append(mark)
        counts[color] = (counts[color] ?? 0) + 1
        return mark.id
    }

    // MARK: Fixing the piles

    /// Sets how many chips a pile holds; the counts follow by the difference.
    func setStackCount(_ stackID: UUID, in captureID: UUID, to newCount: Int) {
        guard let (c, s) = locateStack(stackID, in: captureID) else { return }
        let clamped = min(max(newCount, 1), StackMark.largest)
        let change = clamped - captures[c].stacks[s].count
        guard change != 0 else { return }
        let color = captures[c].stacks[s].color
        captures[c].stacks[s].count = clamped
        counts[color] = max(0, (counts[color] ?? 0) + change)
    }

    /// Changes a pile's colour; all of its chips move to the new colour's count.
    func recolorStack(_ stackID: UUID, in captureID: UUID, to color: String) {
        guard colors.contains(color), let (c, s) = locateStack(stackID, in: captureID), captures[c].stacks[s].color != color else { return }
        let old = captures[c].stacks[s].color
        let chips = captures[c].stacks[s].count
        captures[c].stacks[s].color = color
        counts[old] = max(0, (counts[old] ?? 0) - chips)
        counts[color] = (counts[color] ?? 0) + chips
    }

    /// Takes a pile away (it wasn't one); its chips come off the counts.
    func removeStack(_ stackID: UUID, in captureID: UUID) {
        guard let (c, s) = locateStack(stackID, in: captureID) else { return }
        let stack = captures[c].stacks.remove(at: s)
        counts[stack.color] = max(0, (counts[stack.color] ?? 0) - stack.count)
    }

    /// Marks a pile the photo missed, one chip tall, where the person tapped (fractions of the photo's width).
    @discardableResult
    func addStack(in captureID: UUID, x: Double, y: Double, color: String) -> UUID? {
        guard colors.contains(color), let c = captures.firstIndex(where: { $0.id == captureID }) else { return nil }
        let size = captures[c].typicalStackSize
        let stack = StackMark(x: x, y: y, w: size.width, h: size.height, color: color, count: 1)
        captures[c].stacks.append(stack)
        counts[color] = (counts[color] ?? 0) + 1
        return stack.id
    }

    private func locateStack(_ stackID: UUID, in captureID: UUID) -> (capture: Int, stack: Int)? {
        guard let c = captures.firstIndex(where: { $0.id == captureID }),
              let s = captures[c].stacks.firstIndex(where: { $0.id == stackID }) else { return nil }
        return (c, s)
    }

    private func locate(_ markID: UUID, in captureID: UUID) -> (capture: Int, mark: Int)? {
        guard let c = captures.firstIndex(where: { $0.id == captureID }),
              let m = captures[c].marks.firstIndex(where: { $0.id == markID }) else { return nil }
        return (c, m)
    }

    // MARK: Saving

    /// Records the cash-out. False if the amount isn't valid yet.
    func save(into store: NightStore, now: Date = Date()) -> Bool {
        guard let cents = cashOutMinor else { return false }
        store.mutate(nightID) { $0.cashOut(playerID, amountMinor: cents, at: now) }
        return true
    }
}

struct ReviewCountsView: View {
    @EnvironmentObject private var coordinator: NavigationCoordinator
    @EnvironmentObject private var store: NightStore
    @StateObject private var viewModel: CashOutViewModel
    @StateObject private var connectivity = ConnectivityMonitor()

    @State private var showsCamera = false
    @State private var showsLibrary = false
    @State private var reviewing: ReviewTarget?
    @State private var cameraStatus = CameraAccess.status
    @Environment(\.scenePhase) private var scenePhase

    private struct ReviewTarget: Identifiable { let id: UUID }

    init(target: CashOutTarget, night: GameNight?) {
        _viewModel = StateObject(wrappedValue: CashOutViewModel(target: target, night: night))
    }

    private var photosUnavailableReason: String? {
        if !APIConfig.isConfigured {
            return "Photo counting isn't set up in this build. Count by hand instead."
        }
        if !connectivity.isOnline {
            return "You're offline. Photo counting needs a connection — you can still count by hand."
        }
        return nil
    }

    var body: some View {
        Group {
            if viewModel.isMissing {
                EmptyState(
                    icon: "questionmark.folder",
                    title: "This player isn't here any more",
                    message: "The night may have changed on another device.",
                    actionTitle: "Back"
                ) { coordinator.pop() }
                .padding(Spacing.gutter)
                .pokerReadableWidth()
            } else {
                content
            }
        }
        .background(PokerBackground())
        .navigationTitle(viewModel.playerName.isEmpty ? "Cash out" : "Cash out · \(viewModel.playerName)")
        .navigationBarTitleDisplayMode(.inline)
        .fullScreenCover(isPresented: $showsCamera) {
            CameraScreen(angle: viewModel.photoAngle, onCapture: { viewModel.receive($0, pose: $1) })
        }
        .sheet(isPresented: $showsLibrary) {
            PhotoLibraryPicker(onPick: { viewModel.receive($0, pose: $1) })
        }
        .sheet(item: $reviewing) { target in
            PhotoReviewView(viewModel: viewModel, captureID: target.id)
        }
        .confirmationDialog(
            "This photo may not count well",
            isPresented: Binding(get: { viewModel.qualityPrompt != nil }, set: { if !$0 { viewModel.discardHeldPhoto() } }),
            titleVisibility: .visible,
            presenting: viewModel.qualityPrompt
        ) { _ in
            Button("Retake photo") {
                viewModel.discardHeldPhoto()
                Task {
                    // Let this dialog finish closing before the camera opens over it.
                    try? await Task.sleep(nanoseconds: 400_000_000)
                    retake()
                }
            }
            .accessibilityIdentifier("cashout.quality.retake")
            Button("Use it anyway") { viewModel.useHeldPhotoAnyway() }
                .accessibilityIdentifier("cashout.quality.useAnyway")
            Button("Cancel", role: .cancel) { viewModel.discardHeldPhoto() }
        } message: { prompt in
            Text(prompt.issue.message(for: prompt.angle))
        }
        // Coming back from Settings after allowing the camera.
        .onChange(of: scenePhase) { phase in
            if phase == .active { cameraStatus = CameraAccess.status }
        }
        // The counting service sleeps when idle; waking it now means the photo isn't the thing that waits.
        .task { Prewarm.countingService() }
        .onDisappear {
            if viewModel.isUploading { viewModel.cancelUpload() }
        }
    }

    // MARK: Content

    private var content: some View {
        ScrollView {
            VStack(spacing: Spacing.lg) {
                StepIndicator(current: 3)

                Picker("How to cash out", selection: $viewModel.mode) {
                    ForEach(CashOutViewModel.Mode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("cashout.mode")

                switch viewModel.mode {
                case .chips:
                    photoCard
                    photoBanner
                    ForEach(viewModel.colors, id: \.self) { color in
                        countCard(color)
                    }
                case .amount:
                    amountCard
                }

                totalsCard
            }
            .padding(.horizontal, Spacing.gutter)
            .padding(.vertical, Spacing.lg)
            .pokerReadableWidth()
        }
        .scrollDismissesKeyboard(.interactively)
        .keyboardDoneButton()
        .safeAreaInset(edge: .bottom, spacing: 0) {
            PokerButton(
                title: viewModel.isEditing ? "Save changes" : "Save cash-out",
                isEnabled: viewModel.cashOutMinor != nil && !viewModel.isUploading
            ) {
                if viewModel.save(into: store) {
                    Haptics.success()
                    coordinator.pop()
                }
            }
            .accessibilityIdentifier("cashout.save")
            .pokerBottomBar()
        }
    }

    // MARK: Photo

    private var photoCard: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            SectionHeader(title: viewModel.captures.isEmpty ? "Count from a photo" : "Photos")

            if viewModel.isUploading {
                HStack(spacing: Spacing.md) {
                    ProgressView().tint(.pokerGoldLight)
                    Text("Counting the chips…")
                        .font(.pokerCallout)
                        .foregroundStyle(.pokerTextPrimary)
                }
                .accessibilityElement(children: .combine)

                PokerButton(title: "Skip and count by hand", kind: .quiet) { viewModel.cancelUpload() }
                    .accessibilityIdentifier("cashout.skipUpload")
            } else {
                let photosAvailable = photosUnavailableReason == nil
                let cameraBlocked = cameraStatus == .denied || cameraStatus == .restricted || cameraStatus == .unavailable
                let canTakePhoto = photosAvailable && !cameraBlocked

                if !viewModel.captures.isEmpty {
                    capturesStrip
                }

                if viewModel.canAddPhoto {
                    Picker("How the chips are laid out", selection: $viewModel.photoAngle) {
                        ForEach(PhotoAngle.allCases) { angle in
                            Text(angle.title).tag(angle)
                        }
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("cashout.photoAngle")
                }

                Text(Self.photoAdvice(for: viewModel.photoAngle, hasPhotos: !viewModel.captures.isEmpty))
                    .font(.pokerFootnote)
                    .foregroundStyle(.pokerTextSecondary)
                    .accessibilityIdentifier("cashout.photoAdvice")

                if let reason = photosUnavailableReason {
                    InlineBanner(kind: .info, message: reason)
                } else if let message = CameraAccess.explanation(for: cameraStatus) {
                    InlineBanner(kind: .warning, message: message, actionTitle: cameraStatus == .denied ? "Open Settings" : nil) {
                        CameraAccess.openSettings()
                    }
                }

                if viewModel.canAddPhoto {
                    let take = PokerButton(
                        title: viewModel.captures.isEmpty ? "Take photo" : "Add photo",
                        systemImage: "camera.fill",
                        kind: canTakePhoto && viewModel.captures.isEmpty ? .primary : .secondary,
                        isEnabled: canTakePhoto,
                        action: takePhoto
                    )
                    .accessibilityIdentifier("cashout.takePhoto")
                    let choose = PokerButton(
                        title: "Choose",
                        systemImage: "photo.on.rectangle",
                        kind: .secondary,
                        isEnabled: photosAvailable
                    ) { showsLibrary = true }
                    .accessibilityIdentifier("cashout.choosePhoto")

                    // Side by side while the words fit; one above the other at large text sizes.
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: Spacing.md) { take; choose }
                        VStack(spacing: Spacing.md) { take; choose }
                    }
                } else {
                    Text("That's the most photos one cash-out can use. Fix any chips that are wrong, or start over.")
                        .font(.pokerFootnote)
                        .foregroundStyle(.pokerTextTertiary)
                }

                #if DEBUG
                if AppEnvironment.isUITest {
                    // Stands in for the camera and library, which a UI test can't drive.
                    PokerButton(title: "Use a sample photo", kind: .quiet) {
                        if viewModel.photoAngle == .side {
                            viewModel.receive(UITestSamplePhoto.sideImage(), pose: UITestSamplePhoto.samplePose)
                        } else {
                            viewModel.receive(UITestSamplePhoto.image())
                        }
                    }
                    .accessibilityIdentifier("cashout.samplePhoto")
                    PokerButton(title: "Use a blurry photo", kind: .quiet) { viewModel.receive(UITestSamplePhoto.blurryImage()) }
                        .accessibilityIdentifier("cashout.blurryPhoto")
                }
                #endif

                if !viewModel.captures.isEmpty {
                    PokerButton(title: "Start over", kind: .quiet) {
                        viewModel.startOver()
                        Haptics.selection()
                    }
                    .accessibilityIdentifier("cashout.startOver")
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .pokerCard()
    }

    /// The photos so far, each opening a closer look at the chips found on it.
    private var capturesStrip: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Spacing.sm) {
                    ForEach(Array(viewModel.captures.enumerated()), id: \.element.id) { index, capture in
                        thumbnail(capture, index: index)
                    }
                }
            }
            let chips = viewModel.colors.reduce(0) { $0 + (viewModel.counts[$1] ?? 0) }
            Text("\(viewModel.captures.count) photo\(viewModel.captures.count == 1 ? "" : "s") · \(chips) chip\(chips == 1 ? "" : "s") counted")
                .font(.pokerNumeric(.footnote, weight: .semibold))
                .foregroundStyle(.pokerTextPrimary)
                .accessibilityIdentifier("cashout.photoSummary")
        }
    }

    @ViewBuilder
    private func thumbnail(_ capture: PhotoCapture, index: Int) -> some View {
        let picture = Image(uiImage: capture.image)
            .resizable()
            .scaledToFill()
            .frame(width: 88, height: 66)
            .clipShape(RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Radius.control, style: .continuous).stroke(Color.pokerStroke, lineWidth: 1))
        if capture.isEmpty {
            // An older server doesn't say where the chips are; there is nothing to check.
            picture.accessibilityLabel("Photo \(index + 1)")
        } else {
            Button {
                reviewing = ReviewTarget(id: capture.id)
            } label: {
                picture
                    .overlay(alignment: .bottomTrailing) {
                        Text("\(capture.chipCount)")
                            .font(.pokerNumeric(.caption2))
                            .foregroundStyle(.black)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Color.pokerGoldLight))
                            .padding(4)
                    }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Photo \(index + 1), \(capture.chipCount) chips found")
            .accessibilityHint(capture.angle == .side ? "Check each pile" : "Check each chip")
            .accessibilityIdentifier("cashout.photo.\(index)")
        }
    }

    @ViewBuilder
    private var photoBanner: some View {
        switch viewModel.photoNotice {
        case .counted(let confidence, let ignored):
            InlineBanner(kind: .info, message: Self.message(forConfidence: confidence, ignored: ignored, angle: viewModel.captures.last?.angle ?? .above))
                .accessibilityIdentifier("cashout.photoNotice")
        case .failed(let message):
            InlineBanner(kind: .warning, message: message)
        case nil:
            EmptyView()
        }
    }

    /// What to do before the photo is taken, for how the chips are laid out.
    static func photoAdvice(for angle: PhotoAngle, hasPhotos: Bool) -> String {
        if hasPhotos {
            return "Tap a photo to check what was found. Too many chips for one photo? Add another with the rest — put each chip in only one photo and the counts add up."
        }
        switch angle {
        case .above:
            return "Lay the chips flat on a plain surface and hold your phone directly overhead. You can correct every count afterwards."
        case .side:
            return "Stand each colour in its own pile, in a row a hand apart on a plain surface. Hold your phone low, level with the piles, about a hand's width back, in good light. Counting from the side is an estimate: you can correct every pile afterwards."
        }
    }

    private static func message(forConfidence confidence: String, ignored: Int, angle: PhotoAngle) -> String {
        var text: String
        if angle == .side {
            // Counting piles from the side is never better than an estimate, whatever the service says.
            text = "Counted each pile from your photo. This is the hardest way to read chips, so please check every pile, and every colour, before you save."
        } else {
            switch confidence {
            case "high": text = "Counted from your photo. Check each colour before you save."
            case "medium": text = "Counted from your photo, but some chips may be off. Please check each colour."
            default: text = "The photo was hard to read — stacked or overlapping chips — so these counts may be off. Please correct them."
            }
        }
        if ignored > 0 {
            text += " \(ignored) chip\(ignored == 1 ? "" : "s") in colours you aren't using tonight \(ignored == 1 ? "was" : "were") left out."
        }
        return text
    }

    /// Back to the camera after a poor photo, or the library where there is no camera to use.
    private func retake() {
        cameraStatus = CameraAccess.status
        switch cameraStatus {
        case .ready, .needsPermission: takePhoto()
        case .denied, .restricted, .unavailable: showsLibrary = true
        }
    }

    private func takePhoto() {
        cameraStatus = CameraAccess.status
        switch cameraStatus {
        case .ready:
            showsCamera = true
        case .needsPermission:
            Task {
                let granted = await CameraAccess.requestAccess()
                cameraStatus = CameraAccess.status
                if granted { showsCamera = true }
            }
        case .denied, .restricted, .unavailable:
            // The button is disabled in these states; this is only a backstop.
            Haptics.warning()
        }
    }

    // MARK: Counting

    /// One colour. The chip, its name and the stepper share a line when the
    /// screen is wide enough, so five colours fit on one screen; narrower
    /// screens and larger text sizes stack them instead.
    private func countCard(_ color: String) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: Spacing.md) {
                    chipAndName(color)
                    Spacer(minLength: Spacing.sm)
                    stepper(for: color, isCompact: true)
                }
                VStack(alignment: .leading, spacing: Spacing.md) {
                    chipAndName(color)
                    stepper(for: color, isCompact: false)
                }
            }

            HStack {
                if let dealt = viewModel.dealtChips?[color] {
                    Text("Started with \(dealt)")
                        .font(.pokerFootnote)
                        .foregroundStyle(.pokerTextTertiary)
                }
                Spacer(minLength: Spacing.sm)
                MoneyText(cents: viewModel.subtotalMinor(color), font: .pokerNumeric(.subheadline), color: .pokerGoldLight)
            }
        }
        .pokerCard(padding: Spacing.md)
    }

    private func chipAndName(_ color: String) -> some View {
        HStack(spacing: Spacing.md) {
            ChipView(color: color, size: 40)
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text(color)
                    .font(.pokerHeadline)
                    .foregroundStyle(.pokerTextPrimary)
                Text("\(Money.format(cents: viewModel.valueMinor(color), currencyCode: viewModel.currency)) each")
                    .font(.pokerFootnote)
                    .foregroundStyle(.pokerTextSecondary)
            }
        }
    }

    private func stepper(for color: String, isCompact: Bool) -> some View {
        StepperField(
            value: Binding(
                get: { viewModel.counts[color] ?? 0 },
                set: { viewModel.counts[color] = $0 }
            ),
            range: 0...9_999,
            accessibilityLabel: "\(color) chips",
            identifier: "review.count.\(color)",
            isCompact: isCompact
        )
    }

    // MARK: Amount

    private var amountCard: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            SectionHeader(title: "Cash-out amount")

            HStack(spacing: Spacing.sm) {
                Text(Money.currencySymbol(currencyCode: viewModel.currency))
                    .font(.pokerNumeric(.title2))
                    .foregroundStyle(Color.pokerGoldLight)
                    .accessibilityHidden(true)
                TextField("0.00", text: $viewModel.amountText)
                    .keyboardType(.decimalPad)
                    .font(.pokerNumeric(.title2))
                    .accessibilityLabel("Cash-out amount")
                    .accessibilityIdentifier("cashout.amount")
            }
            .pokerTextField(isError: !viewModel.amountText.isEmpty && viewModel.amountMinor == nil)

            if !viewModel.amountText.isEmpty && viewModel.amountMinor == nil {
                Label("Enter an amount like \(Money.plain(25.5)).", systemImage: "exclamationmark.circle.fill")
                    .font(.pokerFootnote)
                    .foregroundStyle(.pokerNegative)
            } else {
                Text("Use this when the chips are already counted, or this player is taking a different amount.")
                    .font(.pokerFootnote)
                    .foregroundStyle(.pokerTextTertiary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .pokerCard()
    }

    // MARK: Totals

    private var totalsCard: some View {
        let cashOut = viewModel.cashOutMinor
        let net = viewModel.netMinor ?? 0
        let tone: Color = net == 0 ? .pokerTextPrimary : (net > 0 ? .pokerPositive : .pokerNegative)
        let label = net == 0 ? "Even" : (net > 0 ? "Up" : "Down")

        return VStack(spacing: Spacing.md) {
            HStack {
                Text("Cash-out").font(.pokerHeadline).foregroundStyle(.pokerTextPrimary)
                Spacer()
                if let cashOut {
                    MoneyText(cents: cashOut, font: .pokerNumeric(.title3), color: .pokerGoldLight)
                } else {
                    Text("—").font(.pokerNumeric(.title3)).foregroundStyle(.pokerTextTertiary)
                }
            }
            Divider().overlay(Color.white.opacity(0.12))
            HStack {
                Text("Money in").foregroundStyle(.pokerTextSecondary)
                Spacer()
                MoneyText(cents: viewModel.totalInMinor, font: .pokerNumeric(.body), color: .pokerTextPrimary)
            }
            if cashOut != nil {
                HStack {
                    Text(label).foregroundStyle(.pokerTextSecondary)
                    Spacer()
                    MoneyText(cents: abs(net), font: .pokerNumeric(.body), color: tone)
                }
            }
        }
        .pokerCard()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(totalsSpoken(cashOut: cashOut, net: net, label: label))
        .accessibilityIdentifier("review.totals")
    }

    private func totalsSpoken(cashOut: Int?, net: Int, label: String) -> String {
        guard let cashOut else { return "Enter a valid amount." }
        return "Cash-out \(Money.spoken(cents: cashOut)). Money in \(Money.spoken(cents: viewModel.totalInMinor)). \(label) \(Money.spoken(cents: abs(net)))."
    }
}

struct ReviewCountsView_Previews: PreviewProvider {
    static var previews: some View {
        let night = GameNight.start(
            buyInMinor: 5_000, playerNames: ["Pranav", "Sam"], colors: ["White", "Red", "Blue", "Green", "Black"],
            denominationsMinor: ["White": 25, "Red": 100, "Blue": 200, "Green": 500, "Black": 1_000],
            startingCounts: ["White": 20, "Red": 10, "Blue": 5, "Green": 2, "Black": 1]
        )
        return NavigationStack {
            ReviewCountsView(target: CashOutTarget(nightID: night.id, playerID: night.players[0].id), night: night)
                .environmentObject(NavigationCoordinator())
                .environmentObject(NightStore(repository: MemoryNightRepository(nights: [night])))
        }
    }
}
