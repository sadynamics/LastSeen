//
//  EntitlementInspector.swift
//  Reads the `aps-environment` value that was actually signed into the app
//  binary by Xcode. If the value here is `nil`, the entitlement was stripped
//  at signing time and APNs registration will silently fail no matter what
//  the .entitlements file says — this points at a missing capability on
//  the target or a broken provisioning profile.
//

import Foundation

enum EntitlementInspector {
    /// Reads the value of `aps-environment` from the app's embedded
    /// provisioning profile. Returns nil if the profile doesn't exist (App
    /// Store builds) or doesn't contain the entitlement.
    static func apsEnvironmentFromEmbeddedProfile() -> String? {
        guard let url = Bundle.main.url(forResource: "embedded", withExtension: "mobileprovision"),
              let data = try? Data(contentsOf: url),
              let raw = String(data: data, encoding: .ascii) else {
            return nil
        }
        guard let plistStart = raw.range(of: "<?xml"),
              let plistEnd = raw.range(of: "</plist>") else {
            return nil
        }
        let plistData = Data(raw[plistStart.lowerBound..<plistEnd.upperBound].utf8)
        guard
            let plist = try? PropertyListSerialization.propertyList(from: plistData, format: nil),
            let dict = plist as? [String: Any],
            let entitlements = dict["Entitlements"] as? [String: Any],
            let value = entitlements["aps-environment"] as? String
        else {
            return nil
        }
        return value
    }

    /// True if the embedded provisioning profile is present (i.e. dev /
    /// ad-hoc / enterprise build). False for App Store builds where the
    /// profile is consumed at install time.
    static var hasEmbeddedProfile: Bool {
        Bundle.main.url(forResource: "embedded", withExtension: "mobileprovision") != nil
    }
}
