import SwiftUI
import SwiftData
import UIKit

struct OnboardingView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.openURL) private var openURL
    @AppStorage("didFinishOnboarding") private var didFinishOnboarding = false

    @State private var page = 0
    @State private var weight: Double = 70
    @State private var unit: UserProfile.UnitSystem = .metric
    @State private var sex: UserProfile.BiologicalSex = .unspecified
    @State private var notificationsWanted = false
    @State private var notificationStatusText = L10n.tr("Пока не настроено")
    @State private var showWeightValidation = false

    private let service = SessionService()

    var body: some View {
        VStack {
            TabView(selection: $page) {
                onboardingIntro.tag(0)
                onboardingProfile.tag(1)
                onboardingNotifications.tag(2)
            }
            .tabViewStyle(.page(indexDisplayMode: .automatic))
            .animation(.easeInOut, value: page)
            HStack {
                if page > 0 {
                    Button("Назад") { page -= 1 }
                }
                Spacer()
                Button(page == 2 ? "Готово" : "Дальше") {
                    if page == 2 {
                        finish()
                    } else if page == 1, weight <= 0 {
                        showWeightValidation = true
                    } else {
                        page += 1
                    }
                }
            }
            .padding()
        }
    }

    private var onboardingIntro: some View {
        VStack(spacing: 12) {
            Text("Контроль, вода, утро")
                .font(.title2)
            VStack(alignment: .leading, spacing: 10) {
                Label("Контроль в моменте: BAC и таймер отрезвления (примерно)", systemImage: "gauge")
                Label("Поддержка привычки: быстрый лог воды и напоминания", systemImage: "drop")
                Label("Утренний прогноз и чек-ин за 10 секунд", systemImage: "sun.max")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Text("Приложение про harm-reduction, без советов про вождение.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
        }
        .padding()
    }

    private var onboardingProfile: some View {
        Form {
            Section("Профиль для расчёта") {
                Stepper(value: $weight, in: 30...200, step: 1) {
                    HStack {
                        Text("Вес")
                        Spacer()
                        Text(String(format: "%.0f %@", weight, unit == .metric ? "кг" : "lbs"))
                    }
                }
                Picker("Единицы", selection: $unit) {
                    Text("Метрические").tag(UserProfile.UnitSystem.metric)
                    Text("Имперские").tag(UserProfile.UnitSystem.imperial)
                }
                Picker("Пол (опционально)", selection: $sex) {
                    ForEach(UserProfile.BiologicalSex.allCases) { s in
                        Text(s.label).tag(s)
                    }
                }
                Text("Можно изменить позже. Выбор 'Не указан' снижает точность.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .overlay(alignment: .bottom) {
            if showWeightValidation {
                Text("Введите корректный вес")
                    .font(.caption)
                    .padding(8)
                    .background(.red.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
    }

    private var onboardingNotifications: some View {
        VStack(spacing: 16) {
            Text("Напоминания")
                .font(.title2)
            Text("Вода во время сессии и утренний чек-ин. Разрешите уведомления, чтобы не забыть.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Button("Разрешить уведомления") {
                Task {
                    notificationsWanted = await NotificationService.shared.requestAuthorization()
                    notificationStatusText = notificationsWanted ? L10n.tr("Разрешены") : L10n.tr("Отклонены")
                }
            }
            .buttonStyle(.borderedProminent)
            Button("Пока не надо") {
                notificationStatusText = L10n.tr("Можно включить позже в Настройках")
            }
            .buttonStyle(.bordered)
            Text(notificationStatusText)
                .font(.footnote)
                .foregroundStyle(.secondary)
            if !notificationsWanted {
                Button("Открыть настройки iOS") {
                    guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                    openURL(url)
                }
                .font(.footnote)
            }
        }
        .padding()
    }

    private func finish() {
        do {
            let profile = try service.upsertProfile(context: context, weight: weight, unitSystem: unit, sex: sex)
            profile.notificationsEnabled = notificationsWanted
        } catch {
            print("Failed to save profile: \(error)")
        }
        didFinishOnboarding = true
    }
}
