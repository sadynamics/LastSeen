//
//  Theme.swift
//  Color, typography, gradient, shadow, and motion tokens for the LastSeen design system.
//

import SwiftUI

enum Theme {
    // MARK: Colors
    enum Color {
        // Surfaces
        static let background = SwiftUI.Color("LSBackground", bundle: nil, fallback: Self.fallbackBackground)
        static let surface = SwiftUI.Color("LSSurface", bundle: nil, fallback: Self.fallbackSurface)
        static let surfaceElevated = SwiftUI.Color("LSSurfaceElevated", bundle: nil, fallback: Self.fallbackSurfaceElevated)
        static let separator = SwiftUI.Color.white.opacity(0.07)

        // Text
        static let primaryText = SwiftUI.Color.white
        static let secondaryText = SwiftUI.Color.white.opacity(0.72)
        static let tertiaryText = SwiftUI.Color.white.opacity(0.42)

        // Brand & semantic
        /// Brand accent — vibrant indigo with a hint of cyan. Use as the primary CTA fill.
        static let accent = SwiftUI.Color(red: 0.36, green: 0.55, blue: 1.00)
        /// Lighter accent for accents, glows, and gradient ends.
        static let accentLight = SwiftUI.Color(red: 0.55, green: 0.74, blue: 1.00)
        /// Secondary accent for variety in icons and badges (a vivid violet).
        static let accentSecondary = SwiftUI.Color(red: 0.69, green: 0.42, blue: 1.00)

        static let online = SwiftUI.Color(red: 0.20, green: 0.86, blue: 0.50)
        static let offline = SwiftUI.Color(red: 0.55, green: 0.55, blue: 0.60)
        static let warning = SwiftUI.Color(red: 0.99, green: 0.72, blue: 0.30)
        static let danger = SwiftUI.Color(red: 0.98, green: 0.36, blue: 0.45)

        // Tints used in iconography
        static let tintMint = SwiftUI.Color(red: 0.30, green: 0.86, blue: 0.74)
        static let tintAmber = SwiftUI.Color(red: 0.99, green: 0.72, blue: 0.30)
        static let tintRose = SwiftUI.Color(red: 1.00, green: 0.45, blue: 0.61)

        // Fallbacks (used when no color asset is bundled)
        private static let fallbackBackground = SwiftUI.Color(red: 0.040, green: 0.045, blue: 0.067)
        private static let fallbackSurface = SwiftUI.Color(red: 0.085, green: 0.095, blue: 0.130)
        private static let fallbackSurfaceElevated = SwiftUI.Color(red: 0.130, green: 0.142, blue: 0.180)
    }

    // MARK: Gradients
    enum Gradient {
        /// Background "aurora" — deep navy with a soft purple bloom near the top.
        static let background = LinearGradient(
            colors: [
                SwiftUI.Color(red: 0.06, green: 0.06, blue: 0.12),
                SwiftUI.Color(red: 0.04, green: 0.05, blue: 0.07),
                SwiftUI.Color(red: 0.03, green: 0.04, blue: 0.06)
            ],
            startPoint: .top,
            endPoint: .bottom
        )

        /// Subtle radial bloom in brand color for hero sections.
        static let heroBloom = RadialGradient(
            colors: [
                Color.accent.opacity(0.25),
                Color.accent.opacity(0.0)
            ],
            center: .top,
            startRadius: 30,
            endRadius: 320
        )

        /// Primary CTA — diagonal accent gradient.
        static let primaryButton = LinearGradient(
            colors: [Color.accent, Color.accentLight],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )

        /// Card surface gradient — subtle vertical sheen.
        static let surfaceSheen = LinearGradient(
            colors: [
                Color.surfaceElevated.opacity(0.75),
                Color.surface.opacity(0.55)
            ],
            startPoint: .top,
            endPoint: .bottom
        )

        /// Online status — bright mint to green.
        static let online = LinearGradient(
            colors: [Color.tintMint, Color.online],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )

        /// Premium / paywall highlight.
        static let premium = LinearGradient(
            colors: [
                SwiftUI.Color(red: 0.99, green: 0.78, blue: 0.36),
                SwiftUI.Color(red: 0.99, green: 0.55, blue: 0.41)
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
    }

    // MARK: Typography
    enum Font {
        /// Large display title — used for screen titles and hero numbers.
        static let display = SwiftUI.Font.system(.largeTitle, design: .rounded, weight: .bold)
        static let title = SwiftUI.Font.system(.title, design: .rounded, weight: .bold)
        static let title2 = SwiftUI.Font.system(.title2, design: .rounded, weight: .semibold)
        static let title3 = SwiftUI.Font.system(.title3, design: .rounded, weight: .semibold)
        static let headline = SwiftUI.Font.system(.headline, design: .rounded, weight: .semibold)
        static let body = SwiftUI.Font.system(.body, design: .default)
        static let callout = SwiftUI.Font.system(.callout, design: .default)
        static let subheadline = SwiftUI.Font.system(.subheadline, design: .default)
        static let footnote = SwiftUI.Font.system(.footnote, design: .default)
        static let caption = SwiftUI.Font.system(.caption, design: .default)
        static let captionMono = SwiftUI.Font.system(.caption, design: .monospaced)

        /// Use for big numeric stats so digits don't jitter.
        static let numericLarge = SwiftUI.Font.system(.title, design: .rounded, weight: .bold)
            .monospacedDigit()
        static let numericMedium = SwiftUI.Font.system(.title3, design: .rounded, weight: .semibold)
            .monospacedDigit()

        /// Tiny uppercase labels used on stat chips.
        static let label = SwiftUI.Font.system(.caption2, design: .rounded, weight: .bold)
    }

    // MARK: Spacing
    enum Spacing {
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 12
        static let lg: CGFloat = 16
        static let xl: CGFloat = 24
        static let xxl: CGFloat = 32
        static let xxxl: CGFloat = 44
    }

    // MARK: Radii
    enum Radius {
        static let xs: CGFloat = 6
        static let sm: CGFloat = 10
        static let md: CGFloat = 14
        static let lg: CGFloat = 20
        static let xl: CGFloat = 28
        static let pill: CGFloat = 999
    }

    // MARK: Shadows
    struct Shadow {
        let color: SwiftUI.Color
        let radius: CGFloat
        let x: CGFloat
        let y: CGFloat

        static let card = Shadow(color: .black.opacity(0.35), radius: 18, x: 0, y: 10)
        static let button = Shadow(color: Color.accent.opacity(0.45), radius: 18, x: 0, y: 8)
        static let glow = Shadow(color: Color.accent.opacity(0.6), radius: 22, x: 0, y: 0)
        static let onlineGlow = Shadow(color: Color.online.opacity(0.85), radius: 8, x: 0, y: 0)
    }

    // MARK: Motion
    enum Motion {
        static let snap = SwiftUI.Animation.spring(response: 0.32, dampingFraction: 0.78)
        static let smooth = SwiftUI.Animation.easeInOut(duration: 0.25)
        static let breath = SwiftUI.Animation.easeInOut(duration: 1.4).repeatForever(autoreverses: true)
    }
}

// MARK: - Helpers

private extension SwiftUI.Color {
    /// Use a named color asset if present, otherwise fall back to a literal Color.
    init(_ name: String, bundle: Bundle?, fallback: SwiftUI.Color) {
        if UIColor(named: name) != nil {
            self.init(name, bundle: bundle)
        } else {
            self = fallback
        }
    }
}

extension View {
    /// Apply one of the design system shadow presets.
    func ds(shadow: Theme.Shadow) -> some View {
        self.shadow(color: shadow.color, radius: shadow.radius, x: shadow.x, y: shadow.y)
    }
}
