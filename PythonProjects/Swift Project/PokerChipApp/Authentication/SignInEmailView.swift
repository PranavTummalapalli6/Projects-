import SwiftUI

@MainActor
final class SignInEmailViewModel: ObservableObject {
    @Published var email = ""
    @Published var password = ""
    @Published var errorMessage: String?
    @Published var isWorking = false

    /// True once the account has been created/signed into. AuthViewModel's Firebase
    /// listener is what actually drives navigation away from this screen.
    func submit(mode: AuthMode) {
        guard !email.isEmpty, !password.isEmpty else {
            errorMessage = "Enter both an email and a password."
            return
        }
        errorMessage = nil
        isWorking = true
        Task {
            do {
                switch mode {
                case .signIn:
                    _ = try await AuthenticationManager.shared.signIn(email: email, password: password)
                case .signUp:
                    _ = try await AuthenticationManager.shared.createUser(email: email, password: password)
                }
            } catch {
                errorMessage = friendlyMessage(for: error)
            }
            isWorking = false
        }
    }

    private func friendlyMessage(for error: Error) -> String {
        let nsError = error as NSError
        switch nsError.code {
        case 17009: return "Incorrect password."
        case 17011: return "No account found with that email."
        case 17007: return "An account with that email already exists."
        case 17026: return "Password must be at least 6 characters."
        default: return nsError.localizedDescription
        }
    }
}

enum AuthMode: String, CaseIterable {
    case signIn = "Sign In"
    case signUp = "Sign Up"
}

struct SignInEmailView: View {
    @StateObject private var viewModel = SignInEmailViewModel()
    @State private var mode: AuthMode = .signIn

    var body: some View {
        VStack(spacing: 20) {
            Picker("Mode", selection: $mode) {
                ForEach(AuthMode.allCases, id: \.self) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .padding(.top, 8)

            VStack(spacing: 14) {
                TextField("Email", text: $viewModel.email)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.emailAddress)
                    .autocorrectionDisabled()
                    .padding()
                    .background(Color.gray.opacity(0.15))
                    .cornerRadius(12)

                SecureField("Password", text: $viewModel.password)
                    .padding()
                    .background(Color.gray.opacity(0.15))
                    .cornerRadius(12)
            }

            if let errorMessage = viewModel.errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundColor(.red)
                    .multilineTextAlignment(.center)
            }

            Button {
                viewModel.submit(mode: mode)
            } label: {
                ZStack {
                    if viewModel.isWorking {
                        ProgressView().tint(.white)
                    } else {
                        Text(mode.rawValue)
                            .font(.headline)
                    }
                }
                .foregroundStyle(.white)
                .frame(height: 55)
                .frame(maxWidth: .infinity)
                .background(Color.blue)
                .cornerRadius(12)
            }
            .disabled(viewModel.isWorking)

            Spacer()
        }
        .padding()
        .navigationTitle(mode == .signIn ? "Sign In" : "Create Account")
    }
}

struct SignInEmailView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationStack {
            SignInEmailView()
        }
    }
}
