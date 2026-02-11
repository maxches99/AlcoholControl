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

    private init() {}

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
                    isPremium = true
                    return true
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

    func restore() async {
        var hasPremium = false
        for await result in Transaction.currentEntitlements {
            if case .verified(let transaction) = result, productIDs.contains(transaction.productID) {
                hasPremium = true
            }
        }
        isPremium = hasPremium
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
}
