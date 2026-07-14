//
//  AuthViewModel.swift
//  PokerChipApp
//
//  Created by Pranav on 4/1/25.
//

import Foundation
import FirebaseAuth

class AuthViewModel: ObservableObject {
    @Published var isSignedIn: Bool = false
    
    init() {
        self.isSignedIn = false  // Force sign out for testing
        _ = Auth.auth().addStateDidChangeListener { _, user in
            self.isSignedIn = user != nil
            print("Auth state changed. User is signed in: \(self.isSignedIn)")
        }
    }

    
    func signOut() {
        try? Auth.auth().signOut()
        self.isSignedIn = false
    }
}

