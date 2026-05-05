//
//  SettingsView.swift
//

import SwiftUI

struct SettingsView: View {
    @Environment(AuthService.self) private var auth
    @Environment(SubscriptionService.self) private var subscriptions
    @Environment(NotificationService.self) private var notifications
    @State private var showingPaywall = false
    @State private var showingDeleteConfirm = false
    @State private var isDeleting = false
    @State private var showingPushDiagnostics = false

    var body: some View {
        NavigationStack {
            ZStack {
                AppBackground()
                ScrollView {
                    VStack(spacing: Theme.Spacing.lg) {
                        subscriptionCard
                        notificationsCard
                        accountCard
                        legalCard
                        dangerZoneCard
                        Text("LastSeen \(appVersion)")
                            .font(Theme.Font.caption)
                            .foregroundStyle(Theme.Color.tertiaryText)
                            .padding(.top, Theme.Spacing.md)
                    }
                    .padding(Theme.Spacing.lg)
                    .padding(.bottom, Theme.Spacing.xxl)
                }
                .scrollIndicators(.hidden)
            }
            .navigationTitle("Settings")
            .toolbarBackground(.hidden, for: .navigationBar)
            .sheet(isPresented: $showingPaywall) {
                PaywallView()
            }
            .sheet(isPresented: $showingPushDiagnostics) {
                PushDiagnosticsView()
            }
            .alert("Delete account?", isPresented: $showingDeleteConfirm) {
                Button("Cancel", role: .cancel) {}
                Button("Delete", role: .destructive) {
                    Task { await deleteAccount() }
                }
            } message: {
                Text("This permanently removes your account and all tracking data.")
            }
            .trackScreen("settings", className: "SettingsView")
        }
    }

    // MARK: Subscription

    private var subscriptionCard: some View {
        Card {
            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                HStack {
                    HStack(spacing: 10) {
                        IconBadge(systemImage: subscriptions.isSubscribed ? "checkmark.seal.fill" : "sparkles",
                                  tint: subscriptions.isSubscribed ? Theme.Color.online : Theme.Color.accent,
                                  size: 36)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(subscriptions.isSubscribed ? "LastSeen Pro" : "LastSeen Free")
                                .font(Theme.Font.headline)
                                .foregroundStyle(Theme.Color.primaryText)
                            Text(subscriptions.isSubscribed ? "All features unlocked" : "Limited to one tracked number")
                                .font(Theme.Font.caption)
                                .foregroundStyle(Theme.Color.secondaryText)
                        }
                    }
                    Spacer()
                    statusBadge
                }

                if let exp = subscriptions.expiresAt {
                    Divider().background(Theme.Color.separator)
                    HStack {
                        Text("Renews")
                            .font(Theme.Font.callout)
                            .foregroundStyle(Theme.Color.secondaryText)
                        Spacer()
                        Text(exp.formatted(date: .abbreviated, time: .omitted))
                            .font(Theme.Font.callout.weight(.medium))
                            .foregroundStyle(Theme.Color.primaryText)
                    }
                }

                if subscriptions.isSubscribed {
                    Link(destination: URL(string: "https://apps.apple.com/account/subscriptions")!) {
                        HStack {
                            Text("Manage subscription")
                                .font(Theme.Font.callout.weight(.medium))
                            Spacer()
                            Image(systemName: "arrow.up.right.square")
                        }
                        .foregroundStyle(Theme.Color.accent)
                    }
                    .simultaneousGesture(TapGesture().onEnded {
                        LSAnalytics.shared.log(.settingsLinkTapped(name: "manage_subscription"))
                    })
                } else {
                    PrimaryButton(title: "Upgrade to Pro", systemImage: "sparkles") {
                        LSAnalytics.shared.log(.upgradeTapped(source: "settings"))
                        showingPaywall = true
                    }
                }
            }
        }
    }

    private var statusBadge: some View {
        let active = subscriptions.isSubscribed
        return Text(active ? "Active" : "Free")
            .font(Theme.Font.label)
            .tracking(0.8)
            .foregroundStyle(active ? Theme.Color.online : Theme.Color.secondaryText)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(
                Capsule().fill(active
                    ? Theme.Color.online.opacity(0.15)
                    : Color.white.opacity(0.06))
            )
            .overlay(
                Capsule().stroke(active
                    ? Theme.Color.online.opacity(0.30)
                    : Color.white.opacity(0.10), lineWidth: 0.5)
            )
    }

    // MARK: Account

    // MARK: Notifications

    private var notificationsCard: some View {
        Card {
            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                SectionHeader(title: "Notifications")

                HStack(spacing: Theme.Spacing.md) {
                    IconBadge(systemImage: notifications.authorizationStatus == .authorized
                              ? "bell.badge.fill" : "bell.slash.fill",
                              tint: notifications.authorizationStatus == .authorized
                                    ? Theme.Color.online : Theme.Color.danger,
                              size: 36)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(notifAuthLabel)
                            .font(Theme.Font.callout.weight(.semibold))
                            .foregroundStyle(Theme.Color.primaryText)
                        Text(notifSubtitle)
                            .font(Theme.Font.caption)
                            .foregroundStyle(Theme.Color.secondaryText)
                    }
                    Spacer()
                }

                if notifications.authorizationStatus == .denied {
                    PrimaryButton(title: "Open iOS Settings", systemImage: "gearshape.fill") {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    }
                } else if notifications.authorizationStatus == .notDetermined {
                    PrimaryButton(title: "Enable notifications", systemImage: "bell.fill") {
                        Task { _ = await notifications.requestAuthorizationAndRegister() }
                    }
                } else {
                    Button {
                        showingPushDiagnostics = true
                    } label: {
                        HStack {
                            Text("Push diagnostics")
                                .font(Theme.Font.callout.weight(.medium))
                                .foregroundStyle(Theme.Color.primaryText)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .foregroundStyle(Theme.Color.tertiaryText)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var notifAuthLabel: String {
        switch notifications.authorizationStatus {
        case .authorized: return "Notifications enabled"
        case .provisional: return "Provisional notifications"
        case .ephemeral: return "Ephemeral (App Clip)"
        case .denied: return "Notifications denied"
        case .notDetermined: return "Not enabled yet"
        @unknown default: return "Unknown state"
        }
    }

    private var notifSubtitle: String {
        switch notifications.authorizationStatus {
        case .authorized:
            return notifications.isRegistered
                ? "Synced with server"
                : "Waiting for token…"
        case .denied:
            return "Tap below to re-enable in iOS Settings"
        case .notDetermined:
            return "Push alerts when contacts come online"
        default: return ""
        }
    }

    private var accountCard: some View {
        Card {
            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                SectionHeader(title: "Account")
                if case .signedIn(let user) = auth.state {
                    if let email = user.email {
                        row(label: "Email", value: email, icon: "envelope.fill",
                            tint: Theme.Color.accentSecondary)
                    }
                    Divider().background(Theme.Color.separator)
                    row(label: "User ID",
                        value: String(user.id.prefix(12)) + "…",
                        icon: "person.crop.circle.fill",
                        tint: Theme.Color.accent)
                }
            }
        }
    }

    // MARK: Legal

    private var legalCard: some View {
        Card(padding: 0) {
            VStack(spacing: 0) {
                linkRow(title: "Privacy policy", icon: "lock.shield.fill",
                        tint: Theme.Color.tintMint,
                        url: "https://lastseen.app/privacy")
                Divider().background(Theme.Color.separator).padding(.leading, 60)
                linkRow(title: "Terms of service", icon: "doc.text.fill",
                        tint: Theme.Color.accent,
                        url: "https://lastseen.app/terms")
                Divider().background(Theme.Color.separator).padding(.leading, 60)
                linkRow(title: "Support", icon: "envelope.fill",
                        tint: Theme.Color.tintAmber,
                        url: "mailto:support@lastseen.app")
            }
        }
    }

    // MARK: Danger zone

    private var dangerZoneCard: some View {
        Card(padding: 0) {
            VStack(spacing: 0) {
                Button {
                    Task { await auth.signOut() }
                } label: {
                    actionRow(title: "Sign out",
                              icon: "rectangle.portrait.and.arrow.right",
                              tint: Theme.Color.secondaryText,
                              destructive: false,
                              loading: false)
                }
                .buttonStyle(.plain)
                Divider().background(Theme.Color.separator).padding(.leading, 60)
                Button(role: .destructive) {
                    showingDeleteConfirm = true
                } label: {
                    actionRow(title: "Delete account",
                              icon: "person.crop.circle.badge.minus",
                              tint: Theme.Color.danger,
                              destructive: true,
                              loading: isDeleting)
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: Row helpers

    private func row(label: String, value: String, icon: String, tint: Color) -> some View {
        HStack(spacing: Theme.Spacing.md) {
            IconBadge(systemImage: icon, tint: tint, size: 32)
            Text(label)
                .font(Theme.Font.callout)
                .foregroundStyle(Theme.Color.secondaryText)
            Spacer()
            Text(value)
                .font(Theme.Font.callout.weight(.medium))
                .foregroundStyle(Theme.Color.primaryText)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }

    private func linkRow(title: String, icon: String, tint: Color, url: String) -> some View {
        Link(destination: URL(string: url)!) {
            HStack(spacing: Theme.Spacing.md) {
                IconBadge(systemImage: icon, tint: tint, size: 32)
                Text(title)
                    .font(Theme.Font.callout.weight(.medium))
                    .foregroundStyle(Theme.Color.primaryText)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.Color.tertiaryText)
            }
            .padding(.horizontal, Theme.Spacing.lg)
            .padding(.vertical, 14)
        }
        .simultaneousGesture(TapGesture().onEnded {
            LSAnalytics.shared.log(.settingsLinkTapped(name: title.lowercased().replacingOccurrences(of: " ", with: "_")))
        })
    }

    private func actionRow(title: String, icon: String, tint: Color, destructive: Bool, loading: Bool) -> some View {
        HStack(spacing: Theme.Spacing.md) {
            IconBadge(systemImage: icon,
                      tint: destructive ? Theme.Color.danger : Theme.Color.secondaryText,
                      size: 32)
            Text(title)
                .font(Theme.Font.callout.weight(.medium))
                .foregroundStyle(destructive ? Theme.Color.danger : Theme.Color.primaryText)
            Spacer()
            if loading {
                ProgressView().tint(tint)
            } else {
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.Color.tertiaryText)
            }
        }
        .padding(.horizontal, Theme.Spacing.lg)
        .padding(.vertical, 14)
    }

    private func deleteAccount() async {
        isDeleting = true
        defer { isDeleting = false }
        do {
            try await auth.deleteAccount()
        } catch {
            // surface via auth.lastError or ignore for now.
        }
    }

    private var appVersion: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(v) (\(b))"
    }
}
