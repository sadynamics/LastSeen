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
        .trackScreen("sign_in", className: "SignInView")
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
            }

            VStack(spacing: 8) {
                Text("LastSeen")
                    .font(Theme.Font.display)
                    .foregroundStyle(Theme.Color.primaryText)
                Text("Quietly understand WhatsApp activity\nwith private daily insights.")
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

            Text("By continuing you agree to our Terms and Privacy.")
                .font(Theme.Font.caption)
                .foregroundStyle(Theme.Color.tertiaryText)
                .multilineTextAlignment(.center)
                .padding(.top, Theme.Spacing.sm)
        }
    }

    // MARK: Sign-in handler

    private func handleSignIn(_ result: Result<ASAuthorization, Error>) async {
        errorMessage = nil
        switch result {
        case .failure(let err):
            errorMessage = err.localizedDescription
        case .success(let authorization):
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential else {
                errorMessage = "Couldn't read Apple credential"
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
}
