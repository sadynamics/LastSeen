//
//  AppDelegate.swift
//  We use SwiftUI's `@UIApplicationDelegateAdaptor` to receive the APNs token
//  callback that the UIApplication delegate API requires, and to bootstrap
//  Firebase as early as possible in the launch sequence.
//

import FirebaseCore
import FirebaseMessaging
import SwiftUI
import UIKit
import UserNotifications

final class AppDelegate: NSObject, UIApplicationDelegate {
    /// Captured at launch so the `NotificationService` can pull the token.
    static var pendingToken: Data?

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        // Firebase must be configured before any other Firebase API is called,
        // so we do it synchronously at the top of launch.
        LSAnalytics.shared.configure()

        // Forward APNs tokens to FCM so we can use either delivery channel.
        Messaging.messaging().delegate = self
        return true
    }

    func application(_ application: UIApplication,
                     didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        Self.pendingToken = deviceToken
        Messaging.messaging().apnsToken = deviceToken
        NotificationCenter.default.post(name: .apnsTokenReceived, object: deviceToken)
    }

    func application(_ application: UIApplication,
                     didFailToRegisterForRemoteNotificationsWithError error: Error) {
        LSAnalytics.shared.logError(error, context: ["operation": "register_for_remote_notifications"])
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
}
