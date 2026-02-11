import SwiftUI
import StoreKit

struct PaywallView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var purchase = PurchaseService.shared
    @AppStorage("paywallVariant") private var paywallVariant = ""

    @State private var isLoading = false
    @State private var statusMessage = ""

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 20) {
                Text("Premium")
                    .font(.largeTitle.bold())
                Text(paywallVariant == "B" ? "Контроль вечера + лучшее утро" : "Персональная аналитика и прогноз")
                    .font(.headline)
                    .foregroundStyle(.secondary)

                if purchase.sortedProducts.isEmpty {
                    Text("$4.99/мес")
                        .font(.title2)
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Выберите план")
                            .font(.headline)
                        ForEach(purchase.sortedProducts, id: \.id) { product in
                            Button {
                                purchase.selectedProductID = product.id
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(planTitle(for: product.id))
                                            .font(.subheadline.weight(.semibold))
                                        Text(product.displayPrice)
                                            .font(.footnote)
                                            .foregroundStyle(.secondary)
                                        if let intro = product.subscription?.introductoryOffer {
                                            Text("Пробный период: \(intro.period.debugDescription)")
                                                .font(.caption2)
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                    Spacer()
                                    Image(systemName: purchase.selectedProductID == product.id ? "checkmark.circle.fill" : "circle")
                                        .foregroundStyle(purchase.selectedProductID == product.id ? .green : .secondary)
                                }
                                .padding(10)
                                .background(Color(uiColor: .secondarySystemGroupedBackground))
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 10) {
                    Label("Расширенная аналитика BAC и воды", systemImage: "chart.line.uptrend.xyaxis")
                    Label("История паттернов и трендов", systemImage: "clock.arrow.circlepath")
                    Label("Персональные цели вечера и динамика риска", systemImage: "target")
                    Label("Отмена в любой момент", systemImage: "checkmark.circle")
                }

                Button(isLoading ? "Оформление..." : "Continue/Subscribe") {
                    Task { await subscribe() }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isLoading)

                Button("Restore purchases") {
                    Task { await restore() }
                }
                .buttonStyle(.bordered)

                HStack {
                    Link("Terms", destination: URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!)
                    Spacer()
                    Link("Privacy", destination: URL(string: "https://www.termsfeed.com/live/3f4f77e2-9d7c-4ece-b68d-cac5dc5c2ec8")!)
                }
                .font(.footnote)

                if !statusMessage.isEmpty {
                    Text(statusMessage)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }
            .padding()
            .navigationTitle("Paywall")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Закрыть") { dismiss() }
                }
            }
            .task {
                if paywallVariant.isEmpty {
                    paywallVariant = Bool.random() ? "A" : "B"
                }
                await purchase.loadProducts()
                await purchase.restore()
            }
        }
    }

    private func subscribe() async {
        isLoading = true
        defer { isLoading = false }

        let success = await purchase.purchaseSelected()
        if success {
            statusMessage = L10n.tr("Подписка активирована")
            dismiss()
        } else {
            statusMessage = L10n.tr("Покупка отменена или не завершена")
        }
    }

    private func restore() async {
        await purchase.restore()
        if purchase.isPremium {
            statusMessage = L10n.tr("Покупки восстановлены")
            dismiss()
        } else {
            statusMessage = L10n.tr("Активных покупок не найдено")
        }
    }

    private func planTitle(for productID: String) -> String {
        switch productID {
        case "com.alcoholcontrol.premium.monthly":
            return "Месяц"
        case "com.alcoholcontrol.premium.yearly":
            return "Год"
        default:
            return "План"
        }
    }
}
