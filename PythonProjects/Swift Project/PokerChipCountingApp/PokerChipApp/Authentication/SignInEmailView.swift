import SwiftUI

enum AuthMode: String, CaseIterable {
    case signIn = "Sign in"
    case signUp = "Create account"
}

@MainActor
final class SignInEmailViewModel: ObservableObject {
    @Published var email = ""
    @Published var password = ""
    @Published var errorMessage: String?
    @Published var infoMessage: String?
    @Published var isWorking = false
    /// Mistakes are only pointed out once someone has tried to continue, so
    /// the form doesn't scold them while they're still typing.
    @Published private(set) var showsValidation = false

    /// True when a guest is adding an email to their existing account.
    let isLinking: Bool

    init(isLinking: Bool) {
        self.isLinking = isLinking
    }

    var trimmedEmail: String { email.trimmingCharacters(in: .whitespacesAndNewlines) }

    private var emailLooksValid: Bool {
        trimmedEmail.range(of: #"^[^\s@]+@[^\s@]+\.[^\s@]+$"#, options: .regularExpression) != nil
    }

    func emailProblem() -> String? {
        guard showsValidation else { return nil }
        if trimmedEmail.isEmpty { return "Enter your email address." }
        return emailLooksValid ? nil : "That doesn't look like an email address."
    }

    func passwordProblem(for mode: AuthMode) -> String? {
        guard showsValidation else { return nil }
        if password.isEmpty { return "Enter your password." }
        if mode == .signUp && password.count < 6 { return "Use at least 6 characters." }
        return nil
    }

    func submit(mode: AuthMode, auth: AuthViewModel, onLinked: @escaping () -> Void) {
        showsValidation = true
        infoMessage = nil
        guard emailLooksValid, !password.isEmpty, (mode == .signIn || password.count >= 6) else {
            errorMessage = nil
            return
        }
        errorMessage = nil
        isWorking = true
        let typedEmail = trimmedEmail
        let typedPassword = password
        Task {
            do {
                if isLinking {
                    _ = try await AuthenticationManager.shared.linkEmail(email: typedEmail, password: typedPassword)
                    auth.refreshAccount()
                    onLinked()
                } else {
                    switch mode {
                    case .signIn:
                        _ = try await AuthenticationManager.shared.signIn(email: typedEmail, password: typedPassword)
                    case .signUp:
                        _ = try await AuthenticationManager.shared.createUser(email: typedEmail, password: typedPassword)
                    }
                    // AuthViewModel's Firebase listener moves the app on from here.
                }
            } catch {
                errorMessage = AuthErrorMessage.message(for: error)
            }
            isWorking = false
        }
    }

    func resetPassword() {
        showsValidation = true
        errorMessage = nil
        guard emailLooksValid else {
            infoMessage = nil
            return
        }
        isWorking = true
        let typedEmail = trimmedEmail
        Task {
            do {
                try await AuthenticationManager.shared.sendPasswordReset(email: typedEmail)
                // Same words whether or not an account exists, so this form
                // can't be used to find out who has one.
                infoMessage = "If there's an account for \(typedEmail), we've sent a link to reset the password. Check your inbox."
            } catch {
                errorMessage = AuthErrorMessage.message(for: error)
            }
            isWorking = false
        }
    }
}

struct SignInEmailView: View {
    /// Set when a guest is turning their account into an email account.
    var isLinking = false

    @EnvironmentObject private var auth: AuthViewModel
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel: SignInEmailViewModel
    @State private var mode: AuthMode = .signIn
    @State private var showsPassword = false
    @FocusState private var focus: Field?

    private enum Field { case email, password }

    init(isLinking: Bool = false) {
        self.isLinking = isLinking
        _viewModel = StateObject(wrappedValue: SignInEmailViewModel(isLinking: isLinking))
        _mode = State(initialValue: isLinking ? .signUp : .signIn)
    }

    private var title: String {
        if isLinking { return "Create account" }
        return mode == .signIn ? "Sign in" : "Create account"
    }

    private var actionTitle: String {
        isLinking ? "Save my games to an account" : mode.rawValue
    }

    var body: some View {
        ScrollView {
            VStack(spacing: Spacing.lg) {
                if isLinking {
                    Text("Add an email to your guest account. Everything you've saved stays with it.")
                        .font(.pokerCallout)
                        .foregroundStyle(.pokerTextSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    Picker("Mode", selection: $mode) {
                        ForEach(AuthMode.allCases, id: \.self) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("auth.mode")
                }

                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text("Email").font(.pokerCaption).foregroundStyle(.pokerTextSecondary)
                    TextField(text: $viewModel.email, prompt: placeholder("you@example.com")) {
                        Text("Email")
                    }
                        .textContentType(.emailAddress)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .submitLabel(.next)
                        .focused($focus, equals: .email)
                        .onSubmit { focus = .password }
                        .pokerTextField(isError: viewModel.emailProblem() != nil)
                        .accessibilityIdentifier("auth.emailField")
                    if let problem = viewModel.emailProblem() {
                        fieldProblem(problem)
                    }
                }

                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text("Password").font(.pokerCaption).foregroundStyle(.pokerTextSecondary)
                    HStack(spacing: Spacing.sm) {
                        Group {
                            if showsPassword {
                                TextField(text: $viewModel.password, prompt: placeholder("Password")) {
                                    Text("Password")
                                }
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                            } else {
                                SecureField(text: $viewModel.password, prompt: placeholder("Password")) {
                                    Text("Password")
                                }
                            }
                        }
                        .textContentType(mode == .signIn && !isLinking ? .password : .newPassword)
                        .submitLabel(.go)
                        .focused($focus, equals: .password)
                        .onSubmit(submit)
                        .accessibilityIdentifier("auth.passwordField")

                        Button {
                            showsPassword.toggle()
                        } label: {
                            Image(systemName: showsPassword ? "eye.slash.fill" : "eye.fill")
                                .foregroundStyle(.pokerTextSecondary)
                                .frame(width: Spacing.minTapTarget, height: Spacing.minTapTarget)
                        }
                        .accessibilityLabel(showsPassword ? "Hide password" : "Show password")
                    }
                    .pokerTextField(isError: viewModel.passwordProblem(for: mode) != nil)

                    if let problem = viewModel.passwordProblem(for: mode) {
                        fieldProblem(problem)
                    } else if mode == .signUp {
                        Text("At least 6 characters.")
                            .font(.pokerFootnote)
                            .foregroundStyle(.pokerTextTertiary)
                    }
                }

                if let message = viewModel.errorMessage {
                    InlineBanner(kind: .error, message: message)
                }
                if let message = viewModel.infoMessage {
                    InlineBanner(kind: .success, message: message)
                }

                PokerButton(title: actionTitle, isLoading: viewModel.isWorking, action: submit)
                    .accessibilityIdentifier("auth.submit")

                if mode == .signIn && !isLinking {
                    PokerButton(title: "Forgot password?", kind: .quiet, isEnabled: !viewModel.isWorking) {
                        viewModel.resetPassword()
                    }
                    .accessibilityIdentifier("auth.forgot")
                }
            }
            .padding(.horizontal, Spacing.gutter)
            .padding(.vertical, Spacing.lg)
            .pokerReadableWidth()
        }
        .scrollDismissesKeyboard(.interactively)
        .background(PokerBackground())
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: mode) { _ in
            viewModel.errorMessage = nil
            viewModel.infoMessage = nil
        }
    }

    private func submit() {
        focus = nil
        viewModel.submit(mode: mode, auth: auth) { dismiss() }
    }

    /// Placeholders in the same quiet colour on every field, rather than
    /// whatever the system picks for the field's content type.
    private func placeholder(_ text: String) -> Text {
        Text(text).foregroundColor(Color.pokerTextTertiary)
    }

    private func fieldProblem(_ text: String) -> some View {
        Label(text, systemImage: "exclamationmark.circle.fill")
            .font(.pokerFootnote)
            .foregroundStyle(.pokerNegative)
    }
}

struct SignInEmailView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationStack {
            SignInEmailView()
                .environmentObject(AuthViewModel())
        }
    }
}
