//
//  ContrastTests.swift
//  PokerChipAppTests
//
//  Holds the colour tokens to WCAG 2.x contrast: 4.5:1 for body text, measured
//  against the lightest surface each can sit on. The numbers in docs/DESIGN.md
//  come from the same arithmetic (docs/tools/contrast.py); this makes a change
//  to a token that would drop below the bar fail a test instead.
//
//  Xcode's own accessibility audit flags many of these pairs as failing even
//  where the rendered pixels measure 6–13:1, so it is not used as the gate for
//  contrast (see docs/QA.md).
//

import SwiftUI
import XCTest
@testable import PokerChipApp

final class ContrastTests: XCTestCase {
    private typealias RGB = (r: Double, g: Double, b: Double)

    private func components(_ color: Color) -> (rgb: RGB, alpha: Double) {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(color).getRed(&r, green: &g, blue: &b, alpha: &a)
        return ((Double(r), Double(g), Double(b)), Double(a))
    }

    /// `color` drawn over an opaque background.
    private func composite(_ color: Color, over background: RGB) -> RGB {
        let (rgb, alpha) = components(color)
        return (
            alpha * rgb.r + (1 - alpha) * background.r,
            alpha * rgb.g + (1 - alpha) * background.g,
            alpha * rgb.b + (1 - alpha) * background.b
        )
    }

    private func luminance(_ c: RGB) -> Double {
        func linear(_ v: Double) -> Double { v <= 0.03928 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4) }
        return 0.2126 * linear(c.r) + 0.7152 * linear(c.g) + 0.0722 * linear(c.b)
    }

    private func ratio(_ a: RGB, _ b: RGB) -> Double {
        let (la, lb) = (luminance(a), luminance(b))
        return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)
    }

    private var backdropTop: RGB { components(.pokerBackgroundTop).rgb }
    private var backdropBottom: RGB { components(.pokerBackgroundBottom).rgb }
    private var card: RGB { composite(.pokerSurface, over: backdropTop) }
    private var raised: RGB { composite(.pokerSurfaceRaised, over: backdropTop) }

    private var surfaces: [(name: String, color: RGB)] {
        [("backdrop top", backdropTop), ("backdrop bottom", backdropBottom), ("card", card), ("raised surface / text field", raised)]
    }

    func testEveryTextLevelMeetsBodyContrastOnEverySurface() {
        let levels: [(String, Color)] = [
            ("primary", .pokerTextPrimary), ("secondary", .pokerTextSecondary), ("tertiary", .pokerTextTertiary),
        ]
        for (levelName, level) in levels {
            for (surfaceName, surface) in surfaces {
                let measured = ratio(composite(level, over: surface), surface)
                XCTAssertGreaterThanOrEqual(measured, 4.5, "\(levelName) text on \(surfaceName) is \(String(format: "%.2f", measured)):1")
            }
        }
    }

    func testAccentAndMeaningColoursMeetBodyContrastOnCardsAndFields() {
        let colours: [(String, Color)] = [
            ("gold", .pokerGold), ("gold light", .pokerGoldLight), ("purple light", .pokerPurpleLight),
            ("positive", .pokerPositive), ("negative", .pokerNegative), ("warning", .pokerWarning),
        ]
        for (name, colour) in colours {
            for (surfaceName, surface) in [("backdrop top", backdropTop), ("card", card), ("raised surface / text field", raised)] {
                let measured = ratio(components(colour).rgb, surface)
                XCTAssertGreaterThanOrEqual(measured, 4.5, "\(name) on \(surfaceName) is \(String(format: "%.2f", measured)):1")
            }
        }
    }

    func testBannerTextMeetsBodyContrastOnItsOwnTint() {
        for kind in [InlineBanner.Kind.info, .success, .warning, .error] {
            let tint = components(kind.tint).rgb
            let background = composite(kind.tint.opacity(0.14), over: card)
            let text = ratio(tint, background)
            XCTAssertGreaterThanOrEqual(text, 4.5, "\(kind) banner's coloured icon/action text is \(String(format: "%.2f", text)):1")
            let primary = ratio(composite(.pokerTextPrimary, over: background), background)
            XCTAssertGreaterThanOrEqual(primary, 4.5, "\(kind) banner's message is \(String(format: "%.2f", primary)):1")
        }
    }

    func testButtonLabelsMeetBodyContrastOnTheirFills() {
        let black: RGB = (0, 0, 0)
        XCTAssertGreaterThanOrEqual(ratio(black, components(.pokerGoldLight).rgb), 4.5)
        XCTAssertGreaterThanOrEqual(ratio(black, components(.pokerGold).rgb), 4.5)

        let secondaryFill = composite(Color.white.opacity(0.05), over: backdropTop)
        XCTAssertGreaterThanOrEqual(ratio(components(.pokerPurpleLight).rgb, secondaryFill), 4.5)

        let destructiveFill = composite(Color.pokerNegative.opacity(0.10), over: backdropTop)
        XCTAssertGreaterThanOrEqual(ratio(components(.pokerNegative).rgb, destructiveFill), 4.5)
    }

    func testTheDarkestChipsGetARimBrightEnoughToSeeAgainstTheBackdrop() {
        // A Black chip's fill is 1.04:1 against the backdrop; its rim carries it.
        let rim = composite(ChipPalette.rim("Black"), over: backdropTop)
        XCTAssertGreaterThanOrEqual(ratio(rim, backdropTop), 3.0, "graphical objects need 3:1")
    }
}
