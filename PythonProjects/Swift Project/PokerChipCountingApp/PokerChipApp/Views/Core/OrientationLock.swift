//
//  OrientationLock.swift
//  PokerChipApp
//
//  The app is portrait everywhere except the full-screen table card, which is
//  made to be propped up on its side. The app delegate asks `current` which
//  orientations are allowed; the card widens it while it is on screen and
//  puts it back when it goes.
//

import UIKit
import os

@MainActor
enum OrientationLock {
    private static let log = Logger(subsystem: "Vanarp.PokerChipApp", category: "orientation")

    /// What the app may rotate to right now.
    private(set) static var current: UIInterfaceOrientationMask = .portrait

    static func allowLandscape() { apply(.landscape) }
    static func restorePortrait() { apply(.portrait) }

    private static func apply(_ mask: UIInterfaceOrientationMask) {
        current = mask
        guard let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first else { return }
        scene.windows.first?.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()
        scene.requestGeometryUpdate(.iOS(interfaceOrientations: mask)) { error in
            log.error("Could not rotate the interface: \(error.localizedDescription, privacy: .public)")
        }
    }
}
