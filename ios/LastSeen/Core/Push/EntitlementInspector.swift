//
//  EntitlementInspector.swift
//  Reads the entitlements iOS has actually granted to the running process at
//  runtime. If `aps-environment` here is `nil`, the entitlement was stripped
//  at signing time and APNs registration will silently fail no matter what
//  the .entitlements file says — this points at a missing capability on the
//  App ID or a broken provisioning profile.
//

import Foundation
import Security

enum EntitlementInspector {
    /// Asks iOS what `aps-environment` value our process is signed with right
    /// now. Returns nil if the entitlement is absent.
    ///
    /// This is the source of truth — much more reliable than parsing
    /// `embedded.mobileprovision` (which is a CMS-signed binary blob).
    static func apsEnvironmentRuntime() -> String? {
        guard let task = SecTaskCreateFromSelf(nil) else { return nil }
        var error: Unmanaged<CFError>?
        let raw = SecTaskCopyValueForEntitlement(task, "aps-environment" as CFString, &error)
        if let value = raw?.takeRetainedValue() as? String {
            return value
        }
        return nil
    }

    /// True if the embedded provisioning profile is present (i.e. dev /
    /// ad-hoc / enterprise build). False for App Store builds where the
    /// profile is consumed at install time.
    static var hasEmbeddedProfile: Bool {
        Bundle.main.url(forResource: "embedded", withExtension: "mobileprovision") != nil
    }

    /// Parses the `aps-environment` value out of the embedded provisioning
    /// profile, as a fallback / sanity check against the runtime value.
    /// Mobileprovision files are CMS (PKCS#7) signed binary blobs that
    /// embed an XML plist; we scan the raw bytes for the plist markers
    /// rather than trying to decode the whole file as a string (which fails
    /// because of binary signature bytes outside the ASCII range).
    static func apsEnvironmentFromEmbeddedProfile() -> String? {
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
            let dict = plist as? [String: Any],
            let entitlements = dict["Entitlements"] as? [String: Any]
        else {
            return nil
        }
        return entitlements["aps-environment"] as? String
    }
}
