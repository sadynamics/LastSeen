//
//  SignInView.swift
//

import AuthenticationServices
import SwiftUI

struct SignInView: View {
    @Environment(AuthService.self) private var auth
    @Environment(AppDependencies.self) private var dependencies
    @State private var errorMessage: String?
    @State private var isWorking: Bool = false
    @State private var heroPulse: Bool = false
    /// Alternate username + password sign-in path, used today by App
    /// Review. Surfaced two ways:
    /// 1. A small "Sign in" link below the legal copy. The link is
    ///    hidden by default and only shown when the backend reports
    ///    `reviewerSignInEnabled = true` (which it does iff the
    ///    `REVIEWER_LOGIN_CODE` env var is set on Railway). Unsetting
    ///    that env var post-approval hides the link AND 404s the
    ///    endpoint, with no app resubmission required.
    /// 2. (Backup) Triple-tap on the hero logo — always wired so we
    ///    have a recovery path if anything goes wrong with the config
    ///    fetch on the next submission. Real users won't stumble on it,
    ///    and with the env var unset the sheet's Continue button just
    ///    returns "Sign-in not accepted."
    @State private var showingCredentialsSheet: Bool = false
    @State private var credentialsLinkVisible: Bool = false
    @State private var credentialsUsername: String = ""
    @State private var credentialsPassword: String = ""
    @State private var credentialsError: String?

    var body: some View {
        ZStack {
            AppBackground()

            VStack(spacing: Theme.Spacing.xl) {
                Spacer(minLength: 0)
                hero
                Spacer(minLength: 0)
                actions
            }
            .padding(.horizontal, Theme.Spacing.xl)
            .padding(.bottom, Theme.Spacing.xl)

            if isWorking {
                ZStack {
                    Color.black.opacity(0.55).ignoresSafeArea()
                    ProgressView().tint(.white).scaleEffect(1.2)
                }
            }
        }
        .onAppear { heroPulse = true }
        .task {
            // One-shot probe: ask the backend whether to expose the
            // alternate credentials link. Network failure or 404 keeps
            // the link hidden — the safer default for production users.
            if let cfg = await auth.fetchPublicConfig() {
                credentialsLinkVisible = cfg.reviewerSignInEnabled
            }
        }
        .trackScreen("sign_in", className: "SignInView")
        .sheet(isPresented: $showingCredentialsSheet) {
            credentialsSheet
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
    }

    // MARK: Hero

    private var hero: some View {
        VStack(spacing: Theme.Spacing.lg) {
            ZStack {
                Circle()
                    .stroke(Theme.Color.accent.opacity(0.20), lineWidth: 1)
                    .frame(width: 220, height: 220)
                    .scaleEffect(heroPulse ? 1.08 : 1.0)
                    .opacity(heroPulse ? 0.0 : 0.7)
                    .animation(.easeOut(duration: 2.4).repeatForever(autoreverses: false), value: heroPulse)
                Circle()
                    .stroke(Theme.Color.accent.opacity(0.30), lineWidth: 1)
                    .frame(width: 160, height: 160)
                    .scaleEffect(heroPulse ? 1.12 : 1.0)
                    .opacity(heroPulse ? 0.0 : 0.7)
                    .animation(.easeOut(duration: 2.4).repeatForever(autoreverses: false).delay(0.6), value: heroPulse)
                Circle()
                    .fill(Theme.Gradient.primaryButton)
                    .frame(width: 96, height: 96)
                    .ds(shadow: .glow)
                    .overlay(
                        Image(systemName: "waveform.path.ecg")
                            .font(.system(size: 38, weight: .bold))
                            .foregroundStyle(.white)
                    )
                    // Hidden backup entry. Triple-tapping the logo
                    // opens the same Username + Password sheet that the
                    // visible "Sign in" link does — kept for safety in
                    // case the explicit link gets repositioned in a
                    // future redesign. Backed by `REVIEWER_LOGIN_CODE`,
                    // which 404s when unset.
                    .onTapGesture(count: 3) {
                        openCredentialsSheet()
                    }
            }

            VStack(spacing: 8) {
                Text(L10n.appName)
                    .font(Theme.Font.display)
                    .foregroundStyle(Theme.Color.primaryText)
                Text(L10n.signInTagline)
                    .font(Theme.Font.callout)
                    .foregroundStyle(Theme.Color.secondaryText)
                    .multilineTextAlignment(.center)
            }
        }
    }

    // MARK: Actions

    private var actions: some View {
        VStack(spacing: Theme.Spacing.md) {
            SignInWithAppleButton(.signIn) { request in
                request.requestedScopes = [.email]
            } onCompletion: { result in
                Task { await handleSignIn(result) }
            }
            .signInWithAppleButtonStyle(.white)
            .frame(height: 54)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous))
            .ds(shadow: Theme.Shadow(color: .black.opacity(0.5), radius: 12, x: 0, y: 6))

            if let errorMessage {
                Text(errorMessage)
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.Color.danger)
                    .multilineTextAlignment(.center)
            }

            Text(L10n.signInLegal)
                .font(Theme.Font.caption)
                .foregroundStyle(Theme.Color.tertiaryText)
                .multilineTextAlignment(.center)
                .padding(.top, Theme.Spacing.sm)

            // Discreet alternate sign-in link. Reads as a generic
            // credentials path — real users won't recognise its purpose
            // (they'll keep using Sign in with Apple above), while the
            // reviewer notes spell out the credentials to enter. Only
            // rendered when the backend reports `reviewerSignInEnabled`
            // (i.e. the `REVIEWER_LOGIN_CODE` env var is set on
            // Railway); unsetting that var post-approval hides this
            // from every user without an app resubmission.
            if credentialsLinkVisible {
                Button("Sign in") {
                    openCredentialsSheet()
                }
                .font(Theme.Font.caption)
                .foregroundStyle(Theme.Color.tertiaryText)
                .accessibilityIdentifier("reviewerSignInLink")
                .transition(.opacity)
            }
        }
    }

    private func openCredentialsSheet() {
        credentialsUsername = ""
        credentialsPassword = ""
        credentialsError = nil
        showingCredentialsSheet = true
    }

    // MARK: Sign-in handler

    private func handleSignIn(_ result: Result<ASAuthorization, Error>) async {
        errorMessage = nil
        switch result {
        case .failure(let err):
            errorMessage = err.localizedDescription
        case .success(let authorization):
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential else {
                errorMessage = L10n.signInAppleCredentialError
                return
            }
            isWorking = true
            defer { isWorking = false }
            do {
                try await auth.signIn(with: credential)
                // Now that we have an auth token, kick off the post-sign-in
                // setup: subscriptions, tracking, and crucially the device
                // sync so the backend knows where to send pushes.
                await dependencies.onSignedIn()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    // MARK: Credentials sheet

    private var credentialsSheet: some View {
        ZStack {
            AppBackground()
            ScrollView {
                VStack(spacing: Theme.Spacing.lg) {
                    VStack(spacing: Theme.Spacing.sm) {
                        Image(systemName: "person.crop.circle")
                            .font(.system(size: 34, weight: .semibold))
                            .foregroundStyle(Theme.Color.accent)
                        Text("Sign in")
                            .font(Theme.Font.title)
                            .foregroundStyle(Theme.Color.primaryText)
                        Text("Enter your username and password to continue.")
                            .font(Theme.Font.callout)
                            .foregroundStyle(Theme.Color.secondaryText)
                            .multilineTextAlignment(.center)
                    }

                    VStack(spacing: Theme.Spacing.sm) {
                        TextField("Username", text: $credentialsUsername)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled(true)
                            .textContentType(.username)
                            .keyboardType(.emailAddress)
                            .padding(.horizontal, Theme.Spacing.md)
                            .padding(.vertical, Theme.Spacing.sm)
                            .background(
                                RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
                                    .fill(Color.white.opacity(0.06))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
                                    .stroke(Color.white.opacity(0.10), lineWidth: 1)
                            )
                            .accessibilityIdentifier("reviewerUsernameField")

                        SecureField("Password", text: $credentialsPassword)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled(true)
                            .textContentType(.password)
                            .font(.system(.body, design: .monospaced))
                            .padding(.horizontal, Theme.Spacing.md)
                            .padding(.vertical, Theme.Spacing.sm)
                            .background(
                                RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
                                    .fill(Color.white.opacity(0.06))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
                                    .stroke(Color.white.opacity(0.10), lineWidth: 1)
                            )
                            .accessibilityIdentifier("reviewerPasswordField")
                    }

                    if let credentialsError {
                        Text(credentialsError)
                            .font(Theme.Font.caption)
                            .foregroundStyle(Theme.Color.danger)
                            .multilineTextAlignment(.center)
                    }

                    PrimaryButton(title: "Continue", systemImage: "arrow.right.circle.fill") {
                        Task { await submitCredentials() }
                    }
                    .disabled(
                        credentialsUsername.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            || credentialsPassword.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            || isWorking
                    )
                    .accessibilityIdentifier("reviewerContinueButton")

                    Button("Cancel") { showingCredentialsSheet = false }
                        .font(Theme.Font.callout)
                        .foregroundStyle(Theme.Color.secondaryText)
                }
                .padding(.horizontal, Theme.Spacing.xl)
                .padding(.vertical, Theme.Spacing.xl)
            }
        }
    }

    private func submitCredentials() async {
        let username = credentialsUsername.trimmingCharacters(in: .whitespacesAndNewlines)
        let password = credentialsPassword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !username.isEmpty, !password.isEmpty else { return }
        credentialsError = nil
        isWorking = true
        defer { isWorking = false }
        do {
            try await auth.signInAsReviewer(username: username, password: password)
            await dependencies.onSignedIn()
            showingCredentialsSheet = false
        } catch {
            // Generic message so attackers can't tell whether the
            // endpoint is even enabled.
            credentialsError = "Sign-in not accepted."
        }
    }
}
