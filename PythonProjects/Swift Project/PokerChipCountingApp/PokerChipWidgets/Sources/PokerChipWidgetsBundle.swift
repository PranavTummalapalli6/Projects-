//
//  PokerChipWidgetsBundle.swift
//  PokerChipWidgets
//
//  What the app adds outside itself: the night in progress on the Lock Screen and
//  in the Dynamic Island.
//

import SwiftUI
import WidgetKit

@main
struct PokerChipWidgetsBundle: WidgetBundle {
    var body: some Widget {
        NightLiveActivity()
    }
}
