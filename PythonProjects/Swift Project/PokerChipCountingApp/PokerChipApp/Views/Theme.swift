import SwiftUI

/// Canonical chip color order, shared across every screen that lists chip
/// colors — buy-in availability, denomination suggestions, review, results —
/// so they always present colors in the same order instead of each screen
/// picking its own.
let allChipColors = ["White", "Red", "Blue", "Green", "Black"]

/// Shared "high-stakes" visual language for the whole app — dark background,
/// gold primary accent, purple secondary accent — matching the two brand
/// marks already in Assets.xcassets (the purple/lavender Poker Chip Counter
/// badge, and the gold/black Van Arp Studios splash seal) rather than
/// introducing a third, unrelated color scheme. Spacing, type and the
/// meaning-carrying colours live in DesignSystem/DesignTokens.swift.
extension Color {
    static let pokerGold = Color(red: 0.85, green: 0.68, blue: 0.32)
    static let pokerGoldLight = Color(red: 0.96, green: 0.84, blue: 0.56)
    static let pokerPurple = Color(red: 0.46, green: 0.32, blue: 0.70)
    static let pokerPurpleLight = Color(red: 0.72, green: 0.62, blue: 0.92)
    static let pokerBackgroundTop = Color(red: 0.10, green: 0.07, blue: 0.15)
    static let pokerBackgroundBottom = Color(red: 0.02, green: 0.015, blue: 0.035)
}

// Lets `.foregroundStyle(.pokerGold)` resolve via dot-shorthand the same way
// `.foregroundStyle(.red)` does — SwiftUI's built-in colors get that shorthand
// through a ShapeStyle extension, not just a Color one, so ours needs it too.
extension ShapeStyle where Self == Color {
    static var pokerGold: Color { Color.pokerGold }
    static var pokerGoldLight: Color { Color.pokerGoldLight }
    static var pokerPurple: Color { Color.pokerPurple }
    static var pokerPurpleLight: Color { Color.pokerPurpleLight }
}

/// The app's standard backdrop — a dark purple-to-black gradient. Apply with
/// `.background(PokerBackground())` behind a screen's content.
struct PokerBackground: View {
    var body: some View {
        LinearGradient(
            colors: [.pokerBackgroundTop, .pokerBackgroundBottom],
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea()
    }
}

/// A translucent glass panel with a thin gold hairline — the app's standard
/// container for grouped content (used in place of plain `Color.gray.opacity`
/// backgrounds, which were designed for a light, not dark, background).
struct PokerCardModifier: ViewModifier {
    var padding: CGFloat = Spacing.lg

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(Color.pokerSurface)
            .clipShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                    .stroke(Color.pokerStroke, lineWidth: 1)
            )
    }
}

extension View {
    func pokerCard(padding: CGFloat = Spacing.lg) -> some View {
        modifier(PokerCardModifier(padding: padding))
    }
}

/// Standard text-input look for the dark theme — plain SwiftUI TextFields
/// default to a light-background appearance that reads poorly here. A field
/// in error gets a red outline as well as its message, so the problem is
/// visible without reading.
struct PokerTextFieldModifier: ViewModifier {
    var isError = false

    func body(content: Content) -> some View {
        content
            .foregroundStyle(Color.pokerTextPrimary)
            .tint(Color.pokerGoldLight)
            .padding(.horizontal, Spacing.md)
            .frame(minHeight: 48)
            .background(Color.white.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                    .stroke(isError ? Color.pokerNegative : Color.white.opacity(0.16), lineWidth: isError ? 1.5 : 1)
            )
    }
}

extension View {
    func pokerTextField(isError: Bool = false) -> some View {
        modifier(PokerTextFieldModifier(isError: isError))
    }
}

/// Large screen title — gold, rounded, bold, matching the brand marks. Scales
/// with the reader's text size.
struct PokerTitle: View {
    let text: String
    @ScaledMetric private var size: CGFloat

    init(text: String, size: CGFloat = 34) {
        self.text = text
        _size = ScaledMetric(wrappedValue: size, relativeTo: .largeTitle)
    }

    var body: some View {
        Text(text)
            .font(.system(size: size, weight: .heavy, design: .rounded))
            .foregroundStyle(
                LinearGradient(colors: [.pokerGoldLight, .pokerGold], startPoint: .top, endPoint: .bottom)
            )
            .multilineTextAlignment(.center)
            .minimumScaleFactor(0.7)
            .accessibilityAddTraits(.isHeader)
    }
}
