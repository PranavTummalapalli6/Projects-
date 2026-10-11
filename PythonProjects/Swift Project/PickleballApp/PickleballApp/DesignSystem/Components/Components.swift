import PickleCore
import SwiftUI

/// Small capsule with icon + short label.
struct Pill: View {
    var text: String
    var symbol: String?
    var tint: Color = .secondary
    var filled = false

    var body: some View {
        HStack(spacing: 4) {
            if let symbol { Image(systemName: symbol).imageScale(.small) }
            Text(text).lineLimit(1)
        }
        .font(.footnote.weight(.semibold))
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .foregroundStyle(filled ? Color.white : tint)
        .background(filled ? AnyShapeStyle(tint) : AnyShapeStyle(tint.opacity(0.14)), in: Capsule())
        .accessibilityElement(children: .combine)
    }
}

/// Status chip used in sheets and cards (icon + label + color).
struct StatusChip: View {
    var status: FacilityStatus
    var body: some View { Pill(text: status.label, symbol: status.symbol, tint: status.color) }
}

/// "High confidence" with a three-bar glyph. Never a percentage.
struct ConfidenceIndicator: View {
    var level: ConfidenceLevel
    var body: some View {
        HStack(spacing: 5) {
            HStack(alignment: .bottom, spacing: 2) {
                ForEach(0..<3) { i in
                    RoundedRectangle(cornerRadius: 1)
                        .fill(i <= rank ? Icons.color(for: level) : Color.secondary.opacity(0.25))
                        .frame(width: 4, height: CGFloat(6 + i * 4))
                }
            }
            Text(level.displayName).font(.footnote).foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(level.displayName)
    }
    private var rank: Int { level == .high ? 2 : level == .medium ? 1 : 0 }
}

/// Large, whole-card tappable choice for one-tap reporting. Comfortable for all ages.
struct ChoiceTile: View {
    var symbol: String
    var label: String
    var tint: Color = Theme.accent
    var isSelected = false
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: symbol).font(.title2.weight(.semibold))
                Text(label).font(.callout.weight(.semibold)).multilineTextAlignment(.center).lineLimit(2).minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity, minHeight: 92)
            .padding(.vertical, 8)
            .foregroundStyle(isSelected ? Color.white : tint)
            .background(isSelected ? AnyShapeStyle(tint) : AnyShapeStyle(tint.opacity(0.12)),
                        in: RoundedRectangle(cornerRadius: Theme.Radius.m, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: Theme.Radius.m))
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel(label)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

struct PressableStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

struct PrimaryButtonStyle: ButtonStyle {
    var tint: Color = Theme.accent
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .frame(maxWidth: .infinity, minHeight: 52)
            .foregroundStyle(.white)
            .background(tint.opacity(configuration.isPressed ? 0.8 : 1), in: RoundedRectangle(cornerRadius: Theme.Radius.m, style: .continuous))
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .frame(maxWidth: .infinity, minHeight: 48)
            .foregroundStyle(Theme.accent)
            .background(Theme.accentSoft.opacity(configuration.isPressed ? 0.7 : 1), in: RoundedRectangle(cornerRadius: Theme.Radius.m, style: .continuous))
    }
}

/// Grouped card container.
struct Card<Content: View>: View {
    var title: String?
    var symbol: String?
    /// Use `Theme.raisedFill` when the card sits on a plain (non-grouped) background such as a sheet.
    var fill: Color = Theme.cardBackground
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            if let title {
                Label(title, systemImage: symbol ?? "circle")
                    .labelStyle(.titleAndIcon)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .accessibilityAddTraits(.isHeader)
            }
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Theme.Spacing.l)
        .background(fill, in: RoundedRectangle(cornerRadius: Theme.Radius.l, style: .continuous))
    }
}

/// Icon + title + value row.
struct InfoRow: View {
    var symbol: String
    var title: String
    var value: String?
    var caption: String?
    var tint: Color = .secondary

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.m) {
            Image(systemName: symbol).foregroundStyle(tint).frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.body)
                if let caption { Text(caption).font(.footnote).foregroundStyle(.secondary) }
            }
            Spacer(minLength: 8)
            if let value { Text(value).font(.body.weight(.semibold)).multilineTextAlignment(.trailing) }
        }
        .accessibilityElement(children: .combine)
    }
}

struct EmptyStateView: View {
    var symbol: String
    var title: String
    var message: String
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        VStack(spacing: Theme.Spacing.m) {
            Image(systemName: symbol).font(.system(size: 34, weight: .semibold)).foregroundStyle(Theme.accent)
            Text(title).font(.headline).multilineTextAlignment(.center)
            Text(message).font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
            if let actionTitle, let action {
                Button(actionTitle, action: action).buttonStyle(PrimaryButtonStyle()).padding(.top, 4)
            }
        }
        .padding(Theme.Spacing.xl)
        .frame(maxWidth: .infinity)
    }
}

/// Distinguishes kinds of information (trust rule): fact vs community estimate vs live vs prediction.
enum InfoKind {
    case verifiedFact, communityEstimate, live, historical, prediction, warning

    var label: String {
        switch self {
        case .verifiedFact: "Verified"
        case .communityEstimate: "Community estimate"
        case .live: "LIVE"
        case .historical: "Usual pattern"
        case .prediction: "Estimate"
        case .warning: "Warning"
        }
    }
    var symbol: String {
        switch self {
        case .verifiedFact: "checkmark.seal.fill"
        case .communityEstimate: "person.2.fill"
        case .live: "dot.radiowaves.left.and.right"
        case .historical: "chart.bar.fill"
        case .prediction: "wand.and.stars"
        case .warning: "exclamationmark.triangle.fill"
        }
    }
    var tint: Color {
        switch self {
        case .verifiedFact: Theme.accent
        case .communityEstimate: Theme.restricted
        case .live: Theme.available
        case .historical, .prediction: Theme.unknown
        case .warning: Theme.busy
        }
    }
}

struct InfoKindTag: View {
    var kind: InfoKind
    var body: some View {
        Label(kind.label, systemImage: kind.symbol)
            .font(.caption2.weight(.bold))
            .textCase(.uppercase)
            .foregroundStyle(kind.tint)
    }
}

struct WarningBanner: View {
    var text: String
    var symbol = "exclamationmark.triangle.fill"
    var tint: Color = Theme.busy
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbol)
            Text(text).font(.subheadline.weight(.medium)).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .foregroundStyle(tint)
        .padding(12)
        .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: Theme.Radius.s, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}
