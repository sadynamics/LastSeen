//
//  PushDiagnosticsView.swift
//  Lets the user (and us, when debugging remotely) see exactly what state the
//  push pipeline is in: iOS authorization, APNs token, build environment, and
//  whether the backend has registered this device.
//

import SwiftUI
import UserNotifications

struct PushDiagnosticsView: View {
    @Environment(NotificationService.self) private var notifications
    @Environment(AuthService.self) private var auth
    @Environment(\.dismiss) private var dismiss

    @State private var refreshing = false
    @State private var lastAction: String?

    var body: some View {
        NavigationStack {
            ZStack {
                AppBackground()
                ScrollView {
                    VStack(spacing: Theme.Spacing.lg) {
                        statusCard
                        actionsCard
                        if let lastAction {
                            Text(lastAction)
                                .font(Theme.Font.caption)
                                .foregroundStyle(Theme.Color.secondaryText)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, Theme.Spacing.md)
                        }
                    }
                    .padding(Theme.Spacing.lg)
                }
                .scrollIndicators(.hidden)
            }
            .navigationTitle("Push diagnostics")
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .task { await notifications.refreshAuthorizationStatus() }
        }
    }

    // MARK: Status

    private var statusCard: some View {
        Card {
            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                SectionHeader(title: "Status")
                row("Authorization", value: authValue)
                Divider().background(Theme.Color.separator)
                row("APNs token",
                    value: notifications.apnsToken.map { String($0.prefix(10)) + "…" } ?? "Not received yet")
                Divider().background(Theme.Color.separator)
                row("Build", value: NotificationService.apnsEnvironment)
                Divider().background(Theme.Color.separator)
                row("Backend registered",
                    value: notifications.isRegistered ? "Yes" : "No")
                if case .signedIn(let user) = auth.state {
                    Divider().background(Theme.Color.separator)
                    row("User ID", value: String(user.id.prefix(12)) + "…")
                }
                if let err = notifications.lastRegistrationError {
                    Divider().background(Theme.Color.separator)
                    VStack(alignment: .leading, spacing: 6) {
                        Text("iOS rejected APNs registration")
                            .font(Theme.Font.caption.weight(.semibold))
                            .foregroundStyle(Theme.Color.danger)
                        Text(err)
                            .font(Theme.Font.caption.monospaced())
                            .foregroundStyle(Theme.Color.secondaryText)
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    private var authValue: String {
        switch notifications.authorizationStatus {
        case .authorized: return "Authorized"
        case .denied: return "Denied"
        case .notDetermined: return "Not asked"
        case .provisional: return "Provisional"
        case .ephemeral: return "Ephemeral"
        @unknown default: return "Unknown"
        }
    }

    private func row(_ label: String, value: String) -> some View {
        HStack(alignment: .top, spacing: Theme.Spacing.md) {
            Text(label)
                .foregroundStyle(Theme.Color.secondaryText)
                .font(Theme.Font.callout)
            Spacer()
            Text(value)
                .foregroundStyle(Theme.Color.primaryText)
                .font(Theme.Font.callout.monospaced())
                .multilineTextAlignment(.trailing)
                .textSelection(.enabled)
        }
    }

    // MARK: Actions

    private var actionsCard: some View {
        Card {
            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                SectionHeader(title: "Actions")

                if notifications.authorizationStatus != .authorized {
                    PrimaryButton(title: "Request authorization", systemImage: "bell.fill") {
                        Task {
                            let granted = await notifications.requestAuthorizationAndRegister()
                            lastAction = granted
                                ? "Authorization granted. Token will arrive shortly."
                                : "Authorization not granted."
                        }
                    }
                }

                if notifications.authorizationStatus == .denied {
                    SecondaryButton(title: "Open iOS Settings", systemImage: "gearshape.fill") {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    }
                }

                SecondaryButton(title: "Re-register for remote notifications",
                                systemImage: "arrow.clockwise") {
                    refreshing = true
                    Task {
                        await notifications.registerForRemoteNotifications()
                        // Give iOS a moment to call back with the token.
                        try? await Task.sleep(nanoseconds: 1_500_000_000)
                        await notifications.syncDeviceIfPossible()
                        refreshing = false
                        lastAction = notifications.isRegistered
                            ? "Device registered with server."
                            : (notifications.apnsToken == nil
                               ? "iOS hasn't returned a token yet. Try again in a few seconds."
                               : "Token received but server registration failed.")
                    }
                }

                SecondaryButton(title: "Re-sync device with server",
                                systemImage: "arrow.up.circle.fill") {
                    Task {
                        await notifications.syncDeviceIfPossible()
                        lastAction = notifications.isRegistered
                            ? "Synced with server."
                            : "Server sync failed (no token cached yet)."
                    }
                }
            }
        }
    }
}
