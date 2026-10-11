//
//  AuthenticationView.swift
//  PokerChipApp
//
//  Created by Pranav on 4/2/25.
//

import SwiftUI

/// The first screen for someone who isn't signed in. Guest comes first: nobody
/// should have to make an account before they can count a stack of chips.
struct AuthenticationView: View {
    @EnvironmentObject private var auth: AuthViewModel
    @State private var isWorking = false
    @State private var errorMessage: String?

    var body: some View {
        ScrollView {
            VStack(spacing: Spacing.xl) {
                VStack(spacing: Spacing.lg) {
                    Image("poker_chip_counter_no_bg")
                        .resizable()
                        .scaledToFit()
                        .frame(height: 132)
                        .shadow(color: .pokerPurple.opacity(0.5), radius: 20)
                        .accessibilityHidden(true)

                    PokerTitle(text: "Poker Chip Counter")

                    Text("Work out chip values, run the night, count the stacks, settle up and see how much you play.")
                        .font(.pokerCallout)
                        .foregroundStyle(.pokerTextSecondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.top, Spacing.xxl)

                VStack(spacing: Spacing.md) {
                    if let errorMessage {
                        InlineBanner(kind: .error, message: errorMessage)
                    }

                    PokerButton(title: "Continue as guest", systemImage: "person.fill", isLoading: isWorking) {
                        continueAsGuest()
                    }
                    .accessibilityIdentifier("auth.guest")

                    #if SIGN_IN_WITH_APPLE
                    AppleSignInButton { errorMessage = $0 }
                    #endif

                    NavigationLink {
                        SignInEmailView()
                    } label: {
                        Label("Sign in with email", systemImage: "envelope.fill")
                            .pokerSecondaryLabel()
                    }
                    .accessibilityIdentifier("auth.email")
                }

                Text("A guest account keeps your games private to this app. You can add an email later in Settings to keep them if you change phones.")
                    .font(.pokerFootnote)
                    .foregroundStyle(.pokerTextTertiary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, Spacing.gutter)
            .padding(.bottom, Spacing.xl)
            .pokerReadableWidth()
        }
        .background(PokerBackground())
        .navigationBarTitleDisplayMode(.inline)
    }

    private func continueAsGuest() {
        errorMessage = nil
        isWorking = true
        Task {
            do {
                try await auth.continueAsGuest()
            } catch {
                errorMessage = AuthErrorMessage.message(for: error)
            }
            isWorking = false
        }
    }
}

struct AuthenticationView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationStack {
            AuthenticationView()
                .environmentObject(AuthViewModel())
        }
    }
}
