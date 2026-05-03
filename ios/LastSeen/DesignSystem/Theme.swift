//
//  Theme.swift
//  Color tokens, typography, and shared UI primitives.
//

import SwiftUI

enum Theme {
    enum Color {
        static let background = SwiftUI.Color("LSBackground", bundle: nil, fallback: Self.fallbackBackground)
        static let surface = SwiftUI.Color("LSSurface", bundle: nil, fallback: Self.fallbackSurface)
        static let surfaceElevated = SwiftUI.Color("LSSurfaceElevated", bundle: nil, fallback: Self.fallbackSurfaceElevated)
        static let primaryText = SwiftUI.Color("LSPrimaryText", bundle: nil, fallback: .white)
        static let secondaryText = SwiftUI.Color("LSSecondaryText", bundle: nil, fallback: SwiftUI.Color.white.opacity(0.7))
        static let tertiaryText = SwiftUI.Color("LSTertiaryText", bundle: nil, fallback: SwiftUI.Color.white.opacity(0.45))
        static let online = SwiftUI.Color(red: 0.20, green: 0.84, blue: 0.41)
        static let offline = SwiftUI.Color(red: 0.55, green: 0.55, blue: 0.60)
        static let accent = SwiftUI.Color(red: 0.18, green: 0.50, blue: 1.0)
        static let danger = SwiftUI.Color(red: 0.95, green: 0.30, blue: 0.40)
        static let warning = SwiftUI.Color(red: 0.95, green: 0.65, blue: 0.20)

        private static let fallbackBackground = SwiftUI.Color(red: 0.04, green: 0.05, blue: 0.07)
        private static let fallbackSurface = SwiftUI.Color(red: 0.09, green: 0.10, blue: 0.13)
        private static let fallbackSurfaceElevated = SwiftUI.Color(red: 0.13, green: 0.14, blue: 0.18)
    }

    enum Spacing {
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 12
        static let lg: CGFloat = 16
        static let xl: CGFloat = 24
        static let xxl: CGFloat = 32
    }

    enum Radius {
        static let sm: CGFloat = 8
        static let md: CGFloat = 12
        static let lg: CGFloat = 16
        static let xl: CGFloat = 24
    }
}

// Helper to allow a fallback when a named asset is absent (so the app doesn't
// look broken before color assets are added).
private extension SwiftUI.Color {
    init(_ name: String, bundle: Bundle?, fallback: SwiftUI.Color) {
        if UIColor(named: name) != nil {
            self.init(name, bundle: bundle)
        } else {
            self = fallback
        }
    }
}
