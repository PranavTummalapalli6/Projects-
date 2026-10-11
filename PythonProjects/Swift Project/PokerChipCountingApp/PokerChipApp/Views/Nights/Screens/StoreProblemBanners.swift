//
//  StoreProblemBanners.swift
//  PokerChipApp
//
//  What went wrong with the nights on this phone, in plain words, wherever
//  nights are listed: a file that couldn't be opened, nights from a newer
//  version of the app, a full disk.
//

import SwiftUI

struct StoreProblemBanners: View {
    @EnvironmentObject private var store: NightStore

    var body: some View {
        ForEach(Array(store.problems.enumerated()), id: \.offset) { _, problem in
            InlineBanner(
                kind: .warning,
                message: problem.message,
                actionTitle: problem == .couldNotSave ? "Try again" : nil
            ) {
                store.retrySaving()
            }
            .accessibilityIdentifier("store.problem")
        }
    }
}
