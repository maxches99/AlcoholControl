import SwiftUI
import SwiftData
import UserNotifications
import UIKit

struct NotificationsSettingsView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.openURL) private var openURL
    @Query private var profiles: [UserProfile]

    @State private var notificationsEnabled = false
    @State private var intervalMinutes = 45
    @State private var quietHoursEnabled = false
    @State private var quietStart = 23
    @State private var quietEnd = 8
    @State private var statusMessage = ""
    @State private var authorizationStatus: UNAuthorizationStatus = .notDetermined

    private let service = SessionService()

    init() {
        _profiles = Query()
    }

    private var profile: UserProfile? {
        profiles.first
    }

    var body: some View {
        Form {
            Section("Разрешение") {
                Text(statusLine)
                    .foregroundStyle(.secondary)
                Button("Запросить разрешение") {
                    Task {
                        let granted = await NotificationService.shared.requestAuthorization()
                        authorizationStatus = await NotificationService.shared.authorizationStatus()
                        statusMessage = granted ? L10n.tr("Разрешение получено") : L10n.tr("Разрешение отклонено")
                    }
                }
                if authorizationStatus == .denied {
                    Button("Открыть настройки iOS") {
                        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                        openURL(url)
                    }
                }
            }

            Section("Вода во время сессии") {
                Toggle("Включить напоминания", isOn: $notificationsEnabled)

                Stepper(value: $intervalMinutes, in: 30...120, step: 15) {
                    HStack {
                        Text("Интервал")
                        Spacer()
                        Text("\(intervalMinutes) мин")
                    }
                }

                Toggle("Тихие часы", isOn: $quietHoursEnabled)
                if quietHoursEnabled {
                    Stepper("С \(quietStart):00", value: $quietStart, in: 0...23)
                    Stepper("До \(quietEnd):00", value: $quietEnd, in: 0...23)
                }

                Button("Сохранить и перепланировать") {
                    Task {
                        await saveAndReschedule()
                    }
                }
            }

            if !statusMessage.isEmpty {
                Section {
                    Text(statusMessage)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Уведомления")
        .task {
            await loadState()
        }
    }

    private var statusLine: String {
        switch authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return L10n.tr("Уведомления разрешены")
        case .denied:
            return L10n.tr("Уведомления отключены в системе")
        case .notDetermined:
            return L10n.tr("Разрешение еще не запрошено")
        @unknown default:
            return L10n.tr("Неизвестный статус")
        }
    }

    @MainActor
    private func loadState() async {
        authorizationStatus = await NotificationService.shared.authorizationStatus()

        if let profile {
            notificationsEnabled = profile.notificationsEnabled
            intervalMinutes = profile.waterReminderIntervalMinutes
            quietHoursEnabled = profile.quietHoursEnabled
            quietStart = (profile.quietHoursStartMinutes ?? 23 * 60) / 60
            quietEnd = (profile.quietHoursEndMinutes ?? 8 * 60) / 60
            return
        }

        do {
            let created = try service.fetchOrCreateProfile(context: context)
            notificationsEnabled = created.notificationsEnabled
            intervalMinutes = created.waterReminderIntervalMinutes
            quietHoursEnabled = created.quietHoursEnabled
        } catch {
            statusMessage = L10n.tr("Не удалось загрузить профиль")
        }
    }

    @MainActor
    private func saveAndReschedule() async {
        guard let profile = try? service.fetchOrCreateProfile(context: context) else {
            statusMessage = L10n.tr("Не удалось сохранить профиль")
            return
        }

        profile.notificationsEnabled = notificationsEnabled
        profile.waterReminderIntervalMinutes = intervalMinutes
        profile.quietHoursEnabled = quietHoursEnabled
        profile.quietHoursStartMinutes = quietHoursEnabled ? quietStart * 60 : nil
        profile.quietHoursEndMinutes = quietHoursEnabled ? quietEnd * 60 : nil
        profile.updatedAt = .now

        authorizationStatus = await NotificationService.shared.authorizationStatus()

        guard notificationsEnabled else {
            await NotificationService.shared.cancelWaterReminders()
            NotificationService.shared.cancelHydrationNudge()
            statusMessage = L10n.tr("Напоминания выключены")
            return
        }

        guard authorizationStatus == .authorized || authorizationStatus == .provisional || authorizationStatus == .ephemeral else {
            statusMessage = L10n.tr("Включите уведомления в Настройках iOS")
            return
        }

        await NotificationService.shared.scheduleWaterReminders(
            every: intervalMinutes,
            quietHours: quietHoursEnabled ? (start: quietStart, end: quietEnd) : nil
        )

        statusMessage = L10n.tr("Уведомления обновлены")
    }
}
