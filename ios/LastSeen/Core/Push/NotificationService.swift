//
//  NotificationService.swift
//

import Foundation
import Observation
import UIKit
import UserNotifications

@MainActor
@Observable
final class NotificationService: NSObject {
    private(set) var authorizationStatus: UNAuthorizationStatus = .notDetermined
    private(set) var apnsToken: String?
    private(set) var isRegistered: Bool = false

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
        if authorizationStatus == .authorized || authorizationStatus == .provisional || authorizationStatus == .ephemeral {
            await registerForRemoteNotifications()
        }
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
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            DispatchQueue.main.async {
                UIApplication.shared.registerForRemoteNotifications()
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
        await syncDeviceIfPossible()
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
