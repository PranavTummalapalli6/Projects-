//
//  DesignTokens.swift
//  PokerChipApp
//
//  The app's spacing, radii, type and colour roles in one place. Screens use
//  these names, not raw numbers, so the look can be tuned in one file and stays
//  consistent. Measured contrast for every text level is in docs/DESIGN.md.
//

import SwiftUI

// MARK: - Spacing and shape

/// A 4-pt grid.
enum Spacing {
    static let xs: CGFloat = 4
    static let sm: CGFloat = 8
    static let md: CGFloat = 12
    static let lg: CGFloat = 16
    static let xl: CGFloat = 24
    static let xxl: CGFloat = 32
    static let huge: CGFloat = 48

    /// Left/right margin of every screen.
    static let gutter: CGFloat = 16

    /// Apple's minimum comfortable touch target.
    static let minTapTarget: CGFloat = 44
}

enum Radius {
    static let control: CGFloat = 12
    static let card: CGFloat = 18
    static let sheet: CGFloat = 28
}

// MARK: - Colour roles

extension Color {
    // Surfaces layered over PokerBackground
    static let pokerSurface = Color.white.opacity(0.06)
    static let pokerSurfaceRaised = Color.white.opacity(0.10)
    static let pokerStroke = Color.pokerGold.opacity(0.22)

    // Text. Contrast against the app's lightest surface: primary ~12.6:1,
    // secondary ~7.9:1, tertiary ~5.7:1 — all above the 4.5:1 body-text bar.
    static let pokerTextPrimary = Color.white.opacity(0.95)
    static let pokerTextSecondary = Color.white.opacity(0.72)
    static let pokerTextTertiary = Color.white.opacity(0.58)

    // Meaning, not decoration: results, validation, status.
    static let pokerPositive = Color(red: 0.30, green: 0.80, blue: 0.52)
    static let pokerNegative = Color(red: 0.97, green: 0.45, blue: 0.45)
    static let pokerWarning = Color(red: 0.98, green: 0.72, blue: 0.30)
}

// Lets `.foregroundStyle(.pokerTextSecondary)` resolve the same way
// `.foregroundStyle(.red)` does.
extension ShapeStyle where Self == Color {
    static var pokerTextPrimary: Color { Color.pokerTextPrimary }
    static var pokerTextSecondary: Color { Color.pokerTextSecondary }
    static var pokerTextTertiary: Color { Color.pokerTextTertiary }
    static var pokerPositive: Color { Color.pokerPositive }
    static var pokerNegative: Color { Color.pokerNegative }
    static var pokerWarning: Color { Color.pokerWarning }
}

// MARK: - Type

/// Built on Dynamic Type text styles, so everything scales with the user's
/// text-size setting. Rounded design is the brand voice for headings and
/// numbers; body copy stays in the plain system face for legibility.
extension Font {
    static let pokerDisplay = Font.system(.largeTitle, design: .rounded).weight(.heavy)
    static let pokerTitle = Font.system(.title2, design: .rounded).weight(.bold)
    static let pokerHeadline = Font.system(.headline, design: .rounded)
    static let pokerBody = Font.system(.body)
    static let pokerCallout = Font.system(.callout)
    static let pokerFootnote = Font.system(.footnote)
    static let pokerCaption = Font.system(.caption).weight(.semibold)

    /// Money, counts and clocks: fixed-width digits so a changing value
    /// doesn't jiggle the layout around it.
    static func pokerNumeric(_ style: Font.TextStyle, weight: Font.Weight = .bold) -> Font {
        Font.system(style, design: .rounded).weight(weight).monospacedDigit()
    }
}

// MARK: - Chip colours

/// How each chip colour is drawn. Tuned to look like real clay chips rather
/// than the system's saturated primaries.
enum ChipPalette {
    static func fill(_ color: String) -> Color {
        switch color {
        case "White": return Color(red: 0.93, green: 0.93, blue: 0.90)
        case "Red": return Color(red: 0.80, green: 0.14, blue: 0.17)
        case "Blue": return Color(red: 0.13, green: 0.36, blue: 0.80)
        case "Green": return Color(red: 0.09, green: 0.55, blue: 0.31)
        case "Black": return Color(red: 0.10, green: 0.10, blue: 0.11)
        default: return .gray
        }
    }

    /// The edge "spots" — light on dark chips, dark on the white chip.
    static func spot(_ color: String) -> Color {
        color == "White" ? Color(white: 0.52) : Color.white.opacity(0.92)
    }

    /// The chip's outline. A Black chip is only 1.04:1 against the backdrop, so
    /// the darker chips get a lighter rim to stay visible (see docs/DESIGN.md).
    static func rim(_ color: String) -> Color {
        switch color {
        case "Black": return Color(white: 0.62)
        case "Blue": return Color.white.opacity(0.55)
        case "Red", "Green": return Color.white.opacity(0.40)
        default: return Color.white.opacity(0.28)
        }
    }

    /// Text drawn on top of the chip face.
    static func label(_ color: String) -> Color {
        color == "White" ? Color(white: 0.16) : .white
    }

    /// A single letter that identifies the chip without relying on colour —
    /// red and green are indistinguishable to many people. Black is "K" (as
    /// in CMYK) so it can't be mistaken for Blue.
    static func initial(_ color: String) -> String {
        switch color {
        case "Black": return "K"
        default: return String(color.prefix(1))
        }
    }
}

// MARK: - Layout helpers

extension View {
    /// Keeps content to a comfortable reading width and centred on wide screens.
    func pokerReadableWidth() -> some View {
        frame(maxWidth: 560).frame(maxWidth: .infinity)
    }

    /// The standard spring, switched off when Reduce Motion is on.
    func pokerSpring<Value: Equatable>(value: Value) -> some View {
        modifier(PokerSpringModifier(value: value))
    }
}

private struct PokerSpringModifier<Value: Equatable>: ViewModifier {
    let value: Value
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content.animation(reduceMotion ? nil : .spring(response: 0.35, dampingFraction: 0.85), value: value)
    }
}
