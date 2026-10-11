//
//  Components.swift
//  PokerChipApp
//
//  Reusable building blocks: section headers, list rows, stat tiles, banners,
//  empty states, skeletons, steppers, and money/time text.
//

import SwiftUI

// MARK: - Headers and rows

struct SectionHeader: View {
    let title: String

    var body: some View {
        Text(title.uppercased())
            .font(.pokerCaption)
            .tracking(0.8)
            .foregroundStyle(Color.pokerPurpleLight)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityAddTraits(.isHeader)
    }
}

/// A tappable card row: icon, title, subtitle, chevron. Wrap it in a
/// `NavigationLink` or `Button` — it only draws the content.
struct ListRow: View {
    let icon: String
    let title: String
    var subtitle: String? = nil
    var showsChevron = true

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var iconView: some View {
        Image(systemName: icon)
            .font(.title3)
            .foregroundStyle(Color.pokerGold)
            .frame(width: 40, height: 40)
            .background(Color.pokerGold.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
            .accessibilityHidden(true)
    }

    private var chevron: some View {
        Image(systemName: "chevron.right")
            .font(.caption.weight(.bold))
            .foregroundStyle(.pokerTextTertiary)
            .accessibilityHidden(true)
    }

    private var words: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text(title)
                .font(.pokerHeadline)
                .foregroundStyle(.pokerTextPrimary)
                .multilineTextAlignment(.leading)
            if let subtitle {
                Text(subtitle)
                    .font(.pokerFootnote)
                    .foregroundStyle(.pokerTextSecondary)
                    .multilineTextAlignment(.leading)
            }
        }
    }

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                // The words get the whole width; the icon and chevron share the line above them.
                VStack(alignment: .leading, spacing: Spacing.md) {
                    HStack {
                        iconView
                        Spacer(minLength: Spacing.sm)
                        if showsChevron { chevron }
                    }
                    words
                }
            } else {
                HStack(spacing: Spacing.lg) {
                    iconView
                    words
                    Spacer(minLength: Spacing.sm)
                    if showsChevron { chevron }
                }
            }
        }
        .frame(minHeight: Spacing.minTapTarget)
        .pokerCard()
        .contentShape(Rectangle())
    }
}

struct StatTile: View {
    let label: String
    let value: String
    var valueColor: Color = .pokerTextPrimary
    var spokenValue: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text(label.uppercased())
                .font(.pokerCaption)
                .tracking(0.6)
                .foregroundStyle(.pokerTextTertiary)
            Text(value)
                .font(.pokerNumeric(.title3))
                .foregroundStyle(valueColor)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .pokerCard(padding: Spacing.md)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue(spokenValue ?? value)
    }
}

// MARK: - Flow

/// "Step 2 of 5 · Chips" — shows where a person is in starting and finishing a
/// game, so a long linear flow never feels like it might go on forever.
struct StepIndicator: View {
    static let steps = ["Buy-in", "Chips", "Play", "Count", "Settle"]

    /// Zero-based index into `steps`.
    let current: Int

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack(spacing: Spacing.xs) {
                ForEach(Self.steps.indices, id: \.self) { index in
                    Capsule()
                        .fill(index <= current ? Color.pokerGold : Color.white.opacity(0.16))
                        .frame(height: 4)
                }
            }
            Text("Step \(current + 1) of \(Self.steps.count) · \(Self.steps[current])")
                .font(.pokerCaption)
                .foregroundStyle(.pokerTextSecondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Step \(current + 1) of \(Self.steps.count), \(Self.steps[current])")
    }
}

// MARK: - Feedback

struct InlineBanner: View {
    enum Kind {
        case info, success, warning, error

        var icon: String {
            switch self {
            case .info: return "info.circle.fill"
            case .success: return "checkmark.circle.fill"
            case .warning: return "exclamationmark.triangle.fill"
            case .error: return "xmark.octagon.fill"
            }
        }

        var tint: Color {
            switch self {
            case .info: return .pokerPurpleLight
            case .success: return .pokerPositive
            case .warning: return .pokerWarning
            case .error: return .pokerNegative
            }
        }
    }

    let kind: Kind
    let message: String
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        HStack(alignment: .top, spacing: Spacing.md) {
            Image(systemName: kind.icon)
                .foregroundStyle(kind.tint)
                .accessibilityHidden(true)

            Text(message)
                .font(.pokerFootnote)
                .foregroundStyle(.pokerTextPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)

            if let actionTitle, let action {
                Button(action: action) {
                    Text(actionTitle)
                        .font(.pokerFootnote.weight(.semibold))
                        .foregroundStyle(kind.tint)
                        .frame(minWidth: Spacing.minTapTarget, minHeight: Spacing.minTapTarget)
                        .contentShape(Rectangle())
                }
            }
        }
        .padding(Spacing.md)
        .background(kind.tint.opacity(0.14))
        .clipShape(RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                .stroke(kind.tint.opacity(0.35), lineWidth: 1)
        )
        .accessibilityElement(children: .contain)
    }
}

struct EmptyState: View {
    let icon: String
    let title: String
    let message: String
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: Spacing.md) {
            Image(systemName: icon)
                .font(.system(size: 36))
                .foregroundStyle(Color.pokerPurpleLight)
                .accessibilityHidden(true)
            Text(title)
                .font(.pokerHeadline)
                .foregroundStyle(.pokerTextPrimary)
                .multilineTextAlignment(.center)
            Text(message)
                .font(.pokerFootnote)
                .foregroundStyle(.pokerTextSecondary)
                .multilineTextAlignment(.center)
            if let actionTitle, let action {
                PokerButton(title: actionTitle, kind: .secondary, action: action)
                    .padding(.top, Spacing.xs)
            }
        }
        .frame(maxWidth: .infinity)
        .pokerCard(padding: Spacing.xl)
    }
}

/// A shimmering placeholder shown while content loads. Static under Reduce Motion.
struct SkeletonView: View {
    var cornerRadius: CGFloat = Radius.control

    @State private var phase: CGFloat = -1
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(Color.white.opacity(0.08))
            .overlay(
                GeometryReader { geometry in
                    LinearGradient(
                        colors: [.clear, Color.white.opacity(0.10), .clear],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .frame(width: geometry.size.width * 0.6)
                    .offset(x: phase * geometry.size.width * 1.6)
                }
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            )
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.linear(duration: 1.3).repeatForever(autoreverses: false)) {
                    phase = 1
                }
            }
            .accessibilityHidden(true)
    }
}

// MARK: - Input

/// A whole-number field with large −/+ buttons, for player and chip counts.
struct StepperField: View {
    @Binding var value: Int
    let range: ClosedRange<Int>
    let accessibilityLabel: String
    var identifier: String? = nil
    /// A fixed-width version for sharing a row with other content.
    var isCompact = false

    var body: some View {
        HStack(spacing: Spacing.sm) {
            stepButton(systemName: "minus", delta: -1, label: "Decrease \(accessibilityLabel)")

            TextField("0", value: $value, format: .number)
                .keyboardType(.numberPad)
                .multilineTextAlignment(.center)
                .font(.pokerNumeric(.title3))
                .foregroundStyle(.pokerTextPrimary)
                .tint(.pokerGoldLight)
                .frame(minWidth: 52, maxWidth: isCompact ? 56 : .infinity, minHeight: Spacing.minTapTarget)
                .background(Color.white.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
                .accessibilityLabel(accessibilityLabel)
                .accessibilityIdentifier(identifier ?? "")
                .onChange(of: value) { newValue in
                    let clamped = min(max(newValue, range.lowerBound), range.upperBound)
                    if clamped != newValue { value = clamped }
                }

            stepButton(systemName: "plus", delta: 1, label: "Increase \(accessibilityLabel)")
        }
    }

    private func stepButton(systemName: String, delta: Int, label: String) -> some View {
        let target = value + delta
        let enabled = range.contains(target)
        return Button {
            guard enabled else { return }
            value = target
            Haptics.selection()
        } label: {
            Image(systemName: systemName)
                .font(.body.weight(.bold))
                .foregroundStyle(enabled ? Color.pokerGoldLight : Color.pokerTextTertiary)
                .frame(width: Spacing.minTapTarget, height: Spacing.minTapTarget)
                .background(Color.pokerGold.opacity(enabled ? 0.14 : 0.05))
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .accessibilityLabel(label)
        .accessibilityIdentifier(identifier.map { "\($0).\(delta < 0 ? "minus" : "plus")" } ?? "")
    }
}

extension View {
    /// A pinned action area at the bottom of a scrolling screen. Opaque, so
    /// content scrolling underneath never ghosts through the text on it, with a
    /// hairline on top to show it is a separate layer.
    func pokerBottomBar() -> some View {
        padding(.horizontal, Spacing.gutter)
            .padding(.vertical, Spacing.md)
            .pokerReadableWidth()
            .background(
                Color.pokerBackgroundBottom
                    .overlay(alignment: .top) { Color.white.opacity(0.10).frame(height: 1) }
                    .ignoresSafeArea(edges: .bottom)
            )
    }

    /// A "Done" button above the keyboard. Number pads have no return key, so
    /// without this a field can only be left by tapping elsewhere.
    func keyboardDoneButton() -> some View {
        toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") {
                    UIApplication.shared.sendAction(
                        #selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil
                    )
                }
                .accessibilityIdentifier("keyboard.done")
            }
        }
    }
}

// MARK: - Money and time

struct MoneyText: View {
    let cents: Int
    var signed = false
    var font: Font = .pokerNumeric(.body)
    var color: Color = .pokerTextPrimary

    var body: some View {
        Text(signed ? Money.formatSigned(cents: cents) : Money.format(cents: cents))
            .font(font)
            .foregroundStyle(color)
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .accessibilityLabel(spokenAmount)
    }

    private var spokenAmount: String {
        let words = Money.spoken(cents: abs(cents))
        guard signed else { return cents < 0 ? "minus \(words)" : words }
        if cents > 0 { return "plus \(words)" }
        return cents < 0 ? "minus \(words)" : words
    }
}

struct DurationText: View {
    enum Style { case clock, compact }

    let seconds: Int
    var style: Style = .compact
    var font: Font = .pokerNumeric(.body)
    var color: Color = .pokerTextPrimary

    var body: some View {
        Text(style == .clock ? DurationFormat.clock(seconds) : DurationFormat.compact(seconds))
            .font(font)
            .foregroundStyle(color)
            .lineLimit(1)
            .minimumScaleFactor(0.5)
            .accessibilityLabel(DurationFormat.spoken(seconds))
    }
}
