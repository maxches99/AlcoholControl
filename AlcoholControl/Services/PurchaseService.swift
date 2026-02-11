import Foundation
import Combine
import StoreKit

@MainActor
final class PurchaseService: ObservableObject {
    static let shared = PurchaseService()
    private let monthlyID = "com.alcoholcontrol.premium.monthly"
    private let yearlyID = "com.alcoholcontrol.premium.yearly"
    @Published var isPremium = false
    @Published var products: [Product] = []
    @Published var isLoadingProducts = false
    @Published var selectedProductID = "com.alcoholcontrol.premium.monthly"

    private var transactionUpdatesTask: Task<Void, Never>?

    private init() {
        observeTransactionUpdates()
    }

    private var productIDs: [String] {
        [monthlyID, yearlyID]
    }

    var sortedProducts: [Product] {
        products.sorted { lhs, rhs in
            order(for: lhs.id) < order(for: rhs.id)
        }
    }

    func loadProducts() async {
        isLoadingProducts = true
        defer { isLoadingProducts = false }
        do {
            products = try await Product.products(for: productIDs)
            if sortedProducts.first(where: { $0.id == selectedProductID }) == nil,
               let fallback = sortedProducts.first {
                selectedProductID = fallback.id
            }
        } catch {
            products = []
        }
    }

    func purchaseSelected() async -> Bool {
        guard let product = sortedProducts.first(where: { $0.id == selectedProductID }) ?? sortedProducts.first else {
            return false
        }
        return await purchase(product: product)
    }

    func purchase() async -> Bool {
        await purchaseSelected()
    }

    private func purchase(product: Product) async -> Bool {
        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                switch verification {
                case .verified(let transaction):
                    await transaction.finish()
                    await refreshPremiumStatus()
                    return isPremium
                case .unverified:
                    return false
                }
            case .userCancelled, .pending:
                return false
            @unknown default:
                return false
            }
        } catch {
            return false
        }
    }

    @discardableResult
    func restore() async -> Bool {
        await refreshPremiumStatus()
        return isPremium
    }

    @discardableResult
    func restoreFromAppStore() async -> Bool {
        do {
            try await AppStore.sync()
        } catch {
            // Even if sync fails (e.g. no network), still recalculate local entitlements.
        }
        await refreshPremiumStatus()
        return isPremium
    }

    private func order(for productID: String) -> Int {
        switch productID {
        case monthlyID:
            return 0
        case yearlyID:
            return 1
        default:
            return 2
        }
    }

    private func observeTransactionUpdates() {
        transactionUpdatesTask?.cancel()
        transactionUpdatesTask = Task { [weak self] in
            guard let self else { return }
            for await result in Transaction.updates {
                if case .verified(let transaction) = result {
                    await transaction.finish()
                }
                await self.refreshPremiumStatus()
            }
        }
    }

    private func refreshPremiumStatus() async {
        var hasPremium = false
        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result else { continue }
            guard productIDs.contains(transaction.productID) else { continue }
            guard transaction.revocationDate == nil else { continue }
            if let expirationDate = transaction.expirationDate, expirationDate < Date() {
                continue
            }
            hasPremium = true
            break
        }
        isPremium = hasPremium
    }
}
