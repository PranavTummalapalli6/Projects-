//
//  PhotoReviewView.swift
//  PokerChipApp
//
//  The photo with a circle on every chip that was counted (or, for a photo taken
//  from the side, a box round every pile with the number of chips in it). A wrong
//  colour is one tap to change, a circle that isn't a chip is one tap to remove, a
//  chip the photo missed is one tap to add, and a pile with the wrong number is a
//  step up or down — and the cash-out counts move with each. The steppers on the
//  cash-out screen stay the way to count without the picture.
//

import SwiftUI

struct PhotoReviewView: View {
    @ObservedObject var viewModel: CashOutViewModel
    let captureID: UUID

    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiateWithoutColor
    @AppStorage(PrefKey.colorBlindChips) private var colorBlindChips = false

    @State private var selected: UUID?
    @State private var isAdding = false
    @State private var addColor: String
    @State private var zoom = 1

    init(viewModel: CashOutViewModel, captureID: UUID) {
        self.viewModel = viewModel
        self.captureID = captureID
        _addColor = State(initialValue: viewModel.colors.first ?? "White")
    }

    private var capture: PhotoCapture? { viewModel.captures.first { $0.id == captureID } }

    var body: some View {
        NavigationStack {
            Group {
                if let capture {
                    content(capture)
                } else {
                    EmptyState(
                        icon: "photo",
                        title: "This photo is gone",
                        message: "Start over from the cash-out screen to take it again.",
                        actionTitle: "Close"
                    ) { dismiss() }
                    .padding(Spacing.gutter)
                }
            }
            .background(PokerBackground())
            .navigationTitle("Check the photo")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .accessibilityIdentifier("photoReview.done")
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: Layout

    private func content(_ capture: PhotoCapture) -> some View {
        GeometryReader { screen in
            VStack(spacing: 0) {
                GeometryReader { outer in
                    ScrollView([.horizontal, .vertical], showsIndicators: zoom > 1) {
                        photo(capture, width: outer.size.width * CGFloat(zoom))
                    }
                }
                .frame(maxHeight: .infinity)

                if dynamicTypeSize.isAccessibilitySize {
                    // Large text needs more room than is left under the photo, so the controls scroll
                    // instead of being cut off.
                    ScrollView { controls(capture) }
                        .frame(height: screen.size.height * 0.55)
                        .background(.ultraThinMaterial)
                } else {
                    controls(capture)
                        .background(.ultraThinMaterial)
                }
            }
        }
    }

    private func photo(_ capture: PhotoCapture, width: CGFloat) -> some View {
        Image(uiImage: capture.image)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: width)
            // The picture says nothing the rings don't: they are what VoiceOver gets.
            .accessibilityHidden(true)
            .overlay(alignment: .topLeading) {
                ZStack(alignment: .topLeading) {
                    ForEach(Array(capture.marks.enumerated()), id: \.element.id) { index, mark in
                        markView(mark, index: index, count: capture.marks.count, width: width)
                    }
                    ForEach(Array(capture.stacks.enumerated()), id: \.element.id) { index, stack in
                        stackView(stack, index: index, count: capture.stacks.count, width: width)
                    }
                    if isAdding {
                        // Catches the tap that says where the missed chip is.
                        Color.clear
                            .contentShape(Rectangle())
                            .gesture(
                                DragGesture(minimumDistance: 0)
                                    .onEnded { value in add(at: value.location, width: width) }
                            )
                            .accessibilityHidden(true)
                    }
                }
                .frame(width: width, height: width * capture.aspectRatio)
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel(capture.angle == .side
                ? "Your photo, with a box round each of the \(capture.stacks.count) piles found"
                : "Your photo, with a ring on each of the \(capture.marks.count) chips found")
    }

    private func markView(_ mark: ChipMark, index: Int, count: Int, width: CGFloat) -> some View {
        let diameter = max(14, mark.r * 2 * width)
        let hit = max(diameter, Spacing.minTapTarget)
        let isSelected = selected == mark.id
        return ring(mark, diameter: diameter, isSelected: isSelected)
            .frame(width: hit, height: hit)
            .contentShape(Circle())
            .position(x: mark.x * width, y: mark.y * width)
            .onTapGesture {
                guard !isAdding else { return }
                selected = isSelected ? nil : mark.id
                Haptics.selection()
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(mark.color) chip, \(index + 1) of \(count)")
            .accessibilityValue(isSelected ? "Selected" : "")
            .accessibilityAddTraits(.isButton)
            .accessibilityIdentifier("photoReview.mark.\(index)")
    }

    /// A box round a pile, in the pile's colour with a light edge, and the number of chips in it.
    private func stackView(_ stack: StackMark, index: Int, count: Int, width: CGFloat) -> some View {
        let boxWidth = max(28, stack.w * width)
        let boxHeight = max(28, stack.h * width)
        let isSelected = selected == stack.id
        let showsLetter = differentiateWithoutColor || colorBlindChips
        let badge = Text(showsLetter ? "\(ChipPalette.initial(stack.color)) \(stack.count)" : "\(stack.count)")
            .font(.system(size: 15, weight: .heavy, design: .rounded).monospacedDigit())
            .foregroundStyle(.black)
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(Capsule().fill(isSelected ? Color.pokerGold : Color.pokerGoldLight))
            .shadow(color: .black.opacity(0.5), radius: 2)
        return ZStack {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.white.opacity(0.92), lineWidth: isSelected ? 7 : 5)
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(isSelected ? Color.pokerGold : ChipPalette.fill(stack.color), lineWidth: isSelected ? 4 : 3)
                .padding(isSelected ? 1.5 : 1)
        }
        .frame(width: boxWidth, height: boxHeight)
        .shadow(color: .black.opacity(0.5), radius: 2)
        .overlay(alignment: .top) { badge.offset(y: -12) }
        .frame(width: max(boxWidth, Spacing.minTapTarget), height: max(boxHeight, Spacing.minTapTarget))
        .contentShape(Rectangle())
        .rotationEffect(.degrees(stack.angle))
        .position(x: stack.x * width, y: stack.y * width)
        .onTapGesture {
            guard !isAdding else { return }
            selected = isSelected ? nil : stack.id
            Haptics.selection()
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(stack.color) pile, \(stack.count) \(stack.count == 1 ? "chip" : "chips"), \(index + 1) of \(count)")
        .accessibilityValue(isSelected ? "Selected" : "")
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("photoReview.stack.\(index)")
    }

    /// A ring in the chip's colour with a light edge round it, so it shows on felt of any colour.
    private func ring(_ mark: ChipMark, diameter: CGFloat, isSelected: Bool) -> some View {
        ZStack {
            Circle().strokeBorder(Color.white.opacity(0.92), lineWidth: isSelected ? 7 : 5)
            Circle().strokeBorder(isSelected ? Color.pokerGold : ChipPalette.fill(mark.color), lineWidth: isSelected ? 4 : 3)
                .padding(isSelected ? 1.5 : 1)
            if differentiateWithoutColor || colorBlindChips {
                Text(ChipPalette.initial(mark.color))
                    .font(.system(size: max(9, diameter * 0.34), weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                    .shadow(color: .black, radius: 2)
            }
        }
        .frame(width: diameter, height: diameter)
        .shadow(color: .black.opacity(0.5), radius: 2)
    }

    // MARK: Controls

    private func controls(_ capture: PhotoCapture) -> some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            legend(capture)

            if let mark = capture.marks.first(where: { $0.id == selected }) {
                fixPanel(mark)
            } else if let stack = capture.stacks.first(where: { $0.id == selected }) {
                stackPanel(stack)
            } else if isAdding {
                addPanel(for: capture)
            } else {
                let hint = Text(capture.isEmpty
                                ? "No chips were found in this photo. Add them, or count by hand."
                                : (capture.angle == .side
                                    ? "Tap a box to change how many chips are in that pile, or its colour. A pile counted from the side is an estimate."
                                    : "Tap a circle to change its colour or remove it."))
                    .font(.pokerFootnote)
                    .foregroundStyle(.pokerTextSecondary)
                let zoomPicker = Picker("Zoom", selection: $zoom) {
                    Text("1×").tag(1)
                    Text("2×").tag(2)
                    Text("3×").tag(3)
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("photoReview.zoom")
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .center, spacing: Spacing.md) {
                        hint
                        Spacer(minLength: Spacing.sm)
                        zoomPicker.frame(width: 150)
                    }
                    VStack(alignment: .leading, spacing: Spacing.sm) {
                        hint
                        zoomPicker
                    }
                }
                PokerButton(title: capture.angle == .side ? "A pile is missing — add it" : "A chip is missing — add it", systemImage: "plus.circle", kind: .secondary) {
                    isAdding = true
                    selected = nil
                }
                .accessibilityIdentifier("photoReview.addMode")
            }
        }
        .padding(Spacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func legend(_ capture: PhotoCapture) -> some View {
        let tally = capture.tally
        let counts = HStack(spacing: Spacing.md) {
            ForEach(viewModel.colors, id: \.self) { color in
                HStack(spacing: Spacing.xs) {
                    ChipView(color: color, size: 22)
                    Text("\(tally[color] ?? 0)")
                        .font(.pokerNumeric(.subheadline))
                        .foregroundStyle(.pokerTextPrimary)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(color) chips in this photo")
                .accessibilityValue("\(tally[color] ?? 0)")
                .accessibilityIdentifier("photoReview.legend.\(color)")
            }
        }
        let total = Text("\(capture.chipCount) in this photo")
            .font(.pokerFootnote)
            .foregroundStyle(.pokerTextSecondary)
        // Side by side when there is room; the total goes underneath on a narrow phone. Both keep their own
        // width: left to share the row, the stack hands the counts less than they need and the numbers are
        // cut down to slivers (it did, on the largest phones, where this layout fits).
        return ViewThatFits(in: .horizontal) {
            HStack(spacing: Spacing.md) {
                counts.fixedSize(horizontal: true, vertical: false)
                Spacer(minLength: Spacing.sm)
                total.fixedSize(horizontal: true, vertical: false)
            }
            VStack(alignment: .leading, spacing: Spacing.xs) {
                ScrollView(.horizontal, showsIndicators: false) { counts }
                total
            }
        }
    }

    private func fixPanel(_ mark: ChipMark) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text("This chip is…")
                .font(.pokerHeadline)
                .foregroundStyle(.pokerTextPrimary)
            colorRow(selection: mark.color) { color in
                viewModel.recolor(mark.id, in: captureID, to: color)
                Haptics.selection()
            }
            PokerButton(title: "Not a chip — remove it", systemImage: "trash", kind: .secondary) {
                viewModel.removeMark(mark.id, in: captureID)
                selected = nil
                Haptics.selection()
            }
            .accessibilityIdentifier("photoReview.remove")
            PokerButton(title: "Done with this chip", kind: .quiet) { selected = nil }
                .accessibilityIdentifier("photoReview.deselect")
        }
    }

    private func stackPanel(_ stack: StackMark) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text("This pile has…")
                .font(.pokerHeadline)
                .foregroundStyle(.pokerTextPrimary)
            HStack(spacing: Spacing.md) {
                StepperField(
                    value: Binding(
                        get: { stack.count },
                        set: { viewModel.setStackCount(stack.id, in: captureID, to: $0) }
                    ),
                    range: 1...StackMark.largest,
                    accessibilityLabel: "\(stack.color) chips in this pile",
                    identifier: "photoReview.stackCount",
                    isCompact: true
                )
                Text(stack.count == 1 ? "chip" : "chips")
                    .font(.pokerCallout)
                    .foregroundStyle(.pokerTextSecondary)
            }
            colorRow(selection: stack.color) { color in
                viewModel.recolorStack(stack.id, in: captureID, to: color)
                Haptics.selection()
            }
            PokerButton(title: "Not a pile — remove it", systemImage: "trash", kind: .secondary) {
                viewModel.removeStack(stack.id, in: captureID)
                selected = nil
                Haptics.selection()
            }
            .accessibilityIdentifier("photoReview.removeStack")
            PokerButton(title: "Done with this pile", kind: .quiet) { selected = nil }
                .accessibilityIdentifier("photoReview.deselect")
        }
    }

    private func addPanel(for capture: PhotoCapture) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text(capture.angle == .side ? "Tap the photo where the pile is" : "Tap the photo where the chip is")
                .font(.pokerHeadline)
                .foregroundStyle(.pokerTextPrimary)
            colorRow(selection: addColor) { color in
                addColor = color
                Haptics.selection()
            }
            PokerButton(title: "Finished adding", kind: .quiet) { isAdding = false }
                .accessibilityIdentifier("photoReview.addDone")
        }
    }

    private func colorRow(selection: String, choose: @escaping (String) -> Void) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Spacing.sm) {
                ForEach(viewModel.colors, id: \.self) { color in
                    Button {
                        choose(color)
                    } label: {
                        ChipView(color: color, size: 40)
                            .padding(4)
                            .background(Circle().stroke(color == selection ? Color.pokerGold : Color.clear, lineWidth: 3))
                            .frame(minWidth: Spacing.minTapTarget, minHeight: Spacing.minTapTarget)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(color)")
                    .accessibilityAddTraits(color == selection ? .isSelected : [])
                    .accessibilityIdentifier("photoReview.color.\(color)")
                }
            }
        }
    }

    // MARK: Actions

    private func add(at location: CGPoint, width: CGFloat) {
        guard width > 0 else { return }
        let x = Double(location.x / width), y = Double(location.y / width)
        if capture?.angle == .side {
            viewModel.addStack(in: captureID, x: x, y: y, color: addColor)
        } else {
            viewModel.addMark(in: captureID, x: x, y: y, color: addColor)
        }
        Haptics.selection()
    }
}
