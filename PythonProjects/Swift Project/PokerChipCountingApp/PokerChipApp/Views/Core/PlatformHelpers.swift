//
//  PlatformHelpers.swift
//  PokerChipApp
//
//  Small shared infrastructure: load states, haptics, connectivity.
//

import Network
import SwiftUI
import UIKit

/// What a screen that fetches something is currently showing.
enum LoadState<Value> {
    case idle
    case loading
    case loaded(Value)
    case failed(String)
}

/// One place for haptics, so the Settings toggle really turns all of them off.
@MainActor
enum Haptics {
    static func selection() {
        guard AppPreferences.hapticsEnabled else { return }
        UISelectionFeedbackGenerator().selectionChanged()
    }

    static func tap() {
        guard AppPreferences.hapticsEnabled else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    static func success() {
        guard AppPreferences.hapticsEnabled else { return }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    static func warning() {
        guard AppPreferences.hapticsEnabled else { return }
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
    }
}

/// Whether the device currently has a network path. Lets screens say "you're
/// offline — count by hand" up front instead of failing after a long wait.
@MainActor
final class ConnectivityMonitor: ObservableObject {
    @Published private(set) var isOnline = true

    private let monitor = NWPathMonitor()

    init() {
        if AppEnvironment.isUITest { return }
        monitor.pathUpdateHandler = { [weak self] path in
            let online = path.status == .satisfied
            Task { @MainActor in self?.isOnline = online }
        }
        monitor.start(queue: DispatchQueue(label: "ConnectivityMonitor"))
    }

    deinit {
        monitor.cancel()
    }
}
