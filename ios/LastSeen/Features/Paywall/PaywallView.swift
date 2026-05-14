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
                    .first(where: { $0.id == AppConfig.Subscription.yearlyProductId })?.id
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
                Text("Unlock Premium")
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
        let isYearly = product.id == AppConfig.Subscription.yearlyProductId
        let trial = freeTrialOffer(product)
        let periodLabel = subscriptionPeriodLabel(product)

        return Button {
            if selectedProductId != product.id {
                LSAnalytics.shared.log(.paywallPlanSelected(productId: product.id))
            }
            selectedProductId = product.id
        } label: {
            VStack(alignment: .leading, spacing: 0) {
                if isYearly {
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
                        Text(planSubtitle(for: product))
                            .font(Theme.Font.caption)
                            .foregroundStyle(Theme.Color.secondaryText)
                            .lineLimit(1)
                    }
                    Spacer(minLength: Theme.Spacing.sm)
                    if let trial {
                        trialBadge(trial)
                    } else {
                        Text(product.displayPrice)
                            .font(Theme.Font.numericMedium)
                            .foregroundStyle(Theme.Color.primaryText)
                    }
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

    /// Compact pill on the right of a plan row that calls out the free trial.
    private func trialBadge(_ trial: Product.SubscriptionOffer) -> some View {
        Text("\(offerDurationLabel(trial)) FREE")
            .font(Theme.Font.label)
            .tracking(0.8)
            .foregroundStyle(Theme.Color.online)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Capsule(style: .continuous)
                    .fill(Theme.Color.online.opacity(0.14))
            )
            .overlay(
                Capsule(style: .continuous)
                    .stroke(Theme.Color.online.opacity(0.35), lineWidth: 0.5)
            )
            .fixedSize()
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
        if let trial = freeTrialOffer(product) {
            return "Try free for \(offerDurationLabel(trial))"
        }
        return "Subscribe"
    }

    private var legalRow: some View {
        VStack(spacing: Theme.Spacing.xs) {
            Text("Auto-renews. Cancel anytime.")
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

    // MARK: StoreKit helpers

    /// One-line subtitle under the plan name.
    /// - With trial: "then $X.XX / week"
    /// - Without trial: "per week"
    /// - No subscription metadata: falls back to `product.description`.
    private func planSubtitle(for product: Product) -> String {
        let period = subscriptionPeriodLabel(product)
        if freeTrialOffer(product) != nil {
            if !period.isEmpty {
                return "then \(product.displayPrice) / \(period)"
            }
            return "then \(product.displayPrice)"
        }
        if !period.isEmpty { return "per \(period)" }
        return product.description
    }

    /// The product's introductory offer if and only if it is a free trial.
    private func freeTrialOffer(_ product: Product) -> Product.SubscriptionOffer? {
        guard let intro = product.subscription?.introductoryOffer,
              intro.paymentMode == .freeTrial else { return nil }
        return intro
    }

    /// Human-readable recurring period for a product. Renders just the unit
    /// when value == 1 ("week", "year") and a counted form when value > 1
    /// ("2 weeks"). Empty for non-renewing products.
    private func subscriptionPeriodLabel(_ product: Product) -> String {
        guard let period = product.subscription?.subscriptionPeriod else { return "" }
        let (value, unit) = normalizedPeriod(value: period.value, unit: period.unit)
        let base = baseUnitName(unit)
        if base.isEmpty { return "" }
        if value == 1 { return base }
        return "\(value) \(base)s"
    }

    /// Human-readable total duration of an offer, e.g. "3 days", "1 month".
    /// Always includes the count so "Try free for 1 day" / "3 days" reads
    /// correctly.
    private func offerDurationLabel(_ offer: Product.SubscriptionOffer) -> String {
        let total = offer.period.value * offer.periodCount
        let (value, unit) = normalizedPeriod(value: total, unit: offer.period.unit)
        let base = baseUnitName(unit)
        if base.isEmpty { return "" }
        return "\(value) \(value == 1 ? base : "\(base)s")"
    }

    /// App Store Connect / StoreKit sometimes expresses week, month, or year
    /// periods using smaller units (e.g. a weekly product as `(7, .day)`).
    /// Normalize the obvious equivalents so the UI reads naturally.
    private func normalizedPeriod(value: Int,
                                  unit: Product.SubscriptionPeriod.Unit)
        -> (Int, Product.SubscriptionPeriod.Unit) {
        var v = value
        var u = unit
        if u == .day {
            if v % 365 == 0 { v /= 365; u = .year }
            else if v % 30 == 0 { v /= 30; u = .month }
            else if v % 7 == 0 { v /= 7; u = .week }
        }
        if u == .month && v % 12 == 0 { v /= 12; u = .year }
        return (v, u)
    }

    private func baseUnitName(_ unit: Product.SubscriptionPeriod.Unit) -> String {
        switch unit {
        case .day:   return "day"
        case .week:  return "week"
        case .month: return "month"
        case .year:  return "year"
        @unknown default: return ""
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
