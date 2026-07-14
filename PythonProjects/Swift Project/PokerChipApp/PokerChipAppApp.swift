//
//  PokerChipAppApp.swift
//  PokerChipApp
//
//  Created by Pranav on 11/11/24.
//

import SwiftUI
import Firebase
import FirebaseAuth

@main
struct PokerChipAppApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil) -> Bool {
        FirebaseApp.configure()
        // Force sign out for testing purposes.
        try? Auth.auth().signOut()
        return true
    }
}

