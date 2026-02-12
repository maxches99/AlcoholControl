import SwiftUI
import Combine

private func watchTr(_ key: String) -> String {
    NSLocalizedString(key, comment: "")
}

private func watchFmt(_ key: String, _ args: CVarArg...) -> String {
    String(format: watchTr(key), locale: .autoupdatingCurrent, arguments: args)
}

private enum WatchKeys {
    static let appGroupID = "group.maxches.AlcoholControl"
    static let isActive = "widget.isActive"
    static let bac = "widget.currentBAC"
    static let soberAt = "widget.soberAt"
    static let waterConsumed = "widget.waterConsumedMl"
    static let waterTarget = "widget.waterTargetMl"
    static let risk = "widget.morningRisk"
    static let recoveryScore = "widget.recoveryScore"
    static let recoveryLevel = "widget.recoveryLevel"
    static let updatedAt = "widget.updatedAt"
    static let pendingWaterMl = "watch.pendingWaterMl"
    static let pendingDrinkVolume = "watch.pendingDrink.volumeMl"
    static let pendingDrinkABV = "watch.pendingDrink.abv"
    static let pendingDrinkTitle = "watch.pendingDrink.title"
    static let pendingDrinkCategory = "watch.pendingDrink.category"
    static let pendingMealSize = "watch.pendingMeal.size"
    static let pendingEndSession = "watch.pendingEndSession"
    static let pendingStartSession = "watch.pendingStartSession"
    static let pendingSafetyCheck = "watch.pendingSafetyCheck"
    static let pendingPauseMinutes = "watch.pendingPauseMinutes"
}

struct WatchSnapshot {
    var isActive: Bool = false
    var currentBAC: Double = 0
    var soberAt: Date? = nil
    var waterConsumedMl: Int = 0
    var waterTargetMl: Int = 1000
    var risk: String = "low"
    var recoveryScore: Int = 80
    var recoveryLevel: String = "low"
    var updatedAt: Date = .now
}

@MainActor
final class WatchSnapshotStore: ObservableObject {
    @Published var snapshot = WatchSnapshot()
    @Published var statusMessage = ""

    private let defaults = UserDefaults(suiteName: WatchKeys.appGroupID)

    func refresh() {
        guard let defaults else { return }

        let timestamp = defaults.double(forKey: WatchKeys.updatedAt)
        let updatedAt = timestamp > 0 ? Date(timeIntervalSince1970: timestamp) : .now
        let soberTimestamp = defaults.double(forKey: WatchKeys.soberAt)

        snapshot = WatchSnapshot(
            isActive: defaults.bool(forKey: WatchKeys.isActive),
            currentBAC: defaults.double(forKey: WatchKeys.bac),
            soberAt: soberTimestamp > 0 ? Date(timeIntervalSince1970: soberTimestamp) : nil,
            waterConsumedMl: defaults.integer(forKey: WatchKeys.waterConsumed),
            waterTargetMl: max(1, defaults.integer(forKey: WatchKeys.waterTarget)),
            risk: defaults.string(forKey: WatchKeys.risk) ?? "low",
            recoveryScore: defaults.integer(forKey: WatchKeys.recoveryScore),
            recoveryLevel: defaults.string(forKey: WatchKeys.recoveryLevel) ?? "low",
            updatedAt: updatedAt
        )

        statusMessage = "Обновлено: \(updatedAt.formatted(date: .omitted, time: .shortened))"
    }

    func addWaterQuick(volumeMl: Int = 250) {
        guard let defaults else { return }
        let current = defaults.integer(forKey: WatchKeys.pendingWaterMl)
        defaults.set(current + volumeMl, forKey: WatchKeys.pendingWaterMl)
        defaults.set(Date.now.timeIntervalSince1970, forKey: WatchKeys.updatedAt)

        snapshot.waterConsumedMl += volumeMl
        statusMessage = "Отправили +\(volumeMl) мл на iPhone"
    }

    func addDrinkQuick(volumeMl: Double, abv: Double, title: String, category: String) {
        guard let defaults else { return }
        defaults.set(volumeMl, forKey: WatchKeys.pendingDrinkVolume)
        defaults.set(abv, forKey: WatchKeys.pendingDrinkABV)
        defaults.set(title, forKey: WatchKeys.pendingDrinkTitle)
        defaults.set(category, forKey: WatchKeys.pendingDrinkCategory)
        defaults.set(Date.now.timeIntervalSince1970, forKey: WatchKeys.updatedAt)
        statusMessage = "Отправили \(title) на iPhone"
    }

    func requestEndSession() {
        guard let defaults else { return }
        defaults.set(true, forKey: WatchKeys.pendingEndSession)
        defaults.set(Date.now.timeIntervalSince1970, forKey: WatchKeys.updatedAt)
        statusMessage = "Запросили завершение на iPhone"
    }

    func requestStartSession() {
        guard let defaults else { return }
        defaults.set(true, forKey: WatchKeys.pendingStartSession)
        defaults.set(Date.now.timeIntervalSince1970, forKey: WatchKeys.updatedAt)
        statusMessage = "Запросили старт сессии на iPhone"
    }

    func addQuickMeal() {
        guard let defaults else { return }
        defaults.set("snack", forKey: WatchKeys.pendingMealSize)
        defaults.set(Date.now.timeIntervalSince1970, forKey: WatchKeys.updatedAt)
        statusMessage = "Отправили перекус на iPhone"
    }

    func requestSafetyCheck() {
        guard let defaults else { return }
        defaults.set(true, forKey: WatchKeys.pendingSafetyCheck)
        defaults.set(Date.now.timeIntervalSince1970, forKey: WatchKeys.updatedAt)
        statusMessage = watchTr("Запросили центр безопасности на iPhone")
    }

    func requestPause(minutes: Int = 25) {
        guard let defaults else { return }
        defaults.set(minutes, forKey: WatchKeys.pendingPauseMinutes)
        defaults.set(Date.now.timeIntervalSince1970, forKey: WatchKeys.updatedAt)
        statusMessage = "Пауза \(minutes) мин отправлена на iPhone"
    }
}

struct WatchDashboardView: View {
    @EnvironmentObject private var store: WatchSnapshotStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(watchTr("Alcohol Control"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Circle()
                        .fill(store.snapshot.isActive ? Color.green : Color.gray)
                        .frame(width: 8, height: 8)
                }

                if store.snapshot.isActive {
                    Text(watchFmt("BAC %.3f", store.snapshot.currentBAC))
                        .font(.headline)

                    Text(soberText(store.snapshot.soberAt))
                        .font(.caption2)
                        .foregroundStyle(.secondary)

                    VStack(alignment: .leading, spacing: 4) {
                        ProgressView(value: waterProgress)
                        Text("H2O \(store.snapshot.waterConsumedMl)/\(store.snapshot.waterTargetMl) мл")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }

                    Text("Риск утра: \(store.snapshot.risk)")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(riskColor(store.snapshot.risk))

                    Text(watchFmt("Recovery %d/100", store.snapshot.recoveryScore))
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(recoveryColor(store.snapshot.recoveryLevel))
                } else {
                    Text("Сессия не активна")
                        .font(.headline)
                    Text("Запустите вечер в iPhone приложении.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 8) {
                    Button("Обновить") {
                        store.refresh()
                    }
                    .buttonStyle(.bordered)

                    Button("Вода +250") {
                        store.addWaterQuick()
                    }
                    .buttonStyle(.borderedProminent)
                }

                if store.snapshot.isActive {
                    HStack(spacing: 8) {
                        Button("Пиво 330") {
                            store.addDrinkQuick(volumeMl: 330, abv: 5, title: watchTr("Пиво"), category: "beer")
                        }
                        .buttonStyle(.bordered)

                        Button("Вино 150") {
                            store.addDrinkQuick(volumeMl: 150, abv: 12, title: watchTr("Вино"), category: "wine")
                        }
                        .buttonStyle(.bordered)
                    }

                    Button("Коктейль") {
                        store.addDrinkQuick(volumeMl: 180, abv: 18, title: watchTr("Коктейль"), category: "cocktail")
                    }
                    .buttonStyle(.bordered)

                    HStack(spacing: 8) {
                        Button("+ Перекус") {
                            store.addQuickMeal()
                        }
                        .buttonStyle(.bordered)

                        Button("Нужна помощь") {
                            store.requestSafetyCheck()
                        }
                        .buttonStyle(.bordered)
                        .tint(.red)
                    }

                    Button("Пауза 25 мин") {
                        store.requestPause()
                    }
                    .buttonStyle(.bordered)
                    .tint(.purple)

                    Button("Стоп сессии") {
                        store.requestEndSession()
                    }
                    .buttonStyle(.bordered)
                    .tint(.orange)
                } else {
                    Button("Старт сессии") {
                        store.requestStartSession()
                    }
                    .buttonStyle(.borderedProminent)
                }

                if !store.statusMessage.isEmpty {
                    Text(store.statusMessage)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
        }
    }

    private var waterProgress: Double {
        min(1, Double(store.snapshot.waterConsumedMl) / Double(max(1, store.snapshot.waterTargetMl)))
    }

    private func soberText(_ target: Date?) -> String {
        guard let target else { return watchTr("До 0.00: сейчас") }
        let interval = target.timeIntervalSince(.now)
        if interval <= 0 { return watchTr("До 0.00: сейчас") }

        let minutes = Int(interval / 60)
        let hours = minutes / 60
        let rest = minutes % 60

        if hours > 0 {
            return watchFmt("До 0.00 ~%dч %dм", hours, rest)
        }
        return watchFmt("До 0.00 ~%dм", rest)
    }

    private func riskColor(_ risk: String) -> Color {
        switch risk {
        case "high":
            return .red
        case "medium":
            return .orange
        default:
            return .green
        }
    }

    private func recoveryColor(_ level: String) -> Color {
        switch level {
        case "high":
            return .red
        case "medium":
            return .orange
        default:
            return .green
        }
    }
}
