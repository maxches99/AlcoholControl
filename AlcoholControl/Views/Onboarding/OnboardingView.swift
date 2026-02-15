import SwiftUI
import SwiftData

struct OnboardingView: View {
    @Environment(\.modelContext) private var context
    @AppStorage("didFinishOnboarding") private var didFinishOnboarding = false

    @State private var page = 0
    @State private var weight: Double = 70
    @State private var unit: UserProfile.UnitSystem = .metric
    @State private var sex: UserProfile.BiologicalSex = .unspecified
    @State private var showWeightValidation = false

    private let service = SessionService()

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(L10n.format("Шаг %d из 2", page + 1))
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.horizontal)
            .padding(.top, 12)

            TabView(selection: $page) {
                onboardingIntro.tag(0)
                onboardingProfile.tag(1)
            }
            .tabViewStyle(.page(indexDisplayMode: .automatic))
            .animation(.easeInOut, value: page)

            HStack {
                if page > 0 {
                    Button(L10n.tr("Назад")) { page -= 1 }
                }
                Spacer()
                Button(page == 1 ? L10n.tr("Начать") : L10n.tr("Дальше")) {
                    if page == 1 {
                        if weight <= 0 {
                            showWeightValidation = true
                        } else {
                            finish()
                        }
                    } else {
                        page += 1
                    }
                }
                .buttonStyle(.borderedProminent)
            }
            .padding()
        }
    }

    private var onboardingIntro: some View {
        VStack(spacing: 12) {
            Text(L10n.tr("Контроль, вода, утро"))
                .font(.title2)
            VStack(alignment: .leading, spacing: 10) {
                Label(L10n.tr("Контроль в моменте: BAC и таймер отрезвления (примерно)"), systemImage: "gauge")
                Label(L10n.tr("Поддержка привычки: быстрый лог воды и напоминания"), systemImage: "drop")
                Label(L10n.tr("Утренний прогноз и чек-ин за 10 секунд"), systemImage: "sun.max")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Text(L10n.tr("Это инструмент harm-reduction: помогает замечать риски и вовремя делать паузы."))
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
        }
        .padding()
    }

    private var onboardingProfile: some View {
        Form {
            Section(L10n.tr("Профиль для расчёта")) {
                Stepper(value: $weight, in: 30...200, step: 1) {
                    HStack {
                        Text(L10n.tr("Вес"))
                        Spacer()
                        Text(L10n.format("%.0f %@", weight, unit == .metric ? L10n.tr("кг") : L10n.tr("lbs")))
                    }
                }
                Picker(L10n.tr("Единицы"), selection: $unit) {
                    Text(L10n.tr("Метрические")).tag(UserProfile.UnitSystem.metric)
                    Text(L10n.tr("Имперские")).tag(UserProfile.UnitSystem.imperial)
                }
                Picker(L10n.tr("Пол (опционально)"), selection: $sex) {
                    ForEach(UserProfile.BiologicalSex.allCases) { s in
                        Text(s.label).tag(s)
                    }
                }
                Text(L10n.tr("Можно изменить позже. Выбор 'Не указан' снижает точность."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .overlay(alignment: .bottom) {
            if showWeightValidation {
                Text(L10n.tr("Введите корректный вес"))
                    .font(.caption)
                    .padding(8)
                    .background(.red.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
    }

    private func finish() {
        do {
            let profile = try service.upsertProfile(context: context, weight: weight, unitSystem: unit, sex: sex)
            profile.notificationsEnabled = false
        } catch {
            print(L10n.format("Failed to save profile: %@", String(describing: error)))
        }
        didFinishOnboarding = true
    }
}
