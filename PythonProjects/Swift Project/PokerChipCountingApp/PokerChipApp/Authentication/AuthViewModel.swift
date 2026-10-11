//
//  AuthViewModel.swift
//  PokerChipApp
//
//  Created by Pranav on 4/1/25.
//

import Foundation
import FirebaseAuth

/// Who is signed in, driven by Firebase's own listener. Firebase keeps the
/// session in the keychain, so a signed-in person stays signed in across
/// launches; `.unknown` only exists for the instant before the listener
/// reports, so the UI never flashes the wrong screen.
@MainActor
final class AuthViewModel: ObservableObject {
    struct Account: Equatable {
        let uid: String
        let email: String?
        let isAnonymous: Bool
    }

    enum State: Equatable {
        case unknown
        case signedOut
        case signedIn(Account)
    }

    @Published private(set) var state: State = .unknown

    private var listener: AuthStateDidChangeListenerHandle?

    var isSignedIn: Bool {
        if case .signedIn = state { return true }
        return false
    }

    var account: Account? {
        if case .signedIn(let account) = state { return account }
        return nil
    }

    init() {
        #if DEBUG
        if AppEnvironment.isUITest {
            state = .signedIn(Account(uid: "ui-test", email: nil, isAnonymous: true))
            return
        }
        #endif
        listener = Auth.auth().addStateDidChangeListener { [weak self] _, user in
            Task { @MainActor in self?.apply(user) }
        }
    }

    deinit {
        if let listener {
            Auth.auth().removeStateDidChangeListener(listener)
        }
    }

    private func apply(_ user: User?) {
        if let user {
            state = .signedIn(Account(uid: user.uid, email: user.email, isAnonymous: user.isAnonymous))
        } else {
            state = .signedOut
        }
    }

    /// Linking a guest to an email keeps the same user id, so Firebase's
    /// listener doesn't fire — re-read the account by hand afterwards.
    func refreshAccount() {
        #if DEBUG
        if AppEnvironment.isUITest { return }
        #endif
        apply(Auth.auth().currentUser)
    }

    // MARK: Actions

    func continueAsGuest() async throws {
        #if DEBUG
        if AppEnvironment.isUITest {
            state = .signedIn(Account(uid: "ui-test", email: nil, isAnonymous: true))
            return
        }
        #endif
        _ = try await AuthenticationManager.shared.signInAnonymously()
    }

    func signOut() {
        #if DEBUG
        if AppEnvironment.isUITest { state = .signedOut; return }
        #endif
        try? AuthenticationManager.shared.signOut()
    }

    /// Deletes the account on the server first — records, photos and the
    /// sign-in itself — and only then clears the device. If the server call
    /// fails (offline), nothing local is touched and the account still exists.
    func deleteAccount() async throws {
        try await ChipVisionAPIClient.shared.deleteAccount()
        Stores.clearAll()
        signOut()
    }
}

/// Plain-language messages for Firebase Auth errors. Wrong-password and
/// no-such-account are deliberately the same message, so the sign-in screen
/// can't be used to find out who has an account.
enum AuthErrorMessage {
    static func message(for error: Error) -> String {
        let nsError = error as NSError
        guard nsError.domain == "FIRAuthErrorDomain" else {
            if let apiError = error as? ChipVisionAPIError { return apiError.localizedDescription }
            if (error as? URLError)?.code == .notConnectedToInternet { return "You're offline. Check your connection and try again." }
            return nsError.localizedDescription
        }
        switch nsError.code {
        case 17004, 17009, 17011:
            return "That email and password don't match. Check them, or reset your password."
        case 17007:
            return "An account with that email already exists. Try signing in instead."
        case 17008:
            return "That doesn't look like a valid email address."
        case 17010:
            return "Too many attempts. Wait a few minutes and try again."
        case 17014:
            return "For security, sign out and back in, then try again."
        case 17020:
            return "You're offline. Check your connection and try again."
        case 17025:
            return "That email already belongs to another account. Sign in with it instead — games saved as a guest stay with the guest account."
        case 17026:
            return "Choose a password with at least 6 characters."
        case 17006:
            return "This sign-in option isn't turned on yet."
        default:
            return nsError.localizedDescription
        }
    }
}
