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
    /// App Review login sheet. Surfaced two ways:
    /// 1. A small "App Reviewer Sign-In" link below the legal copy. This
    ///    link is hidden by default and only shown when the backend
    ///    reports `reviewerSignInEnabled = true` (which it does iff the
    ///    `REVIEWER_LOGIN_CODE` env var is set on Railway). Unsetting
    ///    that env var post-approval hides the link AND 404s the
    ///    endpoint, with no app resubmission required.
    /// 2. (Backup) Triple-tap on the hero logo — always wired so we
    ///    have a recovery path if anything goes wrong with the config
    ///    fetch on the next submission. Real users won't stumble on it,
    ///    and with the env var unset the sheet's Continue button just
    ///    returns "Sign-in not accepted."
    @State private var showingReviewerSheet: Bool = false
    @State private var reviewerLinkVisible: Bool = false
    @State private var reviewerUsername: String = ""
    @State private var reviewerPassword: String = ""
    @State private var reviewerError: String?

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
            // reviewer link. Network failure or 404 keeps the link
            // hidden — the safer default for production users.
            if let cfg = await auth.fetchPublicConfig() {
                reviewerLinkVisible = cfg.reviewerSignInEnabled
            }
        }
        .trackScreen("sign_in", className: "SignInView")
        .sheet(isPresented: $showingReviewerSheet) {
            reviewerCredentialsSheet
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
                    // App Review backup entry. Triple-tapping the logo
                    // opens the same Username + Password sheet that the
                    // "App Reviewer Sign-In" link does — kept for safety
                    // in case the explicit link gets repositioned in a
                    // future redesign. Backed by `REVIEWER_LOGIN_CODE`,
                    // which 404s when unset.
                    .onTapGesture(count: 3) {
                        openReviewerSheet()
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

            // Discreet but discoverable entry for App Review. Labelled
            // as a plain "Sign in" link to look like a generic alternate
            // auth path — real users won't recognise its purpose, while
            // Apple's reviewer notes tell the tester exactly which link
            // to tap and the credentials to enter. Only rendered when
            // the backend reports `reviewerSignInEnabled` (i.e. the
            // `REVIEWER_LOGIN_CODE` env var is set on Railway); unsetting
            // that var post-approval hides this from every user without
            // an app resubmission.
            if reviewerLinkVisible {
                Button("Sign in") {
                    openReviewerSheet()
                }
                .font(Theme.Font.caption)
                .foregroundStyle(Theme.Color.tertiaryText)
                .accessibilityIdentifier("reviewerSignInLink")
                .transition(.opacity)
            }
        }
    }

    private func openReviewerSheet() {
        reviewerUsername = ""
        reviewerPassword = ""
        reviewerError = nil
        showingReviewerSheet = true
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

    // MARK: App Review reviewer login sheet

    private var reviewerCredentialsSheet: some View {
        ZStack {
            AppBackground()
            ScrollView {
                VStack(spacing: Theme.Spacing.lg) {
                    VStack(spacing: Theme.Spacing.sm) {
                        Image(systemName: "lock.shield.fill")
                            .font(.system(size: 34, weight: .semibold))
                            .foregroundStyle(Theme.Color.accent)
                        Text("App Reviewer Sign-In")
                            .font(Theme.Font.title)
                            .foregroundStyle(Theme.Color.primaryText)
                        Text("Enter the username and password from App Store Connect → Sign-In Information.")
                            .font(Theme.Font.callout)
                            .foregroundStyle(Theme.Color.secondaryText)
                            .multilineTextAlignment(.center)
                    }

                    VStack(spacing: Theme.Spacing.sm) {
                        TextField("Username", text: $reviewerUsername)
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

                        SecureField("Password", text: $reviewerPassword)
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

                    if let reviewerError {
                        Text(reviewerError)
                            .font(Theme.Font.caption)
                            .foregroundStyle(Theme.Color.danger)
                            .multilineTextAlignment(.center)
                    }

                    PrimaryButton(title: "Continue", systemImage: "arrow.right.circle.fill") {
                        Task { await submitReviewerCredentials() }
                    }
                    .disabled(
                        reviewerUsername.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            || reviewerPassword.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            || isWorking
                    )
                    .accessibilityIdentifier("reviewerContinueButton")

                    Button("Cancel") { showingReviewerSheet = false }
                        .font(Theme.Font.callout)
                        .foregroundStyle(Theme.Color.secondaryText)
                }
                .padding(.horizontal, Theme.Spacing.xl)
                .padding(.vertical, Theme.Spacing.xl)
            }
        }
    }

    private func submitReviewerCredentials() async {
        let username = reviewerUsername.trimmingCharacters(in: .whitespacesAndNewlines)
        let password = reviewerPassword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !username.isEmpty, !password.isEmpty else { return }
        reviewerError = nil
        isWorking = true
        defer { isWorking = false }
        do {
            try await auth.signInAsReviewer(username: username, password: password)
            await dependencies.onSignedIn()
            showingReviewerSheet = false
        } catch {
            // Generic message so attackers can't tell whether the
            // endpoint is even enabled.
            reviewerError = "Sign-in not accepted."
        }
    }
}
