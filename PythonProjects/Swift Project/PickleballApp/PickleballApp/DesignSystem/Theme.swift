import SwiftUI
import UIKit

/// Restrained palette: one accent, semantic availability colors, native materials. Every color adapts to dark mode.
enum Theme {
    static let accent = Color(light: 0x1F7A5C, dark: 0x4CC69A)
    static let accentSoft = Color(light: 0xE3F2EC, dark: 0x163A2E)

    static let available = Color(light: 0x23864F, dark: 0x4CD787)
    static let moderate = Color(light: 0xB7791F, dark: 0xF2B544)
    static let busy = Color(light: 0xC2410C, dark: 0xFF8A4C)
    static let unknown = Color(light: 0x6B7280, dark: 0x9CA3AF)
    static let surfaceIssue = Color(light: 0x2563EB, dark: 0x6EA8FF)
    static let restricted = Color(light: 0x7C3AED, dark: 0xB794F6)
    static let unavailable = Color(light: 0xB91C1C, dark: 0xF87171)

    static let cardBackground = Color(uiColor: .secondarySystemGroupedBackground)
    static let groupedBackground = Color(uiColor: .systemGroupedBackground)
    /// Card fill on plain backgrounds (sheets), where the grouped card color would be invisible.
    static let raisedFill = Color(uiColor: .secondarySystemBackground)

    enum Spacing {
        static let xs: CGFloat = 4, s: CGFloat = 8, m: CGFloat = 12, l: CGFloat = 16, xl: CGFloat = 24
    }
    enum Radius {
        static let s: CGFloat = 10, m: CGFloat = 16, l: CGFloat = 22
    }
    /// Minimum tap target for primary actions (larger than Apple's 44pt minimum for older users).
    static let largeTap: CGFloat = 56
}

extension Color {
    init(light: UInt32, dark: UInt32) {
        self.init(uiColor: UIColor { traits in
            let hex = traits.userInterfaceStyle == .dark ? dark : light
            return UIColor(red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                           blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
        })
    }
}
