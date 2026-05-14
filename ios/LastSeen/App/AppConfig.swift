//
//  AppConfig.swift
//

import Foundation

enum AppConfig {
    /// Resolved at launch from the `API_BASE_URL` env var (set in the Xcode scheme),
    /// the `APIBaseURL` Info.plist key, or a sensible default per build config.
    static let apiBaseURL: URL = {
        if let env = ProcessInfo.processInfo.environment["API_BASE_URL"],
           let url = URL(string: env) {
            return url
        }
        if let plist = Bundle.main.object(forInfoDictionaryKey: "APIBaseURL") as? String,
           let url = URL(string: plist) {
            return url
        }
        return URL(string: "https://api-production-466c.up.railway.app")!
    }()

    static let appGroup = "group.collabrainstech.LastSeen"
    static let bundleId = Bundle.main.bundleIdentifier ?? "collabrainstech.LastSeen"

    enum Subscription {
        static let weeklyProductId = "collabrainstech.LastSeen.weekly"
        static let yearlyProductId = "collabrainstech.LastSeen.yearly"
        static let allIds: [String] = [weeklyProductId, yearlyProductId]
    }
}
