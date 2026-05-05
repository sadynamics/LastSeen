//
//  EntitlementInspector.swift
//  Reads the entitlements that were signed into the app at build time so we
//  can verify, on-device, what iOS thinks our process is entitled to. If
//  `aps-environment` here is `nil`, the entitlement was stripped at signing
//  time (broken provisioning profile / missing capability on the App ID)
//  and APNs registration will silently fail no matter what the
//  `.entitlements` file in the project says.
//
//  iOS does not expose a public runtime API to read your own entitlements
//  (the SecTask* APIs are macOS-only), so we parse the embedded
//  provisioning profile, which is itself the source of truth for the
//  entitlements iOS will grant.
//

import Foundation

enum EntitlementInspector {
    /// True if the embedded provisioning profile is present (i.e. dev /
    /// ad-hoc / enterprise build). False for App Store builds where the
    /// profile is consumed at install time.
    static var hasEmbeddedProfile: Bool {
        Bundle.main.url(forResource: "embedded", withExtension: "mobileprovision") != nil
    }

    /// Parses the `aps-environment` value out of the embedded provisioning
    /// profile. Mobileprovision files are CMS (PKCS#7) signed binary blobs
    /// that embed an XML plist; we scan the raw bytes for the plist markers
    /// rather than trying to decode the whole file as a string (which fails
    /// because of binary signature bytes outside the ASCII range).
    static func apsEnvironmentFromEmbeddedProfile() -> String? {
        guard let entitlements = entitlementsFromEmbeddedProfile() else { return nil }
        return entitlements["aps-environment"] as? String
    }

    /// Returns the full entitlements dictionary signed into the embedded
    /// provisioning profile, or nil if the profile is missing / unparseable.
    static func entitlementsFromEmbeddedProfile() -> [String: Any]? {
        guard let url = Bundle.main.url(forResource: "embedded", withExtension: "mobileprovision"),
              let data = try? Data(contentsOf: url) else {
            return nil
        }
        guard let xmlStartMarker = "<?xml".data(using: .utf8),
              let xmlEndMarker = "</plist>".data(using: .utf8),
              let startRange = data.range(of: xmlStartMarker),
              let endRange = data.range(of: xmlEndMarker) else {
            return nil
        }
        let plistData = data.subdata(in: startRange.lowerBound..<endRange.upperBound)
        guard
            let plist = try? PropertyListSerialization.propertyList(from: plistData, format: nil),
            let dict = plist as? [String: Any]
        else {
            return nil
        }
        return dict["Entitlements"] as? [String: Any]
    }
}
