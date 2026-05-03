//
//  OnboardingFlow.swift
//  Three-step onboarding: value prop -> consent gate -> notifications.
//  The consent gate is required for App Review; copy reinforces the
//  "monitor your own / family with consent" framing.
//

import SwiftUI

struct OnboardingFlow: View {
    @Environment(NotificationService.self) private var notifications
    @State private var step: Int = 0
    @State private var hasAcknowledgedConsent: Bool = false

    let onFinish: () -> Void

    var body: some View {
        ZStack {
            Theme.Color.background.ignoresSafeArea()
            VStack {
                progress
                Spacer(minLength: 0)
                content
                    .id(step)
                    .transition(.asymmetric(
                        insertion: .move(edge: .trailing).combined(with: .opacity),
                        removal: .move(edge: .leading).combined(with: .opacity))
                    )
                Spacer(minLength: 0)
                buttons
            }
            .padding(Theme.Spacing.xl)
        }
        .animation(.easeInOut(duration: 0.25), value: step)
    }

    private var progress: some View {
        HStack(spacing: 4) {
            ForEach(0..<3) { i in
                Capsule()
                    .fill(i <= step ? Theme.Color.accent : Theme.Color.surfaceElevated)
                    .frame(height: 4)
            }
        }
        .padding(.top, Theme.Spacing.lg)
    }

    @ViewBuilder
    private var content: some View {
        switch step {
        case 0: valueProp
        case 1: consent
        default: notificationsStep
        }
    }

    private var valueProp: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            Image(systemName: "chart.bar.xaxis")
                .font(.system(size: 56))
                .foregroundStyle(Theme.Color.accent)
            Text("Understand your family's screen time on WhatsApp")
                .font(.title.bold())
                .foregroundStyle(Theme.Color.primaryText)
            Text("LastSeen quietly tracks WhatsApp activity across the day so you can have informed conversations about phone use.")
                .font(.body)
                .foregroundStyle(Theme.Color.secondaryText)
            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                bullet(icon: "clock.fill", text: "Daily and weekly online minutes")
                bullet(icon: "bell.badge.fill", text: "Optional notifications when activity changes")
                bullet(icon: "lock.fill", text: "End-to-end encrypted account, no contacts uploaded")
            }
            .padding(.top, Theme.Spacing.md)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var consent: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            Image(systemName: "person.2.shield.checkmark.fill")
                .font(.system(size: 56))
                .foregroundStyle(Theme.Color.warning)
            Text("Use this app responsibly")
                .font(.title.bold())
                .foregroundStyle(Theme.Color.primaryText)
            Text("LastSeen is for tracking accounts you own, your minor children, or family members who have given you explicit consent to monitor their activity.")
                .font(.body)
                .foregroundStyle(Theme.Color.secondaryText)
            Card {
                Toggle(isOn: $hasAcknowledgedConsent) {
                    Text("I confirm I will only track accounts I own or have permission to monitor.")
                        .font(.callout)
                        .foregroundStyle(Theme.Color.primaryText)
                        .multilineTextAlignment(.leading)
                }
                .tint(Theme.Color.accent)
            }
            Text("Tracking someone without their consent may violate local laws.")
                .font(.caption)
                .foregroundStyle(Theme.Color.tertiaryText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var notificationsStep: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            Image(systemName: "bell.badge.fill")
                .font(.system(size: 56))
                .foregroundStyle(Theme.Color.accent)
            Text("Get a daily summary")
                .font(.title.bold())
                .foregroundStyle(Theme.Color.primaryText)
            Text("We'll send a once-a-day report by default. Real-time alerts can be turned on later in Settings.")
                .font(.body)
                .foregroundStyle(Theme.Color.secondaryText)
            Spacer().frame(height: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var buttons: some View {
        VStack(spacing: Theme.Spacing.md) {
            switch step {
            case 0:
                PrimaryButton(title: "Continue") { step = 1 }
            case 1:
                PrimaryButton(title: "Agree & continue", isDisabled: !hasAcknowledgedConsent) {
                    step = 2
                }
            default:
                PrimaryButton(title: "Allow notifications", systemImage: "bell.fill") {
                    Task {
                        _ = await notifications.requestAuthorizationAndRegister()
                        onFinish()
                    }
                }
                Button("Skip for now") { onFinish() }
                    .foregroundStyle(Theme.Color.secondaryText)
            }
        }
    }

    private func bullet(icon: String, text: String) -> some View {
        HStack(alignment: .top, spacing: Theme.Spacing.md) {
            Image(systemName: icon)
                .foregroundStyle(Theme.Color.accent)
                .frame(width: 24)
            Text(text)
                .foregroundStyle(Theme.Color.primaryText)
                .font(.callout)
        }
    }
}
