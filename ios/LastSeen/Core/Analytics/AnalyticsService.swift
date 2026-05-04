//
//  AnalyticsService.swift
//  Thin facade over FirebaseAnalytics + FirebaseCrashlytics + FirebasePerformance.
//
//  Goals:
//   * One call site per product event so renames are cheap.
//   * Strongly-typed events via `AnalyticsEvent` so the compiler catches typos.
//   * Safe to call from anywhere (`MainActor` isolated, but callers can `Task { @MainActor in ... }`).
//   * No-ops gracefully if Firebase isn't yet configured (e.g. unit tests).
//

import Foundation
import FirebaseAnalytics
import FirebaseCore
import FirebaseCrashlytics
import FirebasePerformance

// MARK: - Event taxonomy

/// All product analytics events flow through this enum so the names stay
/// consistent and the parameter shapes are documented in one place.
enum AnalyticsEvent {
    // Auth
    case signInStarted(method: String)
    case signInSucceeded(method: String, userId: String)
    case signInFailed(method: String, reason: String)
    case signOut
    case accountDeleted

    // Onboarding
    case onboardingStarted
    case onboardingStepViewed(step: Int, name: String)
    case onboardingConsentGiven
    case onboardingCompleted

    // Notifications / push
    case notificationAuthorizationResult(granted: Bool)
    case apnsTokenRegistered

    // Tracking
    case trackedNumberAdded(country: String?)
    case trackedNumberRemoved
    case trackedNumberDetailViewed
    case notificationPrefChanged(name: String, enabled: Bool)

    // Paywall + subscriptions
    case paywallViewed(source: String)
    case paywallPlanSelected(productId: String)
    case purchaseStarted(productId: String, price: Decimal, currency: String?)
    case purchaseSucceeded(productId: String, price: Decimal, currency: String?)
    case purchaseCancelled(productId: String)
    case purchasePending(productId: String)
    case purchaseFailed(productId: String, reason: String)
    case restorePurchasesTapped
    case restorePurchasesSucceeded
    case restorePurchasesFailed(reason: String)

    // Misc UI
    case settingsLinkTapped(name: String)
    case addNumberOpened(source: String)
    case upgradeTapped(source: String)

    /// The Firebase event name. Use `AnalyticsEventXxx` constants where a
    /// matching standard event exists so they roll up into Firebase reports.
    fileprivate var name: String {
        switch self {
        case .signInStarted: return "sign_in_started"
        case .signInSucceeded: return AnalyticsEventLogin
        case .signInFailed: return "sign_in_failed"
        case .signOut: return "sign_out"
        case .accountDeleted: return "account_deleted"

        case .onboardingStarted: return AnalyticsEventTutorialBegin
        case .onboardingStepViewed: return "onboarding_step_viewed"
        case .onboardingConsentGiven: return "onboarding_consent_given"
        case .onboardingCompleted: return AnalyticsEventTutorialComplete

        case .notificationAuthorizationResult: return "notification_authorization_result"
        case .apnsTokenRegistered: return "apns_token_registered"

        case .trackedNumberAdded: return "tracked_number_added"
        case .trackedNumberRemoved: return "tracked_number_removed"
        case .trackedNumberDetailViewed: return "tracked_number_detail_viewed"
        case .notificationPrefChanged: return "notification_pref_changed"

        case .paywallViewed: return "paywall_viewed"
        case .paywallPlanSelected: return "paywall_plan_selected"
        case .purchaseStarted: return "purchase_started"
        case .purchaseSucceeded: return AnalyticsEventPurchase
        case .purchaseCancelled: return "purchase_cancelled"
        case .purchasePending: return "purchase_pending"
        case .purchaseFailed: return "purchase_failed"
        case .restorePurchasesTapped: return "restore_purchases_tapped"
        case .restorePurchasesSucceeded: return "restore_purchases_succeeded"
        case .restorePurchasesFailed: return "restore_purchases_failed"

        case .settingsLinkTapped: return "settings_link_tapped"
        case .addNumberOpened: return "add_number_opened"
        case .upgradeTapped: return "upgrade_tapped"
        }
    }

    fileprivate var parameters: [String: Any] {
        switch self {
        case .signInStarted(let method):
            return [AnalyticsParameterMethod: method]
        case .signInSucceeded(let method, let userId):
            return [AnalyticsParameterMethod: method, "user_id": userId]
        case .signInFailed(let method, let reason):
            return [AnalyticsParameterMethod: method, "reason": reason]
        case .signOut, .accountDeleted, .onboardingStarted,
             .onboardingConsentGiven, .onboardingCompleted,
             .apnsTokenRegistered, .trackedNumberRemoved,
             .trackedNumberDetailViewed, .restorePurchasesTapped,
             .restorePurchasesSucceeded:
            return [:]

        case .onboardingStepViewed(let step, let name):
            return ["step": step, "name": name]

        case .notificationAuthorizationResult(let granted):
            return ["granted": granted]

        case .trackedNumberAdded(let country):
            var p: [String: Any] = [:]
            if let country { p["country"] = country }
            return p

        case .notificationPrefChanged(let name, let enabled):
            return ["pref": name, "enabled": enabled]

        case .paywallViewed(let source), .addNumberOpened(let source), .upgradeTapped(let source):
            return ["source": source]

        case .paywallPlanSelected(let productId),
             .purchaseCancelled(let productId),
             .purchasePending(let productId):
            return [AnalyticsParameterItemID: productId]

        case .purchaseStarted(let productId, let price, let currency):
            return purchaseParameters(productId: productId, price: price, currency: currency)

        case .purchaseSucceeded(let productId, let price, let currency):
            // For the standard `purchase` event Firebase wants `value` and
            // `currency` so revenue rolls up properly in the dashboard.
            var p = purchaseParameters(productId: productId, price: price, currency: currency)
            p[AnalyticsParameterValue] = NSDecimalNumber(decimal: price).doubleValue
            return p

        case .purchaseFailed(let productId, let reason):
            return [AnalyticsParameterItemID: productId, "reason": reason]

        case .restorePurchasesFailed(let reason):
            return ["reason": reason]

        case .settingsLinkTapped(let name):
            return ["link": name]
        }
    }

    private func purchaseParameters(productId: String, price: Decimal, currency: String?) -> [String: Any] {
        var p: [String: Any] = [
            AnalyticsParameterItemID: productId,
            "price": NSDecimalNumber(decimal: price).doubleValue
        ]
        if let currency { p[AnalyticsParameterCurrency] = currency }
        return p
    }
}

// MARK: - Service

/// Process-wide analytics facade. Use `LSAnalytics.shared`.
@MainActor
final class LSAnalytics {
    static let shared = LSAnalytics()

    private(set) var isConfigured = false

    private init() {}

    /// Call once at app launch. Idempotent.
    func configure() {
        guard !isConfigured else { return }
        if FirebaseApp.app() == nil {
            FirebaseApp.configure()
        }
        isConfigured = true

        // Tie unhandled crashes to the same user id we set on Analytics.
        Crashlytics.crashlytics().setCrashlyticsCollectionEnabled(true)
    }

    // MARK: User identity

    /// Sets the Firebase Analytics user ID and Crashlytics user ID so events
    /// and crashes are attributable to the signed-in user.
    func setUser(id: String, email: String?) {
        Analytics.setUserID(id)
        Crashlytics.crashlytics().setUserID(id)
        if let email {
            // Don't send raw email to Analytics (PII); just record presence.
            Analytics.setUserProperty("true", forName: "has_email")
            Crashlytics.crashlytics().setCustomValue(email, forKey: "user_email")
        } else {
            Analytics.setUserProperty("false", forName: "has_email")
        }
    }

    /// Clear identity on sign out / account deletion.
    func clearUser() {
        Analytics.setUserID(nil)
        Crashlytics.crashlytics().setUserID("")
        Analytics.setUserProperty(nil, forName: "has_email")
        Analytics.setUserProperty(nil, forName: "subscription_status")
        Analytics.setUserProperty(nil, forName: "tracked_count")
    }

    // MARK: User properties

    func setSubscriptionStatus(_ isSubscribed: Bool, productId: String? = nil) {
        Analytics.setUserProperty(isSubscribed ? "active" : "free", forName: "subscription_status")
        if let productId {
            Analytics.setUserProperty(productId, forName: "subscription_product")
        } else {
            Analytics.setUserProperty(nil, forName: "subscription_product")
        }
        Crashlytics.crashlytics().setCustomValue(isSubscribed, forKey: "is_subscribed")
    }

    func setTrackedNumberCount(_ count: Int) {
        // Bucket so we don't blow out user-property cardinality.
        let bucket: String
        switch count {
        case 0: bucket = "0"
        case 1: bucket = "1"
        case 2...5: bucket = "2-5"
        case 6...10: bucket = "6-10"
        default: bucket = "11+"
        }
        Analytics.setUserProperty(bucket, forName: "tracked_count")
        Crashlytics.crashlytics().setCustomValue(count, forKey: "tracked_count")
    }

    // MARK: Events

    func log(_ event: AnalyticsEvent) {
        Analytics.logEvent(event.name, parameters: event.parameters)
        // Also drop a Crashlytics breadcrumb so the trail before a crash is
        // easy to reconstruct.
        Crashlytics.crashlytics().log("event=\(event.name)")
    }

    /// Fire a screen_view event for SwiftUI screens (FirebaseAnalytics's
    /// automatic screen tracking only catches UIKit views).
    func logScreen(_ name: String, className: String? = nil) {
        var params: [String: Any] = [AnalyticsParameterScreenName: name]
        if let className {
            params[AnalyticsParameterScreenClass] = className
        }
        Analytics.logEvent(AnalyticsEventScreenView, parameters: params)
        Crashlytics.crashlytics().log("screen=\(name)")
    }

    // MARK: Errors

    /// Record a non-fatal error in Crashlytics with optional context keys.
    func logError(_ error: Error, context: [String: Any] = [:]) {
        let bridged = error as NSError
        var userInfo = bridged.userInfo
        for (k, v) in context { userInfo[k] = v }
        let wrapped = NSError(domain: bridged.domain, code: bridged.code, userInfo: userInfo)
        Crashlytics.crashlytics().record(error: wrapped)
    }

    /// Convenience for `String` events, e.g. when you don't have a typed enum case yet.
    func breadcrumb(_ message: String) {
        Crashlytics.crashlytics().log(message)
    }

    // MARK: Performance traces

    /// Start a performance trace and return a handle the caller can stop.
    /// Returns nil if Performance isn't yet initialised.
    func startTrace(_ name: String) -> Trace? {
        Performance.startTrace(name: name)
    }
}

// MARK: - SwiftUI helpers

import SwiftUI

extension View {
    /// Fire a `screen_view` event when this view appears.
    func trackScreen(_ name: String, className: String? = nil) -> some View {
        self.onAppear {
            LSAnalytics.shared.logScreen(name, className: className)
        }
    }
}
