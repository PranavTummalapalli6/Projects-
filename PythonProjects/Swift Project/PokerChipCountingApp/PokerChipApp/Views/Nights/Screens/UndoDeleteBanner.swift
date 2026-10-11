//
//  UndoDeleteBanner.swift
//  PokerChipApp
//
//  "Night deleted · Undo", for the few seconds a deletion can still be taken
//  back — on Home and History, whichever screen the night was deleted from.
//

import SwiftUI

private struct UndoDeleteBanner: ViewModifier {
    @EnvironmentObject private var store: NightStore

    func body(content: Content) -> some View {
        content
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if let id = store.lastDeletedID {
                    InlineBanner(kind: .success, message: "Night deleted.", actionTitle: "Undo") {
                        store.restore(id)
                        Haptics.selection()
                    }
                    .padding(.horizontal, Spacing.gutter)
                    .padding(.vertical, Spacing.sm)
                    .pokerReadableWidth()
                    .accessibilityIdentifier("undo.banner")
                    .transition(.opacity)
                }
            }
            .pokerSpring(value: store.lastDeletedID)
    }
}

extension View {
    /// Shows the Undo banner for a just-deleted night at the bottom of this screen.
    func undoDeleteBanner() -> some View {
        modifier(UndoDeleteBanner())
    }
}
