//
//  WidgetPalette.swift
//  PokerChipWidgets
//
//  The app's purple and gold, for the widgets (which can't reach the app's own
//  theme): the same values as `Theme.swift`.
//

import SwiftUI

enum WidgetPalette {
    static let gold = Color(red: 0.85, green: 0.68, blue: 0.32)
    static let goldLight = Color(red: 0.96, green: 0.84, blue: 0.56)
    static let purple = Color(red: 0.46, green: 0.32, blue: 0.70)
    static let purpleLight = Color(red: 0.72, green: 0.62, blue: 0.92)
    static let backgroundTop = Color(red: 0.10, green: 0.07, blue: 0.15)
    static let backgroundBottom = Color(red: 0.02, green: 0.015, blue: 0.035)
    static let textPrimary = Color.white
    static let textSecondary = Color.white.opacity(0.72)

    static var background: LinearGradient {
        LinearGradient(colors: [backgroundTop, backgroundBottom], startPoint: .top, endPoint: .bottom)
    }
}
