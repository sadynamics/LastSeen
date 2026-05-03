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
            Theme.Color.background.ignoresSafeArea()
            ScrollView {
                VStack(spacing: Theme.Spacing.xl) {
                    header
                    benefits
                    plans
                    actionButtons
                    legalRow
                }
                .padding(Theme.Spacing.lg)
            }
        }
        .overlay(alignment: .topTrailing) {
            Button { dismiss() } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title2)
                    .foregroundStyle(Theme.Color.tertiaryText)
            }
            .padding(Theme.Spacing.lg)
        }
        .task {
            if subscriptions.products.isEmpty {
                await subscriptions.loadProducts()
            }
            // Pre-select monthly (typically the higher-LTV plan).
            if selectedProductId == nil {
                selectedProductId = subscriptions.products
                    .first(where: { $0.id == AppConfig.Subscription.monthlyProductId })?.id
                    ?? subscriptions.products.first?.id
            }
        }
    }

    private var header: some View {
        VStack(spacing: Theme.Spacing.md) {
            Image(systemName: "sparkles")
                .font(.system(size: 56))
                .foregroundStyle(Theme.Color.accent)
            Text("Track unlimited numbers")
                .font(.title.bold())
                .foregroundStyle(Theme.Color.primaryText)
                .multilineTextAlignment(.center)
            Text("Unlock unlimited tracked numbers, real-time alerts, and weekly reports.")
                .font(.callout)
                .foregroundStyle(Theme.Color.secondaryText)
                .multilineTextAlignment(.center)
        }
        .padding(.top, Theme.Spacing.lg)
    }

    private var benefits: some View {
        Card {
            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                benefit("Track unlimited WhatsApp numbers", "infinity")
                benefit("Real-time online & offline alerts", "bell.badge.fill")
                benefit("Daily and weekly reports", "chart.xyaxis.line")
                benefit("Peak-hour heatmap", "flame.fill")
                benefit("Cancel anytime", "checkmark.shield.fill")
            }
        }
    }

    private func benefit(_ text: String, _ icon: String) -> some View {
        HStack(alignment: .center, spacing: Theme.Spacing.md) {
            Image(systemName: icon)
                .foregroundStyle(Theme.Color.accent)
                .frame(width: 24)
            Text(text)
                .foregroundStyle(Theme.Color.primaryText)
                .font(.callout)
        }
    }

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
            selectedProductId = product.id
        } label: {
            HStack(alignment: .center, spacing: Theme.Spacing.md) {
                ZStack {
                    Circle().stroke(
                        selected ? Theme.Color.accent : Theme.Color.tertiaryText.opacity(0.5),
                        lineWidth: 2
                    )
                    if selected {
                        Circle().fill(Theme.Color.accent)
                            .padding(4)
                    }
                }
                .frame(width: 22, height: 22)
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text(product.displayName)
                            .font(.headline)
                            .foregroundStyle(Theme.Color.primaryText)
                        if isMonthly {
                            Text("BEST VALUE")
                                .font(.caption2.bold())
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(Theme.Color.online.opacity(0.2)))
                                .foregroundStyle(Theme.Color.online)
                        }
                    }
                    Text(product.description)
                        .font(.caption)
                        .foregroundStyle(Theme.Color.secondaryText)
                }
                Spacer()
                Text(product.displayPrice)
                    .font(.headline)
                    .foregroundStyle(Theme.Color.primaryText)
            }
            .padding(Theme.Spacing.lg)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.md)
                    .fill(Theme.Color.surface)
                    .overlay(
                        RoundedRectangle(cornerRadius: Theme.Radius.md)
                            .stroke(selected ? Theme.Color.accent : .clear, lineWidth: 2)
                    )
            )
        }
        .buttonStyle(.plain)
    }

    private var actionButtons: some View {
        VStack(spacing: Theme.Spacing.md) {
            PrimaryButton(
                title: subscribeButtonTitle,
                isLoading: isPurchasing,
                isDisabled: selectedProductId == nil
            ) {
                Task { await purchase() }
            }
            Button {
                Task { try? await subscriptions.restorePurchases() }
            } label: {
                Text("Restore purchases")
                    .font(.callout)
                    .foregroundStyle(Theme.Color.secondaryText)
            }
            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
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
                .font(.caption2)
                .foregroundStyle(Theme.Color.tertiaryText)
                .multilineTextAlignment(.center)
            HStack(spacing: Theme.Spacing.md) {
                Link("Terms", destination: URL(string: "https://lastseen.app/terms")!)
                Link("Privacy", destination: URL(string: "https://lastseen.app/privacy")!)
            }
            .font(.caption2)
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
