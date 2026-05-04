//
//  Components.swift
//  Reusable UI primitives for the LastSeen design system.
//

import SwiftUI

// MARK: - Backgrounds

/// Animated, layered app background. Use as the bottom layer of every screen.
struct AppBackground: View {
    var body: some View {
        ZStack {
            Theme.Color.background.ignoresSafeArea()
            Theme.Gradient.background.ignoresSafeArea()
            Theme.Gradient.heroBloom
                .ignoresSafeArea()
                .blendMode(.plusLighter)
                .opacity(0.55)
        }
    }
}

// MARK: - Buttons

/// Press-down scale + opacity feedback used on interactive cards and chips.
struct ScalePressStyle: ButtonStyle {
    var scale: CGFloat = 0.97
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1.0)
            .opacity(configuration.isPressed ? 0.85 : 1.0)
            .animation(Theme.Motion.snap, value: configuration.isPressed)
    }
}

struct PrimaryButton: View {
    let title: String
    var systemImage: String?
    var isLoading: Bool = false
    var isDisabled: Bool = false
    var fullWidth: Bool = true
    let action: () -> Void

    var body: some View {
        Button(action: { if !isDisabled && !isLoading { action() } }) {
            HStack(spacing: 10) {
                if isLoading {
                    ProgressView().tint(.white)
                } else if let systemImage {
                    Image(systemName: systemImage).font(.callout.weight(.semibold))
                }
                Text(title).font(Theme.Font.headline)
            }
            .foregroundStyle(.white)
            .frame(maxWidth: fullWidth ? .infinity : nil)
            .padding(.horizontal, fullWidth ? 0 : 22)
            .padding(.vertical, 16)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
                    .fill(Theme.Gradient.primaryButton)
                    .opacity(isDisabled ? 0.45 : 1.0)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
                    .stroke(Color.white.opacity(0.18), lineWidth: 0.5)
            )
            .ds(shadow: isDisabled ? Theme.Shadow(color: .clear, radius: 0, x: 0, y: 0) : .button)
        }
        .buttonStyle(ScalePressStyle())
        .disabled(isDisabled || isLoading)
    }
}

struct SecondaryButton: View {
    let title: String
    var systemImage: String?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if let systemImage {
                    Image(systemName: systemImage).font(.callout.weight(.semibold))
                }
                Text(title).font(Theme.Font.headline)
            }
            .foregroundStyle(Theme.Color.primaryText)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
                    .fill(Color.white.opacity(0.06))
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
                    .stroke(Color.white.opacity(0.12), lineWidth: 0.5)
            )
        }
        .buttonStyle(ScalePressStyle())
    }
}

// MARK: - Cards

/// Frosted-glass card. The default surface for almost every section.
struct Card<Content: View>: View {
    var padding: CGFloat = Theme.Spacing.lg
    var cornerRadius: CGFloat = Theme.Radius.lg
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .padding(padding)
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(.ultraThinMaterial)
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(Theme.Gradient.surfaceSheen)
                }
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(Color.white.opacity(0.06), lineWidth: 1)
            )
            .ds(shadow: .card)
    }
}

// MARK: - Status indicators

/// Small dot that pulses softly when "online".
struct GlowingDot: View {
    let isOn: Bool
    var size: CGFloat = 8
    @State private var pulse = false

    var body: some View {
        ZStack {
            if isOn {
                Circle()
                    .fill(Theme.Color.online)
                    .frame(width: size * 2.4, height: size * 2.4)
                    .opacity(pulse ? 0.0 : 0.45)
                    .scaleEffect(pulse ? 1.2 : 0.6)
                    .animation(.easeOut(duration: 1.6).repeatForever(autoreverses: false), value: pulse)
            }
            Circle()
                .fill(isOn ? Theme.Color.online : Theme.Color.offline)
                .frame(width: size, height: size)
                .ds(shadow: isOn ? .onlineGlow : Theme.Shadow(color: .clear, radius: 0, x: 0, y: 0))
        }
        .frame(width: size * 2.4, height: size * 2.4)
        .onAppear { pulse = true }
    }
}

struct StatusPill: View {
    let isOnline: Bool
    let label: String

    var body: some View {
        HStack(spacing: 6) {
            GlowingDot(isOn: isOnline, size: 7)
            Text(label)
                .font(Theme.Font.caption.weight(.medium))
                .foregroundStyle(isOnline ? Theme.Color.online : Theme.Color.secondaryText)
        }
        .padding(.leading, 4)
        .padding(.trailing, 12)
        .padding(.vertical, 4)
        .background(
            Capsule().fill(
                isOnline
                    ? Theme.Color.online.opacity(0.12)
                    : Color.white.opacity(0.06)
            )
        )
        .overlay(
            Capsule().stroke(
                isOnline
                    ? Theme.Color.online.opacity(0.30)
                    : Color.white.opacity(0.08),
                lineWidth: 0.5
            )
        )
    }
}

// MARK: - Avatars

/// Colorful gradient avatar — the gradient is deterministic per seed, so the
/// same number always shows the same colors.
struct GradientAvatar: View {
    let initials: String
    let seed: String
    var size: CGFloat = 44

    private static let palettes: [[Color]] = [
        [Color(red: 0.36, green: 0.55, blue: 1.00), Color(red: 0.69, green: 0.42, blue: 1.00)],
        [Color(red: 0.30, green: 0.86, blue: 0.74), Color(red: 0.36, green: 0.55, blue: 1.00)],
        [Color(red: 1.00, green: 0.55, blue: 0.41), Color(red: 1.00, green: 0.45, blue: 0.61)],
        [Color(red: 0.99, green: 0.72, blue: 0.30), Color(red: 1.00, green: 0.45, blue: 0.61)],
        [Color(red: 0.20, green: 0.86, blue: 0.50), Color(red: 0.30, green: 0.86, blue: 0.74)],
        [Color(red: 0.55, green: 0.74, blue: 1.00), Color(red: 0.69, green: 0.42, blue: 1.00)]
    ]

    private var gradientColors: [Color] {
        let hash = seed.unicodeScalars.reduce(0) { $0 &+ Int($1.value) }
        return Self.palettes[abs(hash) % Self.palettes.count]
    }

    var body: some View {
        Circle()
            .fill(LinearGradient(colors: gradientColors, startPoint: .topLeading, endPoint: .bottomTrailing))
            .overlay(
                Text(initials)
                    .font(.system(size: size * 0.4, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
            )
            .overlay(
                Circle().stroke(Color.white.opacity(0.15), lineWidth: 1)
            )
            .frame(width: size, height: size)
    }
}

// MARK: - Section header

struct SectionHeader: View {
    let title: String
    var subtitle: String? = nil
    var trailing: AnyView? = nil

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title.uppercased())
                    .font(Theme.Font.label)
                    .tracking(1.2)
                    .foregroundStyle(Theme.Color.tertiaryText)
                if let subtitle {
                    Text(subtitle)
                        .font(Theme.Font.caption)
                        .foregroundStyle(Theme.Color.secondaryText)
                }
            }
            Spacer()
            if let trailing { trailing }
        }
    }
}

// MARK: - Icon badge

/// Square rounded icon container — used for benefits, settings rows, etc.
struct IconBadge: View {
    let systemImage: String
    var tint: Color = Theme.Color.accent
    var size: CGFloat = 36

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                .fill(tint.opacity(0.18))
            RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                .stroke(tint.opacity(0.25), lineWidth: 0.5)
            Image(systemName: systemImage)
                .font(.system(size: size * 0.46, weight: .semibold))
                .foregroundStyle(tint)
        }
        .frame(width: size, height: size)
    }
}

// MARK: - Stat tile

struct StatTile: View {
    let label: String
    let value: String
    var systemImage: String? = nil
    var tint: Color = Theme.Color.accent

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(tint)
                }
                Text(label.uppercased())
                    .font(Theme.Font.label)
                    .tracking(0.8)
                    .foregroundStyle(Theme.Color.tertiaryText)
            }
            Text(value)
                .font(Theme.Font.numericMedium)
                .foregroundStyle(Theme.Color.primaryText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Theme.Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
                .fill(Color.white.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
                .stroke(Color.white.opacity(0.06), lineWidth: 0.5)
        )
    }
}

// MARK: - Empty state

struct EmptyState: View {
    let systemImage: String
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: Theme.Spacing.lg) {
            ZStack {
                Circle()
                    .fill(Theme.Color.accent.opacity(0.15))
                    .frame(width: 96, height: 96)
                Circle()
                    .stroke(Theme.Color.accent.opacity(0.25), lineWidth: 1)
                    .frame(width: 96, height: 96)
                Image(systemName: systemImage)
                    .font(.system(size: 38, weight: .light))
                    .foregroundStyle(Theme.Color.accentLight)
            }
            VStack(spacing: 6) {
                Text(title)
                    .font(Theme.Font.title3)
                    .foregroundStyle(Theme.Color.primaryText)
                Text(message)
                    .font(Theme.Font.callout)
                    .foregroundStyle(Theme.Color.secondaryText)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(Theme.Spacing.xl)
    }
}

// MARK: - Floating Action Button

struct FloatingActionButton: View {
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(Theme.Gradient.primaryButton)
                    .frame(width: 58, height: 58)
                    .ds(shadow: .button)
                Image(systemName: systemImage)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(.white)
            }
            .overlay(
                Circle().stroke(Color.white.opacity(0.18), lineWidth: 0.5)
            )
        }
        .buttonStyle(ScalePressStyle(scale: 0.92))
    }
}

// MARK: - Formatting helpers

extension Int {
    /// Format a duration in seconds as e.g. "12m", "1h 4m", "45s".
    var asDuration: String {
        if self < 60 { return "\(self)s" }
        if self < 3600 { return "\(Int((Double(self) / 60).rounded()))m" }
        let h = self / 3600
        let m = (self - h * 3600) / 60
        return m == 0 ? "\(h)h" : "\(h)h \(m)m"
    }
}

extension Date {
    /// Localized "12 minutes ago".
    var relativeShort: String {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .short
        return f.localizedString(for: self, relativeTo: .now)
    }
}
