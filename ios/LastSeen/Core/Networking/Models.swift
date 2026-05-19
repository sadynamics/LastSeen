//
//  Models.swift
//  All wire types are explicitly nonisolated so their Codable conformances
//  remain Sendable across actors (required because the project's default
//  actor isolation is MainActor).
//

import Foundation

// MARK: - Auth

nonisolated struct AppleSignInRequest: Encodable, Sendable {
    let identityToken: String
    let email: String?
    let locale: String?
}

nonisolated struct AppleSignInResponse: Decodable, Sendable {
    let token: String
    let user: User
}

/// Response of `GET /v1/config/public`. Tiny public blob used by the
/// Sign In screen to decide whether the App Reviewer Sign-In link
/// should be visible. The backend derives `reviewerSignInEnabled` from
/// the `REVIEWER_LOGIN_CODE` env var, so toggling that var off on
/// Railway post-approval auto-hides the link without an app
/// resubmission.
nonisolated struct PublicConfig: Decodable, Sendable {
    let reviewerSignInEnabled: Bool
}

/// Body for `POST /v1/auth/reviewer`. Used by the App Review-only login
/// path; gated on the backend by the `REVIEWER_LOGIN_CODE` env var so the
/// endpoint 404s when unset.
///
/// Supports two shapes so we can both keep the legacy hidden triple-tap
/// flow (`code`) and present a normal Username + Password form whose
/// values map 1:1 to App Store Connect → Sign-In Information
/// (`username` + `password`). The backend validates `password` (falling
/// back to `code`) against the shared secret.
nonisolated struct ReviewerSignInRequest: Encodable, Sendable {
    let code: String?
    let username: String?
    let password: String?
    let locale: String?
}

nonisolated struct User: Codable, Hashable, Sendable {
    let id: String
    let email: String?
    let createdAt: Date?
}

// MARK: - Devices

nonisolated struct DeviceRegistrationRequest: Encodable, Sendable {
    let apnsToken: String
    let environment: String
    let appVersion: String?
    let osVersion: String?
    let locale: String?
}

nonisolated struct DeviceRegistrationResponse: Decodable, Sendable {
    let id: String
}

nonisolated struct MyDevicesResponse: Decodable, Sendable {
    nonisolated struct Item: Decodable, Sendable {
        let id: String
        let tokenPrefix: String
        let environment: String?
        let appVersion: String?
        let osVersion: String?
        let lastSeenAt: Date?
    }
    let count: Int
    let items: [Item]
}

nonisolated struct TestPushResponse: Decodable, Sendable {
    let devicesTargeted: Int
}

// MARK: - Tracked numbers

nonisolated enum ScraperStatus: String, Codable, Sendable {
    case PAIRING, WARMING, HEALTHY, COOLING, BANNED, RETIRED
    var isReady: Bool { self == .HEALTHY || self == .WARMING }
}

nonisolated struct ScraperRef: Codable, Hashable, Sendable {
    let status: ScraperStatus
}

nonisolated struct NotificationPrefs: Codable, Hashable, Sendable {
    var onlineEnabled: Bool
    var offlineEnabled: Bool
    var sessionEndedEnabled: Bool
    var dailySummaryEnabled: Bool
    var quietHoursStart: Int?
    var quietHoursEnd: Int?
    var timezone: String?
}

nonisolated struct TrackedNumber: Codable, Hashable, Identifiable, Sendable {
    let id: String
    let userId: String
    let e164: String
    let jid: String?
    var displayName: String?
    let countryCode: String?
    let scraperAccountId: String?
    let archivedAt: Date?
    let createdAt: Date
    var prefs: NotificationPrefs?
    var scraperAccount: ScraperRef?
}

nonisolated struct TrackedNumbersList: Decodable, Sendable {
    let items: [TrackedNumber]
}

nonisolated struct CreateTrackedNumberRequest: Encodable, Sendable {
    let phone: String
    let defaultCountry: String?
    let displayName: String?
}

nonisolated struct TrackedNumberWrapper: Decodable, Sendable {
    let item: TrackedNumber
}

nonisolated enum PresenceStatus: String, Codable, Sendable {
    case AVAILABLE, UNAVAILABLE, COMPOSING, RECORDING, PAUSED
}

nonisolated struct LiveStatus: Codable, Hashable, Sendable {
    let trackedNumberId: String
    let isOnline: Bool
    let lastEventAt: Date?
    let lastStatus: PresenceStatus?
    let onlineSince: Date?
    let lastSeenSecondsAgo: Int?
}

nonisolated struct DaySession: Codable, Hashable, Sendable {
    let start: Date
    let end: Date
    let durationSeconds: Int
}

nonisolated struct SessionsForDay: Codable, Sendable {
    let day: String
    let sessions: [DaySession]
    let totalOnlineSeconds: Int
    let sessionCount: Int
}

nonisolated struct WeeklyDay: Codable, Hashable, Sendable, Identifiable {
    let day: String
    let totalOnlineSeconds: Int
    let sessionCount: Int
    let peakHour: Int?
    var id: String { day }
}

nonisolated struct WeeklyReport: Codable, Sendable {
    let weekStart: String
    let weekEnd: String
    let days: [WeeklyDay]
    let totalOnlineSeconds: Int
    let averagePerDaySeconds: Int
}

nonisolated struct PrefsWrapper: Codable, Sendable {
    let prefs: NotificationPrefs
}

// MARK: - Billing

nonisolated struct BillingVerifyRequest: Encodable, Sendable {
    let signedTransaction: String
}

nonisolated struct BillingVerifyResponse: Decodable, Sendable {
    let ok: Bool
    let productId: String
    let originalTransactionId: String
    let expiresAt: Date
    let environment: String
}

nonisolated struct BillingStatus: Decodable, Sendable {
    nonisolated struct SubscriptionInfo: Decodable, Sendable, Hashable {
        let productId: String
        let status: String
        let expiresAt: Date
        let autoRenewEnabled: Bool
        let environment: String
    }
    let isSubscribed: Bool
    let subscription: SubscriptionInfo?
    /// Number of tracked numbers this user can keep active WITHOUT an
    /// active Premium subscription. Always 0 for normal users; 1 for
    /// App Review reviewer accounts so reviewers can test the core
    /// tracking flow without redeeming a sandbox purchase, while the
    /// 2nd add still surfaces the paywall.
    /// Optional for backward compatibility with older backends.
    let freeTrackedSlots: Int?
}

// MARK: - Me

nonisolated struct MeResponse: Decodable, Sendable {
    nonisolated struct UserPart: Decodable, Sendable {
        let id: String
        let email: String?
        let locale: String?
        let createdAt: Date
        let trackedNumbersCount: Int
    }
    nonisolated struct SubPart: Decodable, Sendable {
        let productId: String
        let status: String
        let expiresAt: Date
        let autoRenewEnabled: Bool
    }
    let user: UserPart?
    let subscription: SubPart?
}
