//
//  PokerChipAppApp.swift
//  PokerChipApp
//
//  Created by Pranav on 11/11/24.
//

import SwiftUI
import Firebase

@main
struct PokerChipAppApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate

    init() {
        AppEnvironment.resetPersistedStateIfRequested()
        Stores.removeRetiredKeys()
        PokerAppearance.apply()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil) -> Bool {
        #if DEBUG
        // UI tests run against stubbed sign-in and network, so Firebase is
        // never started.
        if AppEnvironment.isUITest { return true }
        #endif
        // Firebase keeps the signed-in user in the keychain: starting it is all
        // it takes for a returning person to stay signed in.
        FirebaseApp.configure()
        return true
    }

    /// Portrait everywhere except the table card (see `OrientationLock`).
    func application(_ application: UIApplication,
                     supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        OrientationLock.current
    }
}
