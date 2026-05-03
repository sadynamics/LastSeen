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
        await auth.restoreSessionIfAny()
        if auth.isAuthenticated {
            async let s: Void = subscriptions.start()
            async let t: Void = tracking.refresh()
            async let n: Void = notifications.start()
            _ = await (s, t, n)
        } else {
            await subscriptions.loadProducts()
        }
    }
}
