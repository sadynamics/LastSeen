//
//  SubscriptionService.swift
//  StoreKit 2 wrapper. Handles fetching products, purchase, transaction
//  listening, and forwarding signed transactions to the backend for
//  server-side verification + entitlement.
//

import Foundation
import Observation
import StoreKit

@MainActor
@Observable
final class SubscriptionService {
    enum PurchaseResult: Sendable {
        case success
        case userCancelled
        case pending
    }

    private(set) var products: [Product] = []
    private(set) var isSubscribed: Bool = false
    private(set) var activeProductId: String?
    private(set) var expiresAt: Date?
    private(set) var isLoading: Bool = false
    private(set) var lastError: String?

    private let api: APIClient
    private var transactionListener: Task<Void, Never>?

    init(api: APIClient) {
        self.api = api
    }

    func start() async {
        await loadProducts()
        await refreshFromBackend()
        await syncCurrentEntitlements()
        startTransactionListener()
    }

    func loadProducts() async {
        isLoading = true
        defer { isLoading = false }
        do {
            products = try await Product.products(for: AppConfig.Subscription.allIds)
                .sorted { $0.price < $1.price }
        } catch {
            lastError = error.localizedDescription
        }
    }

    func refreshFromBackend() async {
        do {
            let status: BillingStatus = try await api.get("/v1/billing/status")
            isSubscribed = status.isSubscribed
            activeProductId = status.subscription?.productId
            expiresAt = status.subscription?.expiresAt
            LSAnalytics.shared.setSubscriptionStatus(isSubscribed, productId: activeProductId)
        } catch APIError.unauthorized {
            // The auth flow will handle this; just clear local state.
            isSubscribed = false
            activeProductId = nil
            expiresAt = nil
            LSAnalytics.shared.setSubscriptionStatus(false, productId: nil)
        } catch {
            lastError = error.localizedDescription
            LSAnalytics.shared.logError(error, context: ["operation": "billing_status"])
        }
    }

    func purchase(_ product: Product) async throws -> PurchaseResult {
        let currency = product.priceFormatStyle.currencyCode
        LSAnalytics.shared.log(.purchaseStarted(productId: product.id,
                                                price: product.price,
                                                currency: currency))
        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                switch verification {
                case .verified(let transaction):
                    try await sendToBackend(verification.jwsRepresentation)
                    await transaction.finish()
                    isSubscribed = true
                    activeProductId = transaction.productID
                    expiresAt = transaction.expirationDate
                    LSAnalytics.shared.setSubscriptionStatus(true, productId: transaction.productID)
                    LSAnalytics.shared.log(.purchaseSucceeded(productId: product.id,
                                                              price: product.price,
                                                              currency: currency))
                    return .success
                case .unverified(_, let error):
                    LSAnalytics.shared.log(.purchaseFailed(productId: product.id,
                                                           reason: "unverified"))
                    LSAnalytics.shared.logError(error, context: ["operation": "purchase_verify",
                                                                  "product_id": product.id])
                    throw error
                }
            case .userCancelled:
                LSAnalytics.shared.log(.purchaseCancelled(productId: product.id))
                return .userCancelled
            case .pending:
                LSAnalytics.shared.log(.purchasePending(productId: product.id))
                return .pending
            @unknown default:
                return .pending
            }
        } catch {
            LSAnalytics.shared.log(.purchaseFailed(productId: product.id,
                                                   reason: String(describing: type(of: error))))
            LSAnalytics.shared.logError(error, context: ["operation": "purchase",
                                                          "product_id": product.id])
            throw error
        }
    }

    func restorePurchases() async throws {
        LSAnalytics.shared.log(.restorePurchasesTapped)
        do {
            try await AppStore.sync()
            await syncCurrentEntitlements()
            await refreshFromBackend()
            LSAnalytics.shared.log(.restorePurchasesSucceeded)
        } catch {
            LSAnalytics.shared.log(.restorePurchasesFailed(reason: String(describing: type(of: error))))
            LSAnalytics.shared.logError(error, context: ["operation": "restore_purchases"])
            throw error
        }
    }

    // MARK: - Internals

    private func startTransactionListener() {
        transactionListener?.cancel()
        transactionListener = Task { [weak self] in
            for await update in Transaction.updates {
                guard let self else { return }
                if case .verified(let transaction) = update {
                    try? await self.sendToBackend(update.jwsRepresentation)
                    await transaction.finish()
                    self.isSubscribed = transaction.revocationDate == nil
                        && (transaction.expirationDate ?? .distantPast) > .now
                    self.activeProductId = transaction.productID
                    self.expiresAt = transaction.expirationDate
                }
            }
        }
    }

    private func syncCurrentEntitlements() async {
        var seenActive = false
        for await result in Transaction.currentEntitlements {
            if case .verified(let transaction) = result {
                if let exp = transaction.expirationDate, exp > .now, transaction.revocationDate == nil {
                    seenActive = true
                    activeProductId = transaction.productID
                    expiresAt = exp
                    try? await sendToBackend(result.jwsRepresentation)
                }
            }
        }
        isSubscribed = seenActive
    }

    private func sendToBackend(_ jws: String) async throws {
        let body = BillingVerifyRequest(signedTransaction: jws)
        _ = try await api.post("/v1/billing/verify", body: body, as: BillingVerifyResponse.self)
    }
}
