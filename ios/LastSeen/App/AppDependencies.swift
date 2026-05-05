//
//  AppDependencies.swift
//

import Foundation
import Observation

@MainActor
@Observable
final class AppDependencies {
    let api: APIClient
    let auth: AuthService
    let subscriptions: SubscriptionService
    let tracking: TrackingService
    let notifications: NotificationService

    init() {
        let api = APIClient(baseURL: AppConfig.apiBaseURL)
        let auth = AuthService(api: api)
        api.tokenProvider = { auth.token }
        self.api = api
        self.auth = auth
        self.subscriptions = SubscriptionService(api: api)
        self.tracking = TrackingService(api: api)
        self.notifications = NotificationService(api: api)
    }

    func bootstrap() async {
        // Make sure Firebase is configured before any analytics call. The
        // AppDelegate also calls this; LSAnalytics.configure() is idempotent.
        LSAnalytics.shared.configure()

        await auth.restoreSessionIfAny()
        identifyUserIfPossible()

        if auth.isAuthenticated {
            async let s: Void = subscriptions.start()
            async let t: Void = tracking.refresh()
            async let n: Void = notifications.start()
            _ = await (s, t, n)
            // Now that the auth token is set, re-run the device sync. Covers
            // the case where APNs handed us a token *before* sign-in (which
            // would have hit the API as 401 and cached the token only).
            await notifications.syncDeviceIfPossible()
            // Once we have data, push the latest user properties.
            LSAnalytics.shared.setSubscriptionStatus(subscriptions.isSubscribed,
                                                    productId: subscriptions.activeProductId)
            LSAnalytics.shared.setTrackedNumberCount(tracking.trackedNumbers.count)
        } else {
            await subscriptions.loadProducts()
        }
    }

    /// Re-run the post-sign-in setup. Call after a fresh sign-in so we
    /// register the device, refresh subscriptions, and pull tracked numbers
    /// — without waiting for an app relaunch.
    func onSignedIn() async {
        identifyUserIfPossible()
        async let s: Void = subscriptions.start()
        async let t: Void = tracking.refresh()
        async let n: Void = notifications.start()
        _ = await (s, t, n)
        await notifications.syncDeviceIfPossible()
    }

    /// Push current signed-in identity to analytics + crash reporting. Safe
    /// to call multiple times; clears identity if there's no session.
    func identifyUserIfPossible() {
        if case .signedIn(let user) = auth.state {
            LSAnalytics.shared.setUser(id: user.id, email: user.email)
        } else {
            LSAnalytics.shared.clearUser()
        }
    }
}
