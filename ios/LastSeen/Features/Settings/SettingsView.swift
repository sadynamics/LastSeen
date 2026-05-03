//
//  SettingsView.swift
//

import SwiftUI

struct SettingsView: View {
    @Environment(AuthService.self) private var auth
    @Environment(SubscriptionService.self) private var subscriptions
    @State private var showingPaywall = false
    @State private var showingDeleteConfirm = false
    @State private var isDeleting = false

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.Color.background.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: Theme.Spacing.lg) {
                        accountCard
                        subscriptionCard
                        legalCard
                        dangerZoneCard
                        Text("LastSeen \(appVersion)")
                            .font(.caption2)
                            .foregroundStyle(Theme.Color.tertiaryText)
                            .padding(.top, Theme.Spacing.md)
                    }
                    .padding(Theme.Spacing.lg)
                }
            }
            .navigationTitle("Settings")
            .sheet(isPresented: $showingPaywall) {
                PaywallView()
            }
            .alert("Delete account?", isPresented: $showingDeleteConfirm) {
                Button("Cancel", role: .cancel) {}
                Button("Delete", role: .destructive) {
                    Task { await deleteAccount() }
                }
            } message: {
                Text("This permanently removes your account and all tracking data.")
            }
        }
    }

    private var accountCard: some View {
        Card {
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                Text("Account")
                    .font(.headline)
                    .foregroundStyle(Theme.Color.primaryText)
                if case .signedIn(let user) = auth.state {
                    if let email = user.email {
                        row(label: "Email", value: email)
                    }
                    row(label: "User ID", value: String(user.id.prefix(12)) + "…")
                }
            }
        }
    }

    private var subscriptionCard: some View {
        Card {
            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                HStack {
                    Text("Subscription")
                        .font(.headline)
                        .foregroundStyle(Theme.Color.primaryText)
                    Spacer()
                    Text(subscriptions.isSubscribed ? "Active" : "Free")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(
                            subscriptions.isSubscribed
                                ? Theme.Color.online.opacity(0.2)
                                : Theme.Color.surfaceElevated
                        ))
                        .foregroundStyle(subscriptions.isSubscribed ? Theme.Color.online : Theme.Color.secondaryText)
                }
                if let exp = subscriptions.expiresAt {
                    row(label: "Renews", value: exp.formatted(date: .abbreviated, time: .omitted))
                }
                if subscriptions.isSubscribed {
                    Link(destination: URL(string: "https://apps.apple.com/account/subscriptions")!) {
                        HStack {
                            Text("Manage subscription")
                            Spacer()
                            Image(systemName: "arrow.up.right.square")
                        }
                        .foregroundStyle(Theme.Color.accent)
                    }
                } else {
                    PrimaryButton(title: "Upgrade") { showingPaywall = true }
                }
            }
        }
    }

    private var legalCard: some View {
        Card {
            VStack(spacing: 0) {
                linkRow(title: "Privacy policy", url: "https://lastseen.app/privacy")
                Divider().background(Theme.Color.surfaceElevated)
                linkRow(title: "Terms of service", url: "https://lastseen.app/terms")
                Divider().background(Theme.Color.surfaceElevated)
                linkRow(title: "Support", url: "mailto:support@lastseen.app")
            }
        }
    }

    private var dangerZoneCard: some View {
        Card {
            VStack(spacing: Theme.Spacing.md) {
                Button {
                    Task { await auth.signOut() }
                } label: {
                    HStack {
                        Image(systemName: "rectangle.portrait.and.arrow.right")
                        Text("Sign out")
                        Spacer()
                    }
                    .foregroundStyle(Theme.Color.primaryText)
                }
                Divider().background(Theme.Color.surfaceElevated)
                Button(role: .destructive) {
                    showingDeleteConfirm = true
                } label: {
                    HStack {
                        Image(systemName: "person.crop.circle.badge.minus")
                        Text("Delete account")
                        Spacer()
                        if isDeleting { ProgressView().tint(Theme.Color.danger) }
                    }
                    .foregroundStyle(Theme.Color.danger)
                }
            }
        }
    }

    private func row(label: String, value: String) -> some View {
        HStack {
            Text(label).foregroundStyle(Theme.Color.secondaryText)
            Spacer()
            Text(value)
                .foregroundStyle(Theme.Color.primaryText)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .font(.callout)
    }

    private func linkRow(title: String, url: String) -> some View {
        Link(destination: URL(string: url)!) {
            HStack {
                Text(title).foregroundStyle(Theme.Color.primaryText)
                Spacer()
                Image(systemName: "chevron.right").foregroundStyle(Theme.Color.tertiaryText)
            }
            .padding(.vertical, Theme.Spacing.sm)
        }
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
