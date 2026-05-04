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
            AppBackground()
            VStack(spacing: 0) {
                progress
                    .padding(.top, Theme.Spacing.lg)
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
        .animation(Theme.Motion.snap, value: step)
        .onAppear {
            LSAnalytics.shared.log(.onboardingStarted)
            LSAnalytics.shared.log(.onboardingStepViewed(step: 0, name: "value_prop"))
        }
        .onChange(of: step) { _, newValue in
            let name = ["value_prop", "consent", "notifications"][newValue]
            LSAnalytics.shared.log(.onboardingStepViewed(step: newValue, name: name))
        }
    }

    // MARK: Progress

    private var progress: some View {
        HStack(spacing: 6) {
            ForEach(0..<3) { i in
                Capsule()
                    .fill(i <= step
                        ? AnyShapeStyle(Theme.Gradient.primaryButton)
                        : AnyShapeStyle(Color.white.opacity(0.10)))
                    .frame(height: 4)
            }
        }
    }

    // MARK: Content

    @ViewBuilder
    private var content: some View {
        switch step {
        case 0: valueProp
        case 1: consent
        default: notificationsStep
        }
    }

    private var valueProp: some View {
        StepLayout(
            iconBadge: AnyView(
                heroIcon(systemImage: "waveform.path.ecg",
                         tint: Theme.Color.accent)
            ),
            title: "Insightful, private activity tracking",
            subtitle: "LastSeen quietly tracks WhatsApp activity across the day so you can have informed conversations about phone use."
        ) {
            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                bullet(icon: "clock.fill", tint: Theme.Color.accent,
                       text: "Daily and weekly online minutes")
                bullet(icon: "bell.badge.fill", tint: Theme.Color.tintMint,
                       text: "Optional alerts when activity changes")
                bullet(icon: "lock.shield.fill", tint: Theme.Color.tintAmber,
                       text: "Encrypted account, no contacts uploaded")
            }
            .padding(.top, Theme.Spacing.sm)
        }
    }

    private var consent: some View {
        StepLayout(
            iconBadge: AnyView(
                heroIcon(systemImage: "person.2.shield.checkmark.fill",
                         tint: Theme.Color.tintAmber)
            ),
            title: "Use this app responsibly",
            subtitle: "LastSeen is for tracking accounts you own, your minor children, or family members who have given you explicit consent."
        ) {
            Card {
                Toggle(isOn: $hasAcknowledgedConsent) {
                    Text("I confirm I will only track accounts I own or have permission to monitor.")
                        .font(Theme.Font.callout)
                        .foregroundStyle(Theme.Color.primaryText)
                        .multilineTextAlignment(.leading)
                }
                .tint(Theme.Color.accent)
            }

            HStack(spacing: 8) {
                Image(systemName: "info.circle.fill")
                    .foregroundStyle(Theme.Color.tertiaryText)
                Text("Tracking someone without their consent may violate local laws.")
                    .foregroundStyle(Theme.Color.tertiaryText)
            }
            .font(Theme.Font.caption)
        }
    }

    private var notificationsStep: some View {
        StepLayout(
            iconBadge: AnyView(
                heroIcon(systemImage: "bell.badge.fill",
                         tint: Theme.Color.accentSecondary)
            ),
            title: "Get a daily summary",
            subtitle: "We'll send a once-a-day report by default. Real-time alerts can be turned on later in Settings."
        ) {
            Card {
                VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                    bullet(icon: "sun.max.fill", tint: Theme.Color.tintAmber,
                           text: "Daily summary at 9pm local time")
                    bullet(icon: "circle.dotted", tint: Theme.Color.online,
                           text: "Live online / offline status")
                    bullet(icon: "moon.fill", tint: Theme.Color.accentSecondary,
                           text: "Quiet hours, fully customizable")
                }
            }
        }
    }

    // MARK: Buttons

    @ViewBuilder
    private var buttons: some View {
        VStack(spacing: Theme.Spacing.md) {
            switch step {
            case 0:
                PrimaryButton(title: "Continue", systemImage: "arrow.right") { step = 1 }
            case 1:
                PrimaryButton(title: "Agree & continue",
                              systemImage: "checkmark",
                              isDisabled: !hasAcknowledgedConsent) {
                    LSAnalytics.shared.log(.onboardingConsentGiven)
                    step = 2
                }
            default:
                PrimaryButton(title: "Allow notifications", systemImage: "bell.fill") {
                    Task {
                        _ = await notifications.requestAuthorizationAndRegister()
                        LSAnalytics.shared.log(.onboardingCompleted)
                        onFinish()
                    }
                }
                Button("Skip for now") {
                    LSAnalytics.shared.log(.onboardingCompleted)
                    onFinish()
                }
                    .font(Theme.Font.callout.weight(.medium))
                    .foregroundStyle(Theme.Color.secondaryText)
            }
        }
        .padding(.bottom, Theme.Spacing.sm)
    }

    // MARK: Building blocks

    private func bullet(icon: String, tint: Color, text: String) -> some View {
        HStack(spacing: Theme.Spacing.md) {
            IconBadge(systemImage: icon, tint: tint, size: 32)
            Text(text)
                .foregroundStyle(Theme.Color.primaryText)
                .font(Theme.Font.callout)
            Spacer(minLength: 0)
        }
    }

    private func heroIcon(systemImage: String, tint: Color) -> some View {
        ZStack {
            Circle()
                .fill(tint.opacity(0.18))
                .frame(width: 96, height: 96)
            Circle()
                .stroke(tint.opacity(0.30), lineWidth: 1)
                .frame(width: 96, height: 96)
            Image(systemName: systemImage)
                .font(.system(size: 42, weight: .semibold))
                .foregroundStyle(tint)
        }
    }
}

private struct StepLayout<Content: View>: View {
    let iconBadge: AnyView
    let title: String
    let subtitle: String
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            iconBadge
                .frame(maxWidth: .infinity, alignment: .leading)
            VStack(alignment: .leading, spacing: 10) {
                Text(title)
                    .font(Theme.Font.title)
                    .foregroundStyle(Theme.Color.primaryText)
                    .fixedSize(horizontal: false, vertical: true)
                Text(subtitle)
                    .font(Theme.Font.body)
                    .foregroundStyle(Theme.Color.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
