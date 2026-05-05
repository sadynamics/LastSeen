//
//  AppDelegate.swift
//  We use SwiftUI's `@UIApplicationDelegateAdaptor` to receive the APNs token
//  callback that the UIApplication delegate API requires, and to bootstrap
//  Firebase as early as possible in the launch sequence.
//

import FirebaseCore
import FirebaseMessaging
import OSLog
import SwiftUI
import UIKit
import UserNotifications

/// Logger used by every push-related call site. Filter in Console.app with
/// `subsystem:collabrainstech.LastSeen category:APNS` to see only push logs.
let apnsLog = Logger(subsystem: "collabrainstech.LastSeen", category: "APNS")

final class AppDelegate: NSObject, UIApplicationDelegate {
    /// Captured at launch so the `NotificationService` can pull the token.
    static var pendingToken: Data?

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        apnsLog.info("AppDelegate didFinishLaunching bundleId=\(Bundle.main.bundleIdentifier ?? "?", privacy: .public)")
        print("[APNS] AppDelegate didFinishLaunching")
        LSAnalytics.shared.configure()
        Messaging.messaging().delegate = self
        return true
    }

    func application(_ application: UIApplication,
                     didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        let hex = deviceToken.map { String(format: "%02x", $0) }.joined()
        apnsLog.info("didRegisterForRemoteNotifications token=\(hex.prefix(12), privacy: .public)…")
        print("[APNS] didRegisterForRemoteNotifications token=\(hex.prefix(12))…")
        Self.pendingToken = deviceToken
        Messaging.messaging().apnsToken = deviceToken
        NotificationCenter.default.post(name: .apnsTokenReceived, object: deviceToken)
    }

    func application(_ application: UIApplication,
                     didFailToRegisterForRemoteNotificationsWithError error: Error) {
        let ns = error as NSError
        apnsLog.error("didFailToRegisterForRemoteNotifications domain=\(ns.domain, privacy: .public) code=\(ns.code) message=\(ns.localizedDescription, privacy: .public)")
        print("[APNS] didFailToRegisterForRemoteNotifications domain=\(ns.domain) code=\(ns.code) message=\(ns.localizedDescription)")
        LSAnalytics.shared.logError(error, context: ["operation": "register_for_remote_notifications"])
        NotificationCenter.default.post(name: .apnsRegistrationFailed, object: error)
    }
}

// MARK: - FCM delegate

extension AppDelegate: MessagingDelegate {
    nonisolated func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
        // Firebase has its own token; we still rely on raw APNs for our backend,
        // but log so we can use FCM topics later if we want.
        guard let fcmToken else { return }
        let len = fcmToken.count
        Task { @MainActor in
            LSAnalytics.shared.breadcrumb("fcm_token_received len=\(len)")
        }
    }
}

extension Notification.Name {
    static let apnsTokenReceived = Notification.Name("apnsTokenReceived")
    static let apnsRegistrationFailed = Notification.Name("apnsRegistrationFailed")
}
