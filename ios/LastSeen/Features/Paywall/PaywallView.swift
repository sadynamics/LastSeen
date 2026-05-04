//
//  PaywallView.swift
//

import StoreKit
import SwiftUI

struct PaywallView: View {
    @Environment(SubscriptionService.self) private var subscriptions
    @Environment(\.dismiss) private var dismiss

    @State private var selectedProductId: String?
    @State private var isPurchasing = false
    @State private var errorMessage: String?

    var body: some View {
        ZStack {
            AppBackground()
            ScrollView {
                VStack(spacing: Theme.Spacing.xl) {
                    header
                    benefits
                    plans
                    actionButtons
                    legalRow
                }
                .padding(Theme.Spacing.lg)
                .padding(.bottom, Theme.Spacing.xxl)
            }
            .scrollIndicators(.hidden)
        }
        .overlay(alignment: .topTrailing) {
            Button { dismiss() } label: {
                ZStack {
                    Circle()
                        .fill(.ultraThinMaterial)
                        .frame(width: 32, height: 32)
                    Image(systemName: "xmark")
                        .font(.footnote.weight(.bold))
                        .foregroundStyle(Theme.Color.secondaryText)
                }
            }
            .padding(Theme.Spacing.lg)
        }
        .task {
            if subscriptions.products.isEmpty {
                await subscriptions.loadProducts()
            }
            if selectedProductId == nil {
                selectedProductId = subscriptions.products
                    .first(where: { $0.id == AppConfig.Subscription.monthlyProductId })?.id
                    ?? subscriptions.products.first?.id
            }
        }
        .trackScreen("paywall", className: "PaywallView")
        .onAppear { LSAnalytics.shared.log(.paywallViewed(source: "in_app")) }
    }

    // MARK: Header

    private var header: some View {
        VStack(spacing: Theme.Spacing.md) {
            ZStack {
                Circle()
                    .fill(Theme.Color.accent.opacity(0.18))
                    .frame(width: 96, height: 96)
                Circle()
                    .stroke(Theme.Color.accent.opacity(0.30), lineWidth: 1)
                    .frame(width: 96, height: 96)
                Image(systemName: "sparkles")
                    .font(.system(size: 42, weight: .semibold))
                    .foregroundStyle(Theme.Gradient.premium)
            }
            .ds(shadow: .glow)
            .padding(.top, Theme.Spacing.lg)

            VStack(spacing: 6) {
                Text("Unlock LastSeen Pro")
                    .font(Theme.Font.title)
                    .foregroundStyle(Theme.Color.primaryText)
                    .multilineTextAlignment(.center)
                Text("Track unlimited numbers, get real-time alerts,\nand unlock the full insights dashboard.")
                    .font(Theme.Font.callout)
                    .foregroundStyle(Theme.Color.secondaryText)
                    .multilineTextAlignment(.center)
            }
        }
    }

    // MARK: Benefits

    private var benefits: some View {
        Card {
            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                benefit("Track unlimited numbers", "infinity",
                        tint: Theme.Color.accent)
                Divider().background(Theme.Color.separator)
                benefit("Real-time online & offline alerts", "bell.badge.fill",
                        tint: Theme.Color.tintMint)
                Divider().background(Theme.Color.separator)
                benefit("Daily and weekly reports", "chart.xyaxis.line",
                        tint: Theme.Color.accentSecondary)
                Divider().background(Theme.Color.separator)
                benefit("Peak-hour heatmap", "flame.fill",
                        tint: Theme.Color.tintAmber)
                Divider().background(Theme.Color.separator)
                benefit("Cancel anytime", "checkmark.shield.fill",
                        tint: Theme.Color.online)
            }
        }
    }

    private func benefit(_ text: String, _ icon: String, tint: Color) -> some View {
        HStack(alignment: .center, spacing: Theme.Spacing.md) {
            IconBadge(systemImage: icon, tint: tint, size: 32)
            Text(text)
                .foregroundStyle(Theme.Color.primaryText)
                .font(Theme.Font.callout)
            Spacer(minLength: 0)
        }
    }

    // MARK: Plans

    private var plans: some View {
        VStack(spacing: Theme.Spacing.md) {
            if subscriptions.products.isEmpty {
                ProgressView().tint(Theme.Color.accent)
                    .padding(Theme.Spacing.lg)
            } else {
                ForEach(subscriptions.products, id: \.id) { product in
                    planRow(product)
                }
            }
        }
    }

    private func planRow(_ product: Product) -> some View {
        let selected = selectedProductId == product.id
        let isMonthly = product.id == AppConfig.Subscription.monthlyProductId

        return Button {
            if selectedProductId != product.id {
                LSAnalytics.shared.log(.paywallPlanSelected(productId: product.id))
            }
            selectedProductId = product.id
        } label: {
            VStack(alignment: .leading, spacing: 0) {
                if isMonthly {
                    HStack {
                        Text("BEST VALUE")
                            .font(Theme.Font.label)
                            .tracking(1.0)
                            .foregroundStyle(.black)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(Capsule().fill(Theme.Gradient.premium))
                        Spacer()
                    }
                    .padding(.bottom, 8)
                }
                HStack(alignment: .center, spacing: Theme.Spacing.md) {
                    selectionRing(selected: selected)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(product.displayName)
                            .font(Theme.Font.headline)
                            .foregroundStyle(Theme.Color.primaryText)
                        Text(product.description)
                            .font(Theme.Font.caption)
                            .foregroundStyle(Theme.Color.secondaryText)
                            .lineLimit(2)
                    }
                    Spacer()
                    Text(product.displayPrice)
                        .font(Theme.Font.numericMedium)
                        .foregroundStyle(Theme.Color.primaryText)
                }
            }
            .padding(Theme.Spacing.lg)
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous)
                        .fill(.ultraThinMaterial)
                    RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous)
                        .fill(Theme.Gradient.surfaceSheen)
                    if selected {
                        RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous)
                            .fill(Theme.Color.accent.opacity(0.10))
                    }
                }
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous)
                    .stroke(selected ? Theme.Color.accent : Color.white.opacity(0.06),
                            lineWidth: selected ? 1.5 : 1)
            )
        }
        .buttonStyle(ScalePressStyle(scale: 0.98))
    }

    private func selectionRing(selected: Bool) -> some View {
        ZStack {
            Circle().stroke(
                selected ? Theme.Color.accent : Color.white.opacity(0.30),
                lineWidth: 2
            )
            if selected {
                Circle().fill(Theme.Color.accent).padding(5)
            }
        }
        .frame(width: 22, height: 22)
    }

    // MARK: Actions

    private var actionButtons: some View {
        VStack(spacing: Theme.Spacing.md) {
            PrimaryButton(
                title: subscribeButtonTitle,
                systemImage: nil,
                isLoading: isPurchasing,
                isDisabled: selectedProductId == nil
            ) {
                Task { await purchase() }
            }
            Button {
                Task { try? await subscriptions.restorePurchases() }
            } label: {
                Text("Restore purchases")
                    .font(Theme.Font.callout.weight(.medium))
                    .foregroundStyle(Theme.Color.secondaryText)
            }
            if let errorMessage {
                Text(errorMessage)
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.Color.danger)
                    .multilineTextAlignment(.center)
            }
        }
    }

    private var subscribeButtonTitle: String {
        guard let id = selectedProductId,
              let product = subscriptions.products.first(where: { $0.id == id }) else {
            return "Continue"
        }
        if let intro = product.subscription?.introductoryOffer, intro.paymentMode == .freeTrial {
            return "Start free trial"
        }
        return "Subscribe \(product.displayPrice)"
    }

    private var legalRow: some View {
        VStack(spacing: Theme.Spacing.xs) {
            Text("Subscriptions auto-renew until cancelled. Cancel anytime in Settings → Apple ID → Subscriptions.")
                .font(Theme.Font.caption)
                .foregroundStyle(Theme.Color.tertiaryText)
                .multilineTextAlignment(.center)
            HStack(spacing: Theme.Spacing.md) {
                Link("Terms", destination: URL(string: "https://lastseen.app/terms")!)
                Link("Privacy", destination: URL(string: "https://lastseen.app/privacy")!)
            }
            .font(Theme.Font.caption.weight(.medium))
            .foregroundStyle(Theme.Color.secondaryText)
        }
    }

    private func purchase() async {
        guard let id = selectedProductId,
              let product = subscriptions.products.first(where: { $0.id == id }) else { return }
        errorMessage = nil
        isPurchasing = true
        defer { isPurchasing = false }
        do {
            let result = try await subscriptions.purchase(product)
            if case .success = result {
                dismiss()
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
