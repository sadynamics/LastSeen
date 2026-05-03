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

nonisolated struct User: Codable, Hashable, Sendable {
    let id: String
    let email: String?
    let createdAt: Date?
}

// MARK: - Devices

nonisolated struct DeviceRegistrationRequest: Encodable, Sendable {
    let apnsToken: String
    let appVersion: String?
    let osVersion: String?
    let locale: String?
}

nonisolated struct DeviceRegistrationResponse: Decodable, Sendable {
    let id: String
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
