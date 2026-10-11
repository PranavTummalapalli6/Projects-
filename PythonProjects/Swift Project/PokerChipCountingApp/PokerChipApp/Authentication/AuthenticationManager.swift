//
//  AuthenticationManager.swift
//  PokerChipApp
//
//  Created by Pranav on 4/1/25.
//

import Foundation
import FirebaseAuth

struct AuthDataResultModel {
    let uid: String
    let email: String?
    let photoUrl: String?
    let isAnonymous: Bool

    init(user: User) {
        self.uid = user.uid
        self.email = user.email
        self.photoUrl = user.photoURL?.absoluteString
        self.isAnonymous = user.isAnonymous
    }
}

final class AuthenticationManager {
    static let shared = AuthenticationManager()
    private init() { }

    func createUser(email: String, password: String) async throws -> AuthDataResultModel {
        let authDataResult = try await Auth.auth().createUser(withEmail: email, password: password)
        return AuthDataResultModel(user: authDataResult.user)
    }

    func signIn(email: String, password: String) async throws -> AuthDataResultModel {
        let authDataResult = try await Auth.auth().signIn(withEmail: email, password: password)
        return AuthDataResultModel(user: authDataResult.user)
    }

    /// A guest account: real sign-in, no email. Needs the Anonymous provider
    /// enabled in the Firebase console (Authentication → Sign-in method).
    func signInAnonymously() async throws -> AuthDataResultModel {
        let authDataResult = try await Auth.auth().signInAnonymously()
        return AuthDataResultModel(user: authDataResult.user)
    }

    func sendPasswordReset(email: String) async throws {
        try await Auth.auth().sendPasswordReset(withEmail: email)
    }

    /// Upgrades the current (guest) account to an email account in place, so
    /// everything saved as a guest comes along.
    func linkEmail(email: String, password: String) async throws -> AuthDataResultModel {
        guard let user = Auth.auth().currentUser else {
            throw URLError(.userAuthenticationRequired)
        }
        let credential = EmailAuthProvider.credential(withEmail: email, password: password)
        let authDataResult = try await user.link(with: credential)
        return AuthDataResultModel(user: authDataResult.user)
    }

    func signOut() throws {
        try Auth.auth().signOut()
    }

    /// The token the backend uses to verify who's calling it
    /// (Authorization: Bearer <token>). Firebase caches it and refreshes it
    /// hourly on its own; `forceRefresh` is for recovering from a 401.
    func currentIdToken(forceRefresh: Bool = false) async throws -> String {
        guard let user = Auth.auth().currentUser else {
            throw URLError(.userAuthenticationRequired)
        }
        return try await user.getIDToken(forcingRefresh: forceRefresh)
    }
}
