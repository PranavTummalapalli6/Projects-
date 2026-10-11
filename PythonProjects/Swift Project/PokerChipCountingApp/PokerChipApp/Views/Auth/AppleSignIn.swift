//
//  AppleSignIn.swift
//  PokerChipApp
//
//  Sign in with Apple, exchanged for a Firebase credential.
//
//  Compiled only when the `SIGN_IN_WITH_APPLE` build flag is set, because it
//  needs setup that only the app's owner can do: a paid Apple Developer team
//  with the "Sign in with Apple" capability, and the Apple provider enabled in
//  the Firebase console. (Adding the capability to a free "Personal Team"
//  breaks code signing, so it stays off until then.) Steps are in
//  docs/QUESTIONS.md.
//

#if SIGN_IN_WITH_APPLE
import AuthenticationServices
import CryptoKit
import FirebaseAuth
import SwiftUI

struct AppleSignInButton: View {
    var onError: (String) -> Void

    @State private var rawNonce: String?

    var body: some View {
        SignInWithAppleButton(.continue) { request in
            let nonce = Self.randomNonce()
            rawNonce = nonce
            request.requestedScopes = [.email]
            request.nonce = Self.sha256(nonce)
        } onCompletion: { result in
            switch result {
            case .success(let authorization):
                handle(authorization)
            case .failure(let error):
                // Dismissing the sheet isn't an error worth showing.
                if (error as? ASAuthorizationError)?.code != .canceled {
                    onError("Apple sign-in didn't complete. Try again, or use email.")
                }
            }
        }
        .signInWithAppleButtonStyle(.white)
        .frame(height: 54)
        .clipShape(RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
        .accessibilityIdentifier("auth.apple")
    }

    private func handle(_ authorization: ASAuthorization) {
        guard
            let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
            let tokenData = credential.identityToken,
            let idToken = String(data: tokenData, encoding: .utf8),
            let nonce = rawNonce
        else {
            onError("Apple sign-in didn't return what we needed. Try again, or use email.")
            return
        }
        let firebaseCredential = OAuthProvider.appleCredential(
            withIDToken: idToken,
            rawNonce: nonce,
            fullName: credential.fullName
        )
        Task {
            do {
                _ = try await Auth.auth().signIn(with: firebaseCredential)
            } catch {
                onError(AuthErrorMessage.message(for: error))
            }
        }
    }

    /// A single-use random string; its hash goes to Apple and the original to
    /// Firebase, which proves the token was minted for this very request.
    private static func randomNonce(length: Int = 32) -> String {
        let charset = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        var result = ""
        while result.count < length {
            var bytes = [UInt8](repeating: 0, count: 16)
            guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else {
                // The system random generator failing is practically unheard of; a
                // UUID is still unpredictable enough for a one-time nonce, and
                // sign-in shouldn't crash the app over it.
                return UUID().uuidString.replacingOccurrences(of: "-", with: "")
            }
            for byte in bytes where result.count < length && Int(byte) < charset.count * (256 / charset.count) {
                result.append(charset[Int(byte) % charset.count])
            }
        }
        return result
    }

    private static func sha256(_ input: String) -> String {
        SHA256.hash(data: Data(input.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}
#endif
