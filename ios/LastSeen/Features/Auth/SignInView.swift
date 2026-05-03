//
//  SignInView.swift
//

import AuthenticationServices
import SwiftUI

struct SignInView: View {
    @Environment(AuthService.self) private var auth
    @State private var errorMessage: String?
    @State private var isWorking: Bool = false

    var body: some View {
        ZStack {
            Theme.Color.background.ignoresSafeArea()
            VStack(spacing: Theme.Spacing.xl) {
                Spacer()
                VStack(spacing: Theme.Spacing.md) {
                    Image(systemName: "eye.fill")
                        .font(.system(size: 64))
                        .foregroundStyle(Theme.Color.accent)
                    Text("LastSeen")
                        .font(.largeTitle.bold())
                        .foregroundStyle(Theme.Color.primaryText)
                    Text("Sign in to start tracking activity.")
                        .font(.callout)
                        .foregroundStyle(Theme.Color.secondaryText)
                }
                Spacer()
                VStack(spacing: Theme.Spacing.md) {
                    SignInWithAppleButton(.signIn) { request in
                        request.requestedScopes = [.email]
                    } onCompletion: { result in
                        Task { await handleSignIn(result) }
                    }
                    .signInWithAppleButtonStyle(.white)
                    .frame(height: 52)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundStyle(Theme.Color.danger)
                            .multilineTextAlignment(.center)
                    }
                }
                .padding(.bottom, Theme.Spacing.xl)
            }
            .padding(Theme.Spacing.xl)

            if isWorking {
                ZStack {
                    Color.black.opacity(0.4).ignoresSafeArea()
                    ProgressView().tint(.white)
                }
            }
        }
    }

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
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}
