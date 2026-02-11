import Foundation
import UserNotifications

@MainActor
final class NotificationService {
    enum Identifier {
        static let waterPrefix = "water.reminder"
        static let bedtimeWater = "water.bedtime"
        static let morningCheckIn = "morning.checkin"
        static let hydrationNudge = "water.hydration.nudge"
        static let smartRiskNudge = "session.smart.risk.nudge"
        static let pauseReminder = "session.pause.nudge"
        static let wellbeingCheck = "session.wellbeing.check"
    }

    enum Payload {
        static let sessionID = "session_id"
    }

    static let shared = NotificationService()
    private init() {}

    func requestAuthorization() async -> Bool {
        do {
            return try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
        } catch {
            return false
        }
    }

    func authorizationStatus() async -> UNAuthorizationStatus {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        return settings.authorizationStatus
    }

    func scheduleWaterReminders(every minutes: Int, quietHours: (start: Int, end: Int)?) async {
        await clearRequests(withPrefix: Identifier.waterPrefix)
        guard minutes > 0 else { return }

        let times = reminderTimes(intervalMinutes: minutes, quietHours: quietHours)
        for time in times {
            let content = UNMutableNotificationContent()
            content.title = L10n.tr("Пора воды")
            content.body = L10n.tr("Сделайте несколько глотков воды.")
            content.sound = .default

            var components = DateComponents()
            components.hour = time.hour
            components.minute = time.minute

            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
            let identifier = "\(Identifier.waterPrefix).\(time.hour).\(time.minute)"
            let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
            try? await add(request)
        }
    }

    func scheduleBedtimeWater(for sessionID: UUID, after seconds: TimeInterval = 1800) async {
        cancelBedtimeWater()
        let content = UNMutableNotificationContent()
        content.title = L10n.tr("Вода перед сном")
        content.body = L10n.tr("Стакан воды может облегчить утро.")
        content.sound = .default
        content.userInfo[Payload.sessionID] = sessionID.uuidString

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(60, seconds), repeats: false)
        let request = UNNotificationRequest(identifier: Identifier.bedtimeWater, content: content, trigger: trigger)
        try? await add(request)
    }

    func scheduleMorningCheckIn(for sessionID: UUID, at date: Date) async {
        cancelMorningCheckIn()

        let content = UNMutableNotificationContent()
        content.title = L10n.tr("Утренний чек-ин")
        content.body = L10n.tr("Оцените самочувствие, это займет 10 секунд.")
        content.sound = .default
        content.userInfo[Payload.sessionID] = sessionID.uuidString

        let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        let request = UNNotificationRequest(identifier: Identifier.morningCheckIn, content: content, trigger: trigger)
        try? await add(request)
    }

    func scheduleHydrationNudge(for sessionID: UUID, requiredMl: Int, after seconds: TimeInterval = 1200) async {
        cancelHydrationNudge()
        guard requiredMl > 0 else { return }

        let content = UNMutableNotificationContent()
        content.title = L10n.tr("Водный баланс")
        content.body = L10n.format("Чтобы закрыть цель, выпейте еще примерно %d мл воды.", requiredMl)
        content.sound = .default
        content.userInfo[Payload.sessionID] = sessionID.uuidString

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(60, seconds), repeats: false)
        let request = UNNotificationRequest(identifier: Identifier.hydrationNudge, content: content, trigger: trigger)
        try? await add(request)
    }

    func scheduleSmartRiskNudge(
        for sessionID: UUID,
        morningRisk: InsightLevel,
        memoryRisk: InsightLevel,
        waterDeficitMl: Int
    ) async {
        cancelSmartRiskNudge()

        guard morningRisk != .low || memoryRisk != .low || waterDeficitMl > 250 else { return }

        let delay: TimeInterval
        if memoryRisk == .high || morningRisk == .high {
            delay = 8 * 60
        } else if waterDeficitMl >= 500 {
            delay = 12 * 60
        } else {
            delay = 18 * 60
        }

        let content = UNMutableNotificationContent()
        content.title = L10n.tr("Пауза и вода")
        content.body = smartRiskBody(morningRisk: morningRisk, memoryRisk: memoryRisk, waterDeficitMl: waterDeficitMl)
        content.sound = .default
        content.userInfo[Payload.sessionID] = sessionID.uuidString

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(60, delay), repeats: false)
        let request = UNNotificationRequest(identifier: Identifier.smartRiskNudge, content: content, trigger: trigger)
        try? await add(request)
    }

    func scheduleWellbeingCheck(
        for sessionID: UUID,
        morningRisk: InsightLevel,
        memoryRisk: InsightLevel
    ) async {
        cancelWellbeingCheck()
        guard morningRisk != .low || memoryRisk != .low else { return }

        let delay: TimeInterval
        if memoryRisk == .high || morningRisk == .high {
            delay = 10 * 60
        } else {
            delay = 16 * 60
        }

        let content = UNMutableNotificationContent()
        content.title = L10n.tr("Проверка самочувствия")
        content.body = wellbeingBody(morningRisk: morningRisk, memoryRisk: memoryRisk)
        content.sound = .default
        content.userInfo[Payload.sessionID] = sessionID.uuidString

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: delay, repeats: false)
        let request = UNNotificationRequest(identifier: Identifier.wellbeingCheck, content: content, trigger: trigger)
        try? await add(request)
    }

    func cancelWaterReminders() async {
        await clearRequests(withPrefix: Identifier.waterPrefix)
    }

    func cancelBedtimeWater() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [Identifier.bedtimeWater])
    }

    func cancelMorningCheckIn() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [Identifier.morningCheckIn])
    }

    func cancelHydrationNudge() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [Identifier.hydrationNudge])
    }

    func cancelSmartRiskNudge() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [Identifier.smartRiskNudge])
    }

    func cancelWellbeingCheck() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [Identifier.wellbeingCheck])
    }

    func schedulePauseReminder(after minutes: Int = 25) async {
        let content = UNMutableNotificationContent()
        content.title = L10n.tr("Пауза для восстановления")
        content.body = L10n.tr("Сделайте 25 минут спокойного режима и воду — это ускорит восстановление.")
        content.sound = .default

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: Double(max(5, minutes * 60)), repeats: false)
        let request = UNNotificationRequest(identifier: Identifier.pauseReminder, content: content, trigger: trigger)
        try? await add(request)
    }

    private func smartRiskBody(morningRisk: InsightLevel, memoryRisk: InsightLevel, waterDeficitMl: Int) -> String {
        if memoryRisk == .high {
            return L10n.tr("Риск фрагментов памяти растет. Лучше сделать паузу и переключиться на воду.")
        }
        if morningRisk == .high {
            return L10n.tr("Утренний риск высокий. Добавьте воду и не ускоряйте темп.")
        }
        if waterDeficitMl > 0 {
            return L10n.format("Сейчас полезно добрать воду: еще около %d мл.", waterDeficitMl)
        }
        return L10n.tr("Сделайте короткую паузу и оцените самочувствие.")
    }

    private func wellbeingBody(morningRisk: InsightLevel, memoryRisk: InsightLevel) -> String {
        if memoryRisk == .high {
            return L10n.tr("Сделайте минутную самопроверку: вода, пауза и спокойный темп сейчас особенно важны.")
        }
        if morningRisk == .high {
            return L10n.tr("Проверьте самочувствие и темп. Лучше добавить воду и сделать паузу.")
        }
        return L10n.tr("Короткая проверка состояния: как самочувствие, вода и темп?")
    }

    private func reminderTimes(intervalMinutes: Int, quietHours: (start: Int, end: Int)?) -> [(hour: Int, minute: Int)] {
        var result: [(hour: Int, minute: Int)] = []
        var minuteOfDay = 0

        while minuteOfDay < 24 * 60 {
            let hour = minuteOfDay / 60
            let minute = minuteOfDay % 60

            if !isQuietHour(hour: hour, quietHours: quietHours) {
                result.append((hour, minute))
            }

            minuteOfDay += intervalMinutes
        }

        if result.isEmpty {
            result.append((12, 0))
        }

        return result
    }

    private func isQuietHour(hour: Int, quietHours: (start: Int, end: Int)?) -> Bool {
        guard let quietHours else { return false }
        if quietHours.start == quietHours.end { return false }
        if quietHours.start < quietHours.end {
            return hour >= quietHours.start && hour < quietHours.end
        }
        return hour >= quietHours.start || hour < quietHours.end
    }

    private func clearRequests(withPrefix prefix: String) async {
        let requests = await pendingRequests()
        let ids = requests.map(\.identifier).filter { $0.hasPrefix(prefix) }
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ids)
    }

    private func pendingRequests() async -> [UNNotificationRequest] {
        await withCheckedContinuation { (continuation: CheckedContinuation<[UNNotificationRequest], Never>) in
            UNUserNotificationCenter.current().getPendingNotificationRequests { requests in
                continuation.resume(returning: requests)
            }
        }
    }

    private func add(_ request: UNNotificationRequest) async throws {
        let _: Void = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            UNUserNotificationCenter.current().add(request) { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: ())
                }
            }
        }
    }
}
