//
//  SettingsView.swift
//  PokerChipApp
//
//  Account (sign out, delete, add an email to a guest account), preferences,
//  and About. Apple requires account deletion to be possible from inside the
//  app (Guideline 5.1.1(v)), so it lives here rather than behind a website.
//

import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var auth: AuthViewModel
    @EnvironmentObject private var nightStore: NightStore
    @EnvironmentObject private var nightSync: NightSync

    @AppStorage(PrefKey.haptics) private var hapticsEnabled = true
    @AppStorage(PrefKey.colorBlindChips) private var colorBlindChips = false
    @AppStorage(PrefKey.guidedCamera) private var guidedCamera = true
    @AppStorage(PrefKey.weeklyHoursCap) private var weeklyHoursCap = AppPreferences.defaultWeeklyHoursCap
    @AppStorage(PrefKey.weeklyLossLimit) private var weeklyLossLimit = 0.0
    @AppStorage(PrefKey.sessionReminderHours) private var reminderHours = 0.0
    @AppStorage(PrefKey.coolOffUntil) private var coolOffUntil = 0.0

    @State private var reminders = SessionReminders()
    @State private var notificationsBlocked = false
    @State private var breakToConfirm: HealthyPlay.Break?

    @State private var confirmSignOut = false
    @State private var confirmDelete = false
    @State private var isDeleting = false
    @State private var deleteError: String?

    private var isGuest: Bool { auth.account?.isAnonymous ?? false }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.xl) {
                accountSection
                backupSection
                preferencesSection
                healthySection
                privacySection
                aboutSection
            }
            .padding(.horizontal, Spacing.gutter)
            .padding(.vertical, Spacing.lg)
            .pokerReadableWidth()
        }
        .background(PokerBackground())
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog(
            isGuest ? "Sign out of the guest account?" : "Sign out?",
            isPresented: $confirmSignOut,
            titleVisibility: .visible
        ) {
            Button("Sign out", role: .destructive) { auth.signOut() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(isGuest
                 ? "Your nights stay on this iPhone, but a guest account's backup can't be recovered after you sign out. Add an email first to keep it."
                 : "You can sign back in any time.")
        }
        .confirmationDialog(
            "Delete your account?",
            isPresented: $confirmDelete,
            titleVisibility: .visible
        ) {
            Button("Delete account", role: .destructive) { deleteAccount() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This permanently deletes your account, your saved games and any chip photos. It can't be undone.")
        }
    }

    // MARK: Sections

    private var accountSection: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            SectionHeader(title: "Account")

            HStack(spacing: Spacing.lg) {
                Image(systemName: isGuest ? "person.fill.questionmark" : "person.crop.circle.fill")
                    .font(.title2)
                    .foregroundStyle(Color.pokerGold)
                    .frame(width: 40, height: 40)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text(isGuest ? "Guest" : (auth.account?.email ?? "Signed in"))
                        .font(.pokerHeadline)
                        .foregroundStyle(.pokerTextPrimary)
                    Text(isGuest
                         ? "Add an email to keep your games if you switch phones."
                         : "Your games are saved to this account.")
                        .font(.pokerFootnote)
                        .foregroundStyle(.pokerTextSecondary)
                }
                Spacer(minLength: 0)
            }
            .pokerCard()
            .accessibilityElement(children: .combine)

            if let deleteError {
                InlineBanner(kind: .error, message: deleteError)
            }

            if isGuest {
                NavigationLink {
                    SignInEmailView(isLinking: true)
                } label: {
                    Label("Add an email", systemImage: "envelope.fill")
                        .pokerSecondaryLabel()
                }
                .accessibilityIdentifier("settings.addEmail")
            }

            PokerButton(title: "Sign out", kind: .secondary) { confirmSignOut = true }
                .accessibilityIdentifier("settings.signOut")

            PokerButton(title: "Delete account", kind: .destructive, isLoading: isDeleting) {
                confirmDelete = true
            }
            .accessibilityIdentifier("settings.deleteAccount")
        }
    }

    private var backupSection: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            SectionHeader(title: "Backup")

            HStack(spacing: Spacing.lg) {
                Image(systemName: backupIcon)
                    .font(.title2)
                    .foregroundStyle(Color.pokerGold)
                    .frame(width: 40, height: 40)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text(backupTitle)
                        .font(.pokerHeadline)
                        .foregroundStyle(.pokerTextPrimary)
                    Text(backupDetail)
                        .font(.pokerFootnote)
                        .foregroundStyle(.pokerTextSecondary)
                }
                Spacer(minLength: 0)
            }
            .pokerCard()
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("settings.backup")

            PokerButton(title: "Back up now", systemImage: "arrow.triangle.2.circlepath", kind: .secondary, isLoading: nightSync.status == .syncing) {
                Task { await nightSync.sync(uid: auth.account?.uid) }
            }
            .accessibilityIdentifier("settings.backupNow")
        }
    }

    private var backupIcon: String {
        switch nightSync.status {
        case .idle: return nightStore.pendingCount == 0 ? "checkmark.icloud" : "icloud.and.arrow.up"
        case .syncing: return "arrow.triangle.2.circlepath.icloud"
        case .offline: return "icloud.slash"
        case .unavailable, .needsSignIn, .failed: return "exclamationmark.icloud"
        }
    }

    private var backupTitle: String {
        switch nightSync.status {
        case .idle: return nightStore.pendingCount == 0 ? "Backed up" : "Waiting to back up"
        case .syncing: return "Backing up…"
        case .offline: return "Offline"
        case .unavailable: return "Backup isn't available yet"
        case .needsSignIn: return "Sign in to back up"
        case .failed: return "Backup paused"
        }
    }

    private var backupDetail: String {
        let waiting = nightStore.pendingCount
        switch nightSync.status {
        case .idle:
            if waiting > 0 { return "\(waiting) change\(waiting == 1 ? "" : "s") will go to your account shortly." }
            if let last = nightSync.lastSyncedAt { return "Your nights are on your account. Checked \(last.formatted(.relative(presentation: .named)))." }
            return "Your nights are saved on this iPhone and on your account."
        case .syncing:
            return "Your nights are safe on this iPhone while this happens."
        case .offline:
            return waiting > 0
                ? "\(waiting) change\(waiting == 1 ? " is" : "s are") saved on this iPhone and will back up when you're online."
                : "Everything is saved on this iPhone."
        case .unavailable:
            return "Your nights are safe on this iPhone. They'll back up once the service is available."
        case .needsSignIn:
            return "Your nights are safe on this iPhone."
        case .failed(let message):
            return message
        }
    }

    private var preferencesSection: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            SectionHeader(title: "Preferences")

            VStack(spacing: Spacing.lg) {
                Toggle(isOn: $hapticsEnabled) {
                    toggleLabel("Haptics", "A light tap on buttons and counts.")
                }
                .accessibilityIdentifier("settings.haptics")

                Divider().overlay(Color.white.opacity(0.12))

                Toggle(isOn: $colorBlindChips) {
                    toggleLabel("Colour-blind-friendly chips", "Adds a letter to every chip so colours never have to be told apart.")
                }
                .accessibilityIdentifier("settings.colorBlind")

                Divider().overlay(Color.white.opacity(0.12))

                Toggle(isOn: $guidedCamera) {
                    toggleLabel("Camera tips", "Live tips on the camera screen: hold the phone flatter, lower or steadier, or add light. Turn off to use the standard camera.")
                }
                .accessibilityIdentifier("settings.guidedCamera")
            }
            .tint(.pokerGold)
            .pokerCard()
        }
    }

    // MARK: Healthy play

    private var coolOffEnd: Date? {
        coolOffUntil > Date().timeIntervalSince1970 ? Date(timeIntervalSince1970: coolOffUntil) : nil
    }

    private var healthySection: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            SectionHeader(title: "Healthy play")

            Text("Poker is best when it stays fun. These are yours to set, change or ignore — they stay on this iPhone.")
                .font(.pokerFootnote)
                .foregroundStyle(.pokerTextSecondary)

            VStack(spacing: Spacing.lg) {
                Stepper(value: $weeklyHoursCap, in: 5...60, step: 1) {
                    toggleLabel("Weekly time limit", "\(Int(weeklyHoursCap)) hours a week. Poker Health wears the chip down towards it, and you'll get a gentle word if a week goes past it.")
                }
                .accessibilityIdentifier("settings.weeklyCap")

                Divider().overlay(Color.white.opacity(0.12))

                Toggle(isOn: Binding(get: { weeklyLossLimit > 0 }, set: { weeklyLossLimit = $0 ? 100 : 0 })) {
                    toggleLabel("Weekly loss limit", weeklyLossLimit > 0
                        ? "A gentle word if you're down \(Money.format(weeklyLossLimit)) or more over seven days."
                        : "Off. Turn on to get a gentle word when a bad week gets expensive.")
                }
                .accessibilityIdentifier("settings.lossLimit")

                if weeklyLossLimit > 0 {
                    Stepper(value: $weeklyLossLimit, in: 10...1_000, step: 10) {
                        Text(Money.format(weeklyLossLimit)).font(.pokerNumeric(.body)).foregroundStyle(.pokerTextPrimary)
                    }
                    .accessibilityLabel("Weekly loss limit")
                    .accessibilityIdentifier("settings.lossLimitAmount")
                }

                Divider().overlay(Color.white.opacity(0.12))

                Picker(selection: $reminderHours) {
                    Text("Off").tag(0.0)
                    ForEach([1.0, 2.0, 3.0, 4.0, 6.0], id: \.self) { hours in
                        Text("After \(Int(hours)) hour\(hours == 1 ? "" : "s")").tag(hours)
                    }
                } label: {
                    toggleLabel("Break reminder", "A notification during a night once you've been playing this long. Time on a break doesn't count.")
                }
                .pickerStyle(.menu)
                .accessibilityIdentifier("settings.reminder")
                .onChange(of: reminderHours) { hours in
                    guard hours > 0 else { return }
                    Task { notificationsBlocked = !(await reminders.requestPermission()) }
                }

                if reminderHours > 0 && notificationsBlocked {
                    InlineBanner(
                        kind: .warning,
                        message: "Notifications are turned off for this app, so the reminder can't appear. You can allow them in Settings.",
                        actionTitle: "Open Settings"
                    ) {
                        if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                    }
                }
            }
            .tint(.pokerGold)
            .pokerCard()
            .task { notificationsBlocked = reminderHours > 0 ? !(await reminders.isAllowed()) : false }

            breakCard

            helpCard
        }
    }

    private var breakCard: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Label("Take a break", systemImage: "moon.zzz.fill")
                .font(.pokerHeadline)
                .foregroundStyle(.pokerTextPrimary)

            if let end = coolOffEnd {
                Text("You're on a break until \(end.formatted(date: .abbreviated, time: .shortened)). New nights are paused; your history and any night already in progress are all still here. It can't be cut short — that's what makes it work.")
                    .font(.pokerFootnote)
                    .foregroundStyle(.pokerTextSecondary)
                    .accessibilityIdentifier("settings.breakActive")
            } else {
                Text("Step away on purpose. No new nights can be started for a while, but you can still finish one in progress and look at your history.")
                    .font(.pokerFootnote)
                    .foregroundStyle(.pokerTextSecondary)
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: Spacing.sm) { breakButtons }
                    VStack(spacing: Spacing.sm) { breakButtons }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .pokerCard()
        .confirmationDialog(
            "Take a \(breakToConfirm?.title ?? "") break?",
            isPresented: Binding(get: { breakToConfirm != nil }, set: { if !$0 { breakToConfirm = nil } }),
            titleVisibility: .visible
        ) {
            Button("Start the break") {
                if let length = breakToConfirm {
                    coolOffUntil = HealthyPlay.coolOffEnd(for: length).timeIntervalSince1970
                }
                breakToConfirm = nil
            }
            .accessibilityIdentifier("settings.breakConfirm")
            Button("Not now", role: .cancel) { breakToConfirm = nil }
        } message: {
            if let length = breakToConfirm {
                Text("You won't be able to start a new night until \(HealthyPlay.coolOffEnd(for: length).formatted(date: .abbreviated, time: .shortened)). This can't be undone early.")
            }
        }
    }

    @ViewBuilder
    private var breakButtons: some View {
        ForEach(HealthyPlay.Break.allCases) { length in
            PokerButton(title: length.title, kind: .secondary) { breakToConfirm = length }
                .accessibilityIdentifier("settings.break.\(length.title)")
        }
    }

    private var helpCard: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Label("If it stops being fun", systemImage: "heart.fill")
                .font(.pokerHeadline)
                .foregroundStyle(.pokerTextPrimary)
                .accessibilityIdentifier("settings.help")

            Text("Plenty of people find poker harder to put down than they expected. If it's weighing on you or someone close to you, talking to someone helps. It's free, private, and nobody will judge.")
                .font(.pokerFootnote)
                .foregroundStyle(.pokerTextSecondary)

            ForEach(HelplineDirectory.helplines(for: Locale.current.region?.identifier)) { line in
                helplineRow(line)
            }

            Text("Numbers checked \(HelplineDirectory.verifiedOn).")
                .font(.pokerCaption)
                .foregroundStyle(.pokerTextTertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .pokerCard()
    }

    private func helplineRow(_ line: Helpline) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text(line.name).font(.pokerHeadline).foregroundStyle(.pokerTextPrimary)
            Text(line.detail).font(.pokerFootnote).foregroundStyle(.pokerTextSecondary)
            if let url = line.callURL, let display = line.phoneDisplay {
                Link(destination: url) {
                    Label("Call \(display)", systemImage: "phone.fill").pokerSecondaryLabel()
                }
                .accessibilityIdentifier("settings.help.call")
            }
            if let url = line.textURL {
                Link(destination: url) {
                    Label("Send a text", systemImage: "message.fill").pokerSecondaryLabel()
                }
                .accessibilityIdentifier("settings.help.text")
            }
            if let url = line.websiteURL {
                Link(destination: url) {
                    Label(line.phoneDisplay == nil ? "Open the list" : "Chat or read more online", systemImage: "arrow.up.right")
                        .pokerSecondaryLabel()
                }
                .accessibilityIdentifier("settings.help.web")
            }
        }
        .padding(.top, Spacing.xs)
    }

    private var privacySection: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            SectionHeader(title: "Your data")
            Text("Your nights — who played, what each person put in and took out, where, and any notes — are kept on this iPhone and, when you're signed in, backed up to your account. Deleting a night removes it from the backup too, along with the photos taken at its cash-outs. Photos are sent securely to the counting service and kept private to your account.")
                .font(.pokerFootnote)
                .foregroundStyle(.pokerTextSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .pokerCard()
        }
    }

    private var aboutSection: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            SectionHeader(title: "About")

            VStack(spacing: Spacing.lg) {
                HStack {
                    Text("Version").foregroundStyle(.pokerTextPrimary)
                    Spacer()
                    Text(AppEnvironment.versionString)
                        .font(.pokerNumeric(.body, weight: .regular))
                        .foregroundStyle(.pokerTextSecondary)
                }

                if let email = SupportConfig.supportEmail, let url = URL(string: "mailto:\(email)") {
                    Divider().overlay(Color.white.opacity(0.12))
                    linkRow("Contact support", url)
                }
                if let url = SupportConfig.privacyPolicyURL {
                    Divider().overlay(Color.white.opacity(0.12))
                    linkRow("Privacy policy", url)
                }
                if let url = SupportConfig.termsURL {
                    Divider().overlay(Color.white.opacity(0.12))
                    linkRow("Terms of use", url)
                }
            }
            .pokerCard()

            Text("Chip Counter is for keeping track of home games. It doesn't handle money or take bets.")
                .font(.pokerFootnote)
                .foregroundStyle(.pokerTextTertiary)
        }
    }

    // MARK: Pieces

    private func toggleLabel(_ title: String, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text(title).font(.pokerHeadline).foregroundStyle(.pokerTextPrimary)
            Text(detail).font(.pokerFootnote).foregroundStyle(.pokerTextSecondary)
        }
    }

    private func linkRow(_ title: String, _ url: URL) -> some View {
        Link(destination: url) {
            HStack {
                Text(title).foregroundStyle(.pokerTextPrimary)
                Spacer()
                Image(systemName: "arrow.up.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.pokerTextTertiary)
            }
            .frame(minHeight: Spacing.minTapTarget)
        }
    }

    // MARK: Actions

    private func deleteAccount() {
        deleteError = nil
        isDeleting = true
        Task {
            do {
                // Server first, device second: if the server call fails (say,
                // offline) nothing local is touched and the account still exists.
                try await auth.deleteAccount()
                // The account and everything on the server is gone; nothing of it stays on the phone either.
                nightStore.reset()
            } catch {
                deleteError = deletionMessage(for: error)
            }
            isDeleting = false
        }
    }

    private func deletionMessage(for error: Error) -> String {
        if let apiError = error as? ChipVisionAPIError {
            switch apiError {
            case .offline, .timedOut, .unreachable:
                return "Couldn't reach the server, so your account wasn't deleted. Check your connection and try again."
            case .unauthorized:
                return "Your sign-in has expired. Sign in again, then delete your account."
            default:
                return "Your account wasn't deleted: \(apiError.localizedDescription)"
            }
        }
        return "Your account wasn't deleted: \(error.localizedDescription)"
    }
}

struct SettingsView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationStack {
            SettingsView()
                .environmentObject(AuthViewModel())
                .environmentObject(NavigationCoordinator())
                .environmentObject(NightStore(repository: MemoryNightRepository()))
                .environmentObject(NightSync(store: NightStore(repository: MemoryNightRepository())))
        }
    }
}
