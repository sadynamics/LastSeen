//
//  RootView.swift
//  Decides which top-level flow to show based on auth + onboarding state.
//

import SwiftUI

struct RootView: View {
    @Environment(AuthService.self) private var auth
    @AppStorage("ls.onboarded") private var hasOnboarded: Bool = false

    var body: some View {
        ZStack {
            Theme.Color.background.ignoresSafeArea()
            content
                .transition(.opacity)
        }
        .animation(.easeInOut(duration: 0.25), value: routerKey)
    }

    @ViewBuilder
    private var content: some View {
        switch auth.state {
        case .unknown:
            SplashView()
        case .signedOut:
            if hasOnboarded {
                SignInView()
            } else {
                OnboardingFlow(onFinish: {
                    hasOnboarded = true
                })
            }
        case .signedIn:
            MainTabView()
        }
    }

    private var routerKey: String {
        switch auth.state {
        case .unknown: "unknown"
        case .signedOut: hasOnboarded ? "signin" : "onboarding"
        case .signedIn: "main"
        }
    }
}

private struct SplashView: View {
    var body: some View {
        VStack(spacing: Theme.Spacing.lg) {
            Image(systemName: "eye.fill")
                .font(.system(size: 56))
                .foregroundStyle(Theme.Color.accent)
            Text("LastSeen")
                .font(.title.bold())
                .foregroundStyle(Theme.Color.primaryText)
            ProgressView()
                .controlSize(.small)
                .tint(Theme.Color.accent)
                .padding(.top, Theme.Spacing.md)
        }
    }
}
