//
//  NotificationService.swift
//

import Foundation
import Observation
import OSLog
import UIKit
import UserNotifications

@MainActor
@Observable
final class NotificationService: NSObject {
    private(set) var authorizationStatus: UNAuthorizationStatus = .notDetermined
    private(set) var apnsToken: String?
    private(set) var isRegistered: Bool = false
    /// Last error returned by iOS via `didFailToRegisterForRemoteNotifications`.
    /// Surfaced in the diagnostics screen so the user (and we) can see WHY
    /// APNs is rejecting the registration — typically a missing entitlement
    /// or an App ID without "Push Notifications" enabled in the developer
    /// portal.
    private(set) var lastRegistrationError: String?
    /// Number of times we asked iOS to register for remote notifications since
    /// app launch. Useful to confirm the call is even being made.
    private(set) var registrationAttempts: Int = 0
    /// Wall-clock time of the last call to UIApplication.registerForRemoteNotifications.
    private(set) var lastRegistrationAttemptAt: Date?
    /// Wall-clock time we last received a token from iOS (success).
    private(set) var lastTokenReceivedAt: Date?

    private let api: APIClient
    private var registrationContinuation: CheckedContinuation<String, Error>?

    init(api: APIClient) {
        self.api = api
        super.init()
    }

    /// Called from `AppDependencies.bootstrap` on every launch. If the user
    /// has previously granted notification permission, we re-trigger the APNs
    /// registration handshake so iOS hands us a fresh device token (which
    /// then routes through `AppDelegate -> handleAPNsToken` and re-POSTs to
    /// the backend). Without this, users who pass through onboarding once
    /// never sync their device with the server on later launches.
    func start() async {
        UNUserNotificationCenter.current().delegate = self
        await refreshAuthorizationStatus()
        // If the AppDelegate received a token before the SwiftUI listener
        // attached (a launch-time race), pick it up now.
        await pullPendingTokenIfAny()
        if authorizationStatus == .authorized || authorizationStatus == .provisional || authorizationStatus == .ephemeral {
            await registerForRemoteNotifications()
            // Re-poll in 2s in case iOS hands the token to AppDelegate before
            // the NotificationCenter publisher has subscribed.
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            await pullPendingTokenIfAny()
        }
    }

    /// Reads `AppDelegate.pendingToken`, which is the most-recent token iOS
    /// has handed our process. Posting through NotificationCenter can race
    /// against listener subscription on cold launches; this is a belt-and-
    /// braces backup. Idempotent.
    func pullPendingTokenIfAny() async {
        guard let data = AppDelegate.pendingToken else { return }
        let hex = data.map { String(format: "%02x", $0) }.joined()
        if apnsToken == hex { return }
        await handleAPNsToken(data)
    }

    func refreshAuthorizationStatus() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        authorizationStatus = settings.authorizationStatus
    }

    @discardableResult
    func requestAuthorizationAndRegister() async -> Bool {
        do {
            let granted = try await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound, .badge, .providesAppNotificationSettings])
            await refreshAuthorizationStatus()
            LSAnalytics.shared.log(.notificationAuthorizationResult(granted: granted))
            guard granted else { return false }
            await registerForRemoteNotifications()
            return true
        } catch {
            LSAnalytics.shared.log(.notificationAuthorizationResult(granted: false))
            LSAnalytics.shared.logError(error, context: ["operation": "request_notification_authorization"])
            return false
        }
    }

    func registerForRemoteNotifications() async {
        registrationAttempts += 1
        lastRegistrationAttemptAt = Date()
        apnsLog.info("calling UIApplication.registerForRemoteNotifications attempt=\(self.registrationAttempts)")
        print("[APNS] calling UIApplication.registerForRemoteNotifications attempt=\(registrationAttempts)")
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            DispatchQueue.main.async {
                UIApplication.shared.registerForRemoteNotifications()
                apnsLog.info("UIApplication.registerForRemoteNotifications returned (waiting for callback)")
                print("[APNS] UIApplication.registerForRemoteNotifications returned (waiting for callback)")
                continuation.resume()
            }
        }
    }

    /// Called from the AppDelegate when iOS hands us a token. Caches the
    /// token AND attempts to register it with the backend; if registration
    /// fails (eg. the user isn't signed in yet), the token is retained so
    /// `syncDeviceIfPossible()` can retry once the auth token lands.
    func handleAPNsToken(_ deviceToken: Data) async {
        let token = deviceToken.map { String(format: "%02x", $0) }.joined()
        apnsToken = token
        lastTokenReceivedAt = Date()
        lastRegistrationError = nil
        await syncDeviceIfPossible()
    }

    /// Called from the AppDelegate when iOS rejects the APNs registration.
    /// We capture the error message so it shows up in the diagnostics screen.
    func handleAPNsRegistrationFailure(_ error: Error) {
        let ns = error as NSError
        lastRegistrationError = "\(ns.domain) \(ns.code): \(ns.localizedDescription)"
    }

    /// Idempotent backend sync. Call this after sign-in, after auth-token
    /// refresh, or whenever the app foregrounds, to make sure our APNs token
    /// is present in the server-side `devices` table. Safe to call without a
    /// cached token (no-op).
    func syncDeviceIfPossible() async {
        guard let token = apnsToken else { return }
        do {
            let body = DeviceRegistrationRequest(
                apnsToken: token,
                environment: NotificationService.apnsEnvironment,
                appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String,
                osVersion: UIDevice.current.systemVersion,
                locale: Locale.current.identifier
            )
            _ = try await api.post("/v1/devices", body: body, as: DeviceRegistrationResponse.self)
            isRegistered = true
            LSAnalytics.shared.log(.apnsTokenRegistered)
        } catch {
            // Most likely 401 — user not yet signed in. The token stays cached
            // in `apnsToken` so the next call to syncDeviceIfPossible (after
            // sign-in) succeeds.
            isRegistered = false
            LSAnalytics.shared.logError(error, context: ["operation": "device_register"])
        }
    }

    /// "development" for Xcode debug builds (which receive sandbox APNs
    /// tokens), "production" for TestFlight / App Store builds. The backend
    /// must use the matching APNs gateway or every push silently fails with
    /// BadDeviceToken.
    static var apnsEnvironment: String {
        #if DEBUG
        return "development"
        #else
        return "production"
        #endif
    }
}

extension NotificationService: UNUserNotificationCenterDelegate {
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound, .badge]
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        // Hook for deep-linking to tracked number detail. Wired up when the
        // navigation router lands.
    }
}
