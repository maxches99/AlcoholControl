import Foundation

#if canImport(WidgetKit)
import WidgetKit
#endif

@MainActor
enum WidgetSnapshotStore {
    static let appGroupID = "group.maxches.AlcoholControl"

    private enum Key {
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
        static let pendingSafetyCheck = "watch.pendingSafetyCheck"
        static let pendingPauseMinutes = "watch.pendingPauseMinutes"
    }

    static func update(
        isActive: Bool,
        currentBAC: Double,
        soberAt: Date?,
        waterConsumedMl: Int,
        waterTargetMl: Int,
        morningRisk: InsightLevel,
        recoveryScore: Int,
        recoveryLevel: InsightLevel
    ) {
        guard let defaults = UserDefaults(suiteName: appGroupID) else { return }

        defaults.set(isActive, forKey: Key.isActive)
        defaults.set(max(0, currentBAC), forKey: Key.bac)
        defaults.set(soberAt?.timeIntervalSince1970 ?? 0, forKey: Key.soberAt)
        defaults.set(max(0, waterConsumedMl), forKey: Key.waterConsumed)
        defaults.set(max(1, waterTargetMl), forKey: Key.waterTarget)
        defaults.set(morningRisk.rawValue, forKey: Key.risk)
        let boundedRecoveryScore = min(100, max(0, recoveryScore))
        defaults.set(boundedRecoveryScore, forKey: Key.recoveryScore)
        defaults.set(recoveryLevel.rawValue, forKey: Key.recoveryLevel)
        defaults.set(Date.now.timeIntervalSince1970, forKey: Key.updatedAt)

        #if canImport(WidgetKit)
        WidgetCenter.shared.reloadAllTimelines()
        #endif
    }

    static func clear() {
        guard let defaults = UserDefaults(suiteName: appGroupID) else { return }
        defaults.set(false, forKey: Key.isActive)
        defaults.set(0, forKey: Key.bac)
        defaults.set(0, forKey: Key.soberAt)
        defaults.set(0, forKey: Key.waterConsumed)
        defaults.set(1000, forKey: Key.waterTarget)
        defaults.set(InsightLevel.low.rawValue, forKey: Key.risk)
        defaults.set(80, forKey: Key.recoveryScore)
        defaults.set(InsightLevel.low.rawValue, forKey: Key.recoveryLevel)
        defaults.set(Date.now.timeIntervalSince1970, forKey: Key.updatedAt)

        #if canImport(WidgetKit)
        WidgetCenter.shared.reloadAllTimelines()
        #endif
    }

    static func pendingWaterMl() -> Int {
        guard let defaults = UserDefaults(suiteName: appGroupID) else { return 0 }
        return max(0, defaults.integer(forKey: Key.pendingWaterMl))
    }

    static func enqueuePendingWater(volumeMl: Int = 250) {
        guard let defaults = UserDefaults(suiteName: appGroupID) else { return }
        let current = defaults.integer(forKey: Key.pendingWaterMl)
        defaults.set(current + max(1, volumeMl), forKey: Key.pendingWaterMl)
        defaults.set(Date.now.timeIntervalSince1970, forKey: Key.updatedAt)
    }

    static func consumePendingWaterMl() -> Int {
        guard let defaults = UserDefaults(suiteName: appGroupID) else { return 0 }
        let value = max(0, defaults.integer(forKey: Key.pendingWaterMl))
        if value > 0 {
            defaults.set(0, forKey: Key.pendingWaterMl)
        }
        return value
    }

    static func enqueuePendingDrink(
        volumeMl: Double,
        abvPercent: Double,
        title: String,
        category: DrinkEntry.Category
    ) {
        guard let defaults = UserDefaults(suiteName: appGroupID) else { return }
        defaults.set(max(1, volumeMl), forKey: Key.pendingDrinkVolume)
        defaults.set(max(0.1, abvPercent), forKey: Key.pendingDrinkABV)
        defaults.set(title, forKey: Key.pendingDrinkTitle)
        defaults.set(category.rawValue, forKey: Key.pendingDrinkCategory)
        defaults.set(Date.now.timeIntervalSince1970, forKey: Key.updatedAt)
    }

    static func consumePendingDrink() -> (volumeMl: Double, abvPercent: Double, title: String, category: DrinkEntry.Category)? {
        guard let defaults = UserDefaults(suiteName: appGroupID) else { return nil }
        let volume = defaults.double(forKey: Key.pendingDrinkVolume)
        let abv = defaults.double(forKey: Key.pendingDrinkABV)
        guard volume > 0, abv > 0 else { return nil }

        let title = defaults.string(forKey: Key.pendingDrinkTitle) ?? L10n.tr("Быстрый напиток")
        let rawCategory = defaults.string(forKey: Key.pendingDrinkCategory) ?? DrinkEntry.Category.beer.rawValue
        let category = DrinkEntry.Category(rawValue: rawCategory) ?? .beer

        defaults.set(0, forKey: Key.pendingDrinkVolume)
        defaults.set(0, forKey: Key.pendingDrinkABV)
        defaults.removeObject(forKey: Key.pendingDrinkTitle)
        defaults.removeObject(forKey: Key.pendingDrinkCategory)
        return (volume, abv, title, category)
    }

    static func requestEndSessionFromWatch() {
        guard let defaults = UserDefaults(suiteName: appGroupID) else { return }
        defaults.set(true, forKey: Key.pendingEndSession)
        defaults.set(Date.now.timeIntervalSince1970, forKey: Key.updatedAt)
    }

    static func consumePendingEndSessionRequest() -> Bool {
        guard let defaults = UserDefaults(suiteName: appGroupID) else { return false }
        let requested = defaults.bool(forKey: Key.pendingEndSession)
        if requested {
            defaults.set(false, forKey: Key.pendingEndSession)
        }
        return requested
    }

    static func enqueuePendingMeal(size: MealEntry.MealSize) {
        guard let defaults = UserDefaults(suiteName: appGroupID) else { return }
        defaults.set(size.rawValue, forKey: Key.pendingMealSize)
        defaults.set(Date.now.timeIntervalSince1970, forKey: Key.updatedAt)
    }

    static func consumePendingMealSize() -> MealEntry.MealSize? {
        guard let defaults = UserDefaults(suiteName: appGroupID) else { return nil }
        guard let rawValue = defaults.string(forKey: Key.pendingMealSize) else { return nil }
        defaults.removeObject(forKey: Key.pendingMealSize)
        return MealEntry.MealSize(rawValue: rawValue)
    }

    static func requestSafetyCheckFromWatch() {
        guard let defaults = UserDefaults(suiteName: appGroupID) else { return }
        defaults.set(true, forKey: Key.pendingSafetyCheck)
        defaults.set(Date.now.timeIntervalSince1970, forKey: Key.updatedAt)
    }

    static func consumePendingSafetyCheckRequest() -> Bool {
        guard let defaults = UserDefaults(suiteName: appGroupID) else { return false }
        let requested = defaults.bool(forKey: Key.pendingSafetyCheck)
        if requested {
            defaults.set(false, forKey: Key.pendingSafetyCheck)
        }
        return requested
    }

    static func enqueuePauseRequest(minutes: Int = 25) {
        guard let defaults = UserDefaults(suiteName: appGroupID) else { return }
        defaults.set(minutes, forKey: Key.pendingPauseMinutes)
        defaults.set(Date.now.timeIntervalSince1970, forKey: Key.updatedAt)
    }

    static func consumePendingPauseRequest() -> Int? {
        guard let defaults = UserDefaults(suiteName: appGroupID) else { return nil }
        let value = defaults.integer(forKey: Key.pendingPauseMinutes)
        guard value > 0 else { return nil }
        defaults.set(0, forKey: Key.pendingPauseMinutes)
        return value
    }
}
