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

    func start() async {
        await refreshAuthorizationStatus()
        UNUserNotificationCenter.current().delegate = self
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
            guard granted else { return false }
            await registerForRemoteNotifications()
            return true
        } catch {
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

    /// Called from the AppDelegate / SceneDelegate when iOS hands us a token.
    func handleAPNsToken(_ deviceToken: Data) async {
        let token = deviceToken.map { String(format: "%02x", $0) }.joined()
        apnsToken = token
        do {
            let body = DeviceRegistrationRequest(
                apnsToken: token,
                appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String,
                osVersion: UIDevice.current.systemVersion,
                locale: Locale.current.identifier
            )
            _ = try await api.post("/v1/devices", body: body, as: DeviceRegistrationResponse.self)
            isRegistered = true
        } catch {
            // Best-effort. The user is signed in but our /devices register failed.
            // We retry on next app launch via start().
        }
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
