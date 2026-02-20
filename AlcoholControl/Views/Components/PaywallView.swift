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
            ScrollView {
                VStack(alignment: .leading, spacing: AppDesign.Spacing.md) {
                    VStack(alignment: .leading, spacing: AppDesign.Spacing.sm) {
                        Text(L10n.tr("Premium поддержка"))
                            .font(.system(.largeTitle, design: .rounded).weight(.bold))
                            .foregroundStyle(AppDesign.Colors.primaryText)
                        Text(paywallVariant == "B" ? L10n.tr("Контроль вечера + лучшее утро") : L10n.tr("Персональная аналитика и прогноз"))
                            .font(.headline)
                            .foregroundStyle(AppDesign.Colors.secondaryText)
                    }
                    .appCard()

                    if purchase.sortedProducts.isEmpty {
                        Text(L10n.tr("$4.99/мес"))
                            .font(.title2.weight(.semibold))
                            .foregroundStyle(AppDesign.Colors.primaryText)
                            .appCard()
                    } else {
                        VStack(alignment: .leading, spacing: AppDesign.Spacing.sm) {
                            Text(L10n.tr("Выберите план"))
                                .font(.headline)
                                .foregroundStyle(AppDesign.Colors.primaryText)
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
                                                .foregroundStyle(AppDesign.Colors.secondaryText)
                                            if let intro = product.subscription?.introductoryOffer {
                                                Text(L10n.format("Пробный период: %@", intro.period.debugDescription))
                                                    .font(.caption2)
                                                    .foregroundStyle(AppDesign.Colors.secondaryText)
                                            }
                                        }
                                        Spacer()
                                        Image(systemName: purchase.selectedProductID == product.id ? "checkmark.circle.fill" : "circle")
                                            .foregroundStyle(purchase.selectedProductID == product.id ? AppDesign.Colors.success : AppDesign.Colors.secondaryText)
                                    }
                                    .padding(10)
                                    .background(
                                        RoundedRectangle(cornerRadius: AppDesign.Radius.sm, style: .continuous)
                                            .fill(AppDesign.Colors.background)
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .appCard()
                    }

                    VStack(alignment: .leading, spacing: AppDesign.Spacing.sm) {
                        Label(L10n.tr("Расширенная аналитика BAC и воды"), systemImage: "chart.line.uptrend.xyaxis")
                        Label(L10n.tr("История паттернов и трендов"), systemImage: "clock.arrow.circlepath")
                        Label(L10n.tr("Персональные цели вечера и динамика риска"), systemImage: "target")
                        Label(L10n.tr("Отмена в любой момент"), systemImage: "checkmark.circle")
                    }
                    .foregroundStyle(AppDesign.Colors.primaryText)
                    .appCard()

                    Button(isLoading ? L10n.tr("Оформление...") : L10n.tr("Continue/Subscribe")) {
                        Task { await subscribe() }
                    }
                    .buttonStyle(AppPrimaryButtonStyle())
                    .disabled(isLoading)

                    Button(L10n.tr("Restore purchases")) {
                        Task { await restore() }
                    }
                    .buttonStyle(AppSecondaryButtonStyle())

                    HStack {
                        Link(L10n.tr("Terms"), destination: URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!)
                        Spacer()
                        Link(L10n.tr("Privacy"), destination: URL(string: "https://www.termsfeed.com/live/3f4f77e2-9d7c-4ece-b68d-cac5dc5c2ec8")!)
                    }
                    .font(.footnote)
                    .foregroundStyle(AppDesign.Colors.secondaryText)
                    .padding(.horizontal, AppDesign.Spacing.xs)

                    if !statusMessage.isEmpty {
                        Text(statusMessage)
                            .font(.footnote)
                            .foregroundStyle(AppDesign.Colors.secondaryText)
                            .padding(.horizontal, AppDesign.Spacing.xs)
                    }
                }
                .padding(AppDesign.Spacing.md)
            }
            .appScreenBackground()
            .navigationTitle(L10n.tr("Paywall"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.tr("Закрыть")) { dismiss() }
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
        await purchase.restoreFromAppStore()
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
            return L10n.tr("Месяц")
        case "com.alcoholcontrol.premium.yearly":
            return L10n.tr("Год")
        default:
            return L10n.tr("План")
        }
    }
}
