//
//  PushDiagnosticsView.swift
//  Lets the user (and us, when debugging remotely) see exactly what state the
//  push pipeline is in: iOS authorization, APNs token, build environment, and
//  whether the backend has registered this device.
//

import Foundation
import SwiftUI
import UserNotifications
import Combine

/// Bumped whenever the diagnostics UI changes meaningfully so we can confirm
/// over screen-share that the latest build is running on the device.
private let diagnosticsBuildMarker = "v8 · 2026-05-14"

struct PushDiagnosticsView: View {
    @Environment(NotificationService.self) private var notifications
    @Environment(AuthService.self) private var auth
    @Environment(AppDependencies.self) private var dependencies
    @Environment(\.dismiss) private var dismiss

    @State private var lastAction: String?
    @State private var nowTick: Date = Date()
    @State private var serverDeviceCount: Int?
    @State private var serverProbeInFlight = false

    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        NavigationStack {
            ZStack {
                AppBackground()
                ScrollView {
                    VStack(spacing: Theme.Spacing.lg) {
                        buildBanner
                        statusCard
                        entitlementsCard
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
            .onReceive(timer) { _ in nowTick = Date() }
        }
    }

    // MARK: Build banner

    private var buildBanner: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(Theme.Color.tintMint)
                .frame(width: 8, height: 8)
            Text("Diagnostics build \(diagnosticsBuildMarker)")
                .font(Theme.Font.caption.weight(.semibold).monospaced())
                .foregroundStyle(Theme.Color.secondaryText)
            Spacer()
        }
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Theme.Color.tintMint.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Theme.Color.tintMint.opacity(0.25), lineWidth: 1)
                )
        )
    }

    // MARK: Status

    private var statusCard: some View {
        Card {
            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                SectionHeader(title: "Status")
                row("iOS authorization", value: authValue)
                Divider().background(Theme.Color.separator)
                row("APNs token",
                    value: notifications.apnsToken.map { String($0.prefix(10)) + "…" } ?? "Not received yet")
                Divider().background(Theme.Color.separator)
                row("AppDelegate pendingToken",
                    value: AppDelegate.pendingToken == nil ? "nil" : "set (\(AppDelegate.pendingToken!.count) bytes)")
                Divider().background(Theme.Color.separator)
                row("Backend registered", value: notifications.isRegistered ? "Yes" : "No")
                Divider().background(Theme.Color.separator)
                row("Registration attempts",
                    value: "\(notifications.registrationAttempts)")
                if let at = notifications.lastRegistrationAttemptAt {
                    Divider().background(Theme.Color.separator)
                    row("Last attempt", value: relative(at))
                }
                if let at = notifications.lastTokenReceivedAt {
                    Divider().background(Theme.Color.separator)
                    row("Last token received", value: relative(at))
                }
                if let at = notifications.lastSyncAttemptAt {
                    Divider().background(Theme.Color.separator)
                    row("Last server sync", value: relative(at))
                }
                Divider().background(Theme.Color.separator)
                row("Server-side devices",
                    value: serverProbeInFlight
                        ? "checking…"
                        : (serverDeviceCount.map { "\($0)" } ?? "not checked"))
                if case .signedIn(let user) = auth.state {
                    Divider().background(Theme.Color.separator)
                    row("User ID", value: String(user.id.prefix(12)) + "…")
                }
                if let err = notifications.lastRegistrationError {
                    Divider().background(Theme.Color.separator)
                    failureBlock(title: "iOS rejected APNs registration", body: err)
                }
                if let err = notifications.lastSyncError {
                    Divider().background(Theme.Color.separator)
                    failureBlock(title: "Server sync failed", body: err)
                }
            }
        }
    }

    private func failureBlock(title: String, body: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(Theme.Font.caption.weight(.semibold))
                .foregroundStyle(Theme.Color.danger)
            Text(body)
                .font(Theme.Font.caption.monospaced())
                .foregroundStyle(Theme.Color.secondaryText)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: Entitlements

    private var entitlementsCard: some View {
        Card {
            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                SectionHeader(title: "Build")
                row("Build configuration", value: NotificationService.apnsEnvironment)
                Divider().background(Theme.Color.separator)
                row("Bundle identifier",
                    value: Bundle.main.bundleIdentifier ?? "?")
                Divider().background(Theme.Color.separator)
                row("Embedded profile present",
                    value: EntitlementInspector.hasEmbeddedProfile ? "Yes" : "No")
                Divider().background(Theme.Color.separator)
                row("aps-environment (signed)",
                    value: EntitlementInspector.apsEnvironmentFromEmbeddedProfile() ?? "MISSING")
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
                .foregroundStyle(value == "MISSING" ? Theme.Color.danger : Theme.Color.primaryText)
                .font(Theme.Font.callout.monospaced())
                .multilineTextAlignment(.trailing)
                .textSelection(.enabled)
        }
    }

    private func relative(_ date: Date) -> String {
        let secs = max(0, Int(nowTick.timeIntervalSince(date)))
        if secs < 5 { return "just now" }
        if secs < 60 { return "\(secs)s ago" }
        if secs < 3600 { return "\(secs / 60)m \(secs % 60)s ago" }
        return "\(secs / 3600)h ago"
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
                    Task {
                        await notifications.registerForRemoteNotifications()
                        // Poll for up to 8 seconds, picking up the token via
                        // AppDelegate.pendingToken even if the
                        // NotificationCenter listener races us.
                        for _ in 0..<8 {
                            try? await Task.sleep(nanoseconds: 1_000_000_000)
                            await notifications.pullPendingTokenIfAny()
                            if notifications.apnsToken != nil { break }
                        }
                        await notifications.syncDeviceIfPossible()
                        lastAction = notifications.isRegistered
                            ? "Device registered with server."
                            : (notifications.apnsToken == nil
                               ? "iOS hasn't returned a token after 8s. Likely the network is blocking APNs (port 5223). Try cellular."
                               : "Token received but server registration failed.")
                    }
                }

                SecondaryButton(title: "Re-sync device with server",
                                systemImage: "arrow.up.circle.fill") {
                    Task {
                        await notifications.syncDeviceIfPossible()
                        lastAction = notifications.isRegistered
                            ? "Synced with server."
                            : "Server sync failed."
                        await probeServerDeviceCount()
                    }
                }

                SecondaryButton(title: "Send test push to me",
                                systemImage: "paperplane.fill") {
                    Task { await sendTestPush() }
                }

                SecondaryButton(title: "Check server device count",
                                systemImage: "magnifyingglass") {
                    Task { await probeServerDeviceCount() }
                }
            }
        }
    }

    // MARK: Network probes

    /// Ask the backend how many devices are registered for the signed-in
    /// user. Surfaces the result in the status card so the user can SEE the
    /// registration handshake working (or not) end-to-end.
    private func probeServerDeviceCount() async {
        serverProbeInFlight = true
        defer { serverProbeInFlight = false }
        do {
            let res = try await dependencies.api.get("/v1/me/devices",
                                                     as: MyDevicesResponse.self)
            serverDeviceCount = res.count
            lastAction = res.count == 0
                ? "Server has 0 devices for you. The /v1/devices POST never reached the server (or was rejected)."
                : "Server has \(res.count) device(s) registered for you."
        } catch {
            lastAction = "Couldn't reach /v1/me/devices: \(NotificationService.describeError(error))"
        }
    }

    private func sendTestPush() async {
        do {
            struct Empty: Encodable, Sendable {}
            let res = try await dependencies.api.post("/v1/me/test-push",
                                                      body: Empty(),
                                                      as: TestPushResponse.self)
            if res.devicesTargeted == 0 {
                lastAction = "Server has 0 devices to push to — sync your device first."
            } else {
                lastAction = "Test push sent to \(res.devicesTargeted) device(s). It can take 30s to arrive."
            }
        } catch {
            lastAction = "Test push failed: \(NotificationService.describeError(error))"
        }
    }
}
