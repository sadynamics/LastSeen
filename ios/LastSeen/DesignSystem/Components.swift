//
//  Components.swift
//  Reusable UI primitives.
//

import SwiftUI

struct StatusPill: View {
    let isOnline: Bool
    let label: String

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(isOnline ? Theme.Color.online : Theme.Color.offline)
                .frame(width: 8, height: 8)
            Text(label)
                .font(.caption)
                .foregroundStyle(Theme.Color.secondaryText)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(
            Capsule().fill(Theme.Color.surfaceElevated)
        )
    }
}

struct PrimaryButton: View {
    let title: String
    var systemImage: String?
    var isLoading: Bool = false
    var isDisabled: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: { if !isDisabled && !isLoading { action() } }) {
            HStack(spacing: 8) {
                if isLoading {
                    ProgressView().tint(.white)
                } else if let systemImage {
                    Image(systemName: systemImage)
                }
                Text(title)
                    .fontWeight(.semibold)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.md)
                    .fill(isDisabled ? Theme.Color.accent.opacity(0.4) : Theme.Color.accent)
            )
            .foregroundStyle(.white)
        }
        .buttonStyle(.plain)
        .disabled(isDisabled || isLoading)
    }
}

struct SecondaryButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .fontWeight(.medium)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(
                    RoundedRectangle(cornerRadius: Theme.Radius.md)
                        .stroke(Theme.Color.secondaryText.opacity(0.3), lineWidth: 1)
                )
                .foregroundStyle(Theme.Color.primaryText)
        }
        .buttonStyle(.plain)
    }
}

struct EmptyState: View {
    let systemImage: String
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: Theme.Spacing.md) {
            Image(systemName: systemImage)
                .font(.system(size: 48))
                .foregroundStyle(Theme.Color.tertiaryText)
            Text(title)
                .font(.headline)
                .foregroundStyle(Theme.Color.primaryText)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(Theme.Color.secondaryText)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Theme.Spacing.xl)
    }
}

struct Card<Content: View>: View {
    @ViewBuilder var content: () -> Content
    var body: some View {
        content()
            .padding(Theme.Spacing.lg)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.lg)
                    .fill(Theme.Color.surface)
            )
    }
}

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
