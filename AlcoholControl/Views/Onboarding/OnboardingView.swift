import SwiftUI
import SwiftData

struct OnboardingView: View {
    @Environment(\.modelContext) private var context
    @AppStorage("didFinishOnboarding") private var didFinishOnboarding = false
    @AppStorage("onboardingWeeklyFocus") private var onboardingWeeklyFocusRaw = WeeklyFocus.hydration.rawValue

    @State private var page = 0
    @State private var weight: Double = 70
    @State private var unit: UserProfile.UnitSystem = .metric
    @State private var sex: UserProfile.BiologicalSex = .unspecified
    @State private var showWeightValidation = false
    @State private var focus: WeeklyFocus = .hydration

    private let service = SessionService()

    var body: some View {
        VStack(spacing: 0) {
            topBar

            TabView(selection: $page) {
                focusPage
                    .padding(.horizontal, AppDesign.Spacing.lg)
                    .tag(0)

                profilePage
                    .padding(.horizontal, AppDesign.Spacing.lg)
                    .tag(1)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .animation(.easeInOut(duration: 0.24), value: page)

            bottomArea
        }
        .padding(.top, AppDesign.Spacing.sm)
        .onAppear {
            focus = WeeklyFocus(rawValue: onboardingWeeklyFocusRaw) ?? .hydration
        }
        .background(onboardingBackground.ignoresSafeArea())
    }

    private var topBar: some View {
        HStack {
            Label {
                Text("AlcoholControl")
                    .font(.system(.title3, design: .rounded).weight(.bold))
                    .foregroundStyle(Color.white.opacity(0.95))
            } icon: {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(AppDesign.Colors.primary.opacity(0.25))
                        .frame(width: 34, height: 34)
                    Image(systemName: "drop.fill")
                        .foregroundStyle(AppDesign.Colors.primary)
                        .font(.system(size: 15, weight: .bold))
                }
            }

            Spacer()

            Button(L10n.tr("Пропустить")) {
                finish()
            }
            .font(.headline.weight(.medium))
            .foregroundStyle(Color.white.opacity(0.62))
        }
        .padding(.horizontal, AppDesign.Spacing.lg)
        .padding(.top, AppDesign.Spacing.md)
        .padding(.bottom, AppDesign.Spacing.sm)
    }

    private var focusPage: some View {
        VStack(alignment: .leading, spacing: AppDesign.Spacing.lg) {
            onboardingHero

            VStack(alignment: .leading, spacing: AppDesign.Spacing.md) {
                Text(L10n.tr("Твой ритм, твои правила"))
                    .font(.system(.largeTitle, design: .rounded).weight(.bold))
                    .foregroundStyle(Color.white.opacity(0.96))

                Text(L10n.tr("Без осуждения и ярлыков: только поддержка, чтобы замечать риски и проходить вечер мягче."))
                    .font(.system(.title3, design: .rounded))
                    .foregroundStyle(Color.white.opacity(0.66))
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: AppDesign.Spacing.sm) {
                Text(L10n.tr("Фокус на эту неделю"))
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(Color.white.opacity(0.8))

                ForEach(WeeklyFocus.allCases) { option in
                    focusRow(option)
                }
            }

            Spacer(minLength: 0)
        }
    }

    private var onboardingHero: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 56, style: .continuous)
                .fill(Color.white.opacity(0.16))
                .frame(height: 260)

            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            AppDesign.Colors.primary.opacity(0.56),
                            AppDesign.Colors.accent.opacity(0.42),
                            Color.white.opacity(0.18)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .padding(.horizontal, 18)
                .frame(height: 168)
                .overlay {
                    HStack(spacing: 14) {
                        Image(systemName: "drop.circle.fill")
                            .font(.system(size: 42))
                            .foregroundStyle(Color.white.opacity(0.82))
                        VStack(alignment: .leading, spacing: 6) {
                            Text(L10n.tr("Сессия под контролем"))
                                .font(.headline.weight(.semibold))
                                .foregroundStyle(Color.white.opacity(0.9))
                            Text(L10n.tr("Паузы, вода и утренний check-in в одном потоке"))
                                .font(.subheadline)
                                .foregroundStyle(Color.white.opacity(0.72))
                        }
                    }
                    .padding(.horizontal, 22)
                }
        }
    }

    private func focusRow(_ option: WeeklyFocus) -> some View {
        let isSelected = option == focus

        return Button {
            focus = option
        } label: {
            HStack(spacing: AppDesign.Spacing.md) {
                Image(systemName: option.icon)
                    .font(.system(size: 20, weight: .semibold))
                    .frame(width: 24)
                    .foregroundStyle(isSelected ? AppDesign.Colors.primary : Color.white.opacity(0.58))

                Text(option.title)
                    .font(.system(.title3, design: .rounded).weight(.semibold))
                    .foregroundStyle(Color.white.opacity(isSelected ? 0.96 : 0.8))

                Spacer()

                Image(systemName: isSelected ? "checkmark.circle.fill" : "plus.circle")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(isSelected ? AppDesign.Colors.primary : Color.white.opacity(0.16))
            }
            .padding(.horizontal, AppDesign.Spacing.md)
            .frame(height: 66)
            .background(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(Color.white.opacity(isSelected ? 0.1 : 0.06))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(Color.white.opacity(isSelected ? 0.44 : 0.1), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private var profilePage: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: AppDesign.Spacing.md) {
                Text(L10n.tr("Профиль для расчета"))
                    .font(.system(.title2, design: .rounded).weight(.bold))
                    .foregroundStyle(Color.white.opacity(0.96))

                Text(L10n.tr("Нужно только для более точной оценки BAC и времени восстановления. Изменить можно позже."))
                    .font(.body)
                    .foregroundStyle(Color.white.opacity(0.68))

                VStack(alignment: .leading, spacing: AppDesign.Spacing.sm) {
                    Text(L10n.tr("Единицы"))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.white.opacity(0.74))
                    Picker(L10n.tr("Единицы"), selection: $unit) {
                        Text(L10n.tr("Метрические")).tag(UserProfile.UnitSystem.metric)
                        Text(L10n.tr("Имперские")).tag(UserProfile.UnitSystem.imperial)
                    }
                    .pickerStyle(.segmented)
                    .colorScheme(.dark)
                }

                VStack(alignment: .leading, spacing: AppDesign.Spacing.sm) {
                    HStack {
                        Text(L10n.tr("Вес"))
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Color.white.opacity(0.74))
                        Spacer()
                        Text(L10n.format("%.0f %@", weight, unit == .metric ? L10n.tr("кг") : L10n.tr("lbs")))
                            .font(.headline)
                            .foregroundStyle(Color.white.opacity(0.92))
                    }
                    Slider(value: $weight, in: unit.weightRange, step: 1)
                        .tint(AppDesign.Colors.primary)
                }

                VStack(alignment: .leading, spacing: AppDesign.Spacing.sm) {
                    Text(L10n.tr("Пол (опционально)"))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.white.opacity(0.74))
                    Picker(L10n.tr("Пол (опционально)"), selection: $sex) {
                        ForEach(UserProfile.BiologicalSex.allCases) { s in
                            Text(s.label).tag(s)
                        }
                    }
                    .pickerStyle(.menu)
                    .tint(Color.white.opacity(0.9))
                }

                Text(L10n.tr("Можно оставить 'Не указан', но точность модели будет ниже."))
                    .font(.caption)
                    .foregroundStyle(Color.white.opacity(0.6))

                if showWeightValidation {
                    Text(L10n.tr("Введите корректный вес"))
                        .font(.caption)
                        .padding(AppDesign.Spacing.sm)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(AppDesign.Colors.error.opacity(0.22))
                        .clipShape(RoundedRectangle(cornerRadius: AppDesign.Radius.sm, style: .continuous))
                }
            }
            .padding(AppDesign.Spacing.md)
            .background(
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .fill(Color.white.opacity(0.08))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .stroke(Color.white.opacity(0.1), lineWidth: 1)
            )
            .padding(.bottom, AppDesign.Spacing.md)
        }
        .onChange(of: unit) { oldValue, newValue in
            let converted = oldValue.convertWeight(weight, to: newValue)
            weight = newValue.normalizeWeight(converted).rounded()
        }
    }

    private var bottomArea: some View {
        VStack(spacing: AppDesign.Spacing.md) {
            pageDots

            Button(page == 1 ? L10n.tr("Начать") : L10n.tr("Продолжить")) {
                if page == 1 {
                    if weight <= 0 {
                        showWeightValidation = true
                    } else {
                        finish()
                    }
                } else {
                    withAnimation(.easeInOut(duration: 0.24)) {
                        page = 1
                    }
                }
            }
            .buttonStyle(AppPrimaryButtonStyle())

            Text(L10n.tr("Продолжая, вы выбираете более безопасный и осознанный формат вечера."))
                .font(.caption)
                .foregroundStyle(Color.white.opacity(0.45))
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, AppDesign.Spacing.lg)
        .padding(.top, AppDesign.Spacing.md)
        .padding(.bottom, AppDesign.Spacing.lg)
    }

    private var pageDots: some View {
        HStack(spacing: 7) {
            ForEach(0..<2, id: \.self) { index in
                Capsule(style: .continuous)
                    .fill(index == page ? AppDesign.Colors.primary : Color.white.opacity(0.2))
                    .frame(width: index == page ? 28 : 9, height: 9)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var onboardingBackground: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.05, green: 0.07, blue: 0.08),
                    Color(red: 0.07, green: 0.09, blue: 0.09),
                    Color(red: 0.04, green: 0.06, blue: 0.07)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Circle()
                .fill(AppDesign.Colors.primary.opacity(0.1))
                .frame(width: 230, height: 230)
                .offset(x: -150, y: -320)

            RoundedRectangle(cornerRadius: 90, style: .continuous)
                .fill(AppDesign.Colors.secondary.opacity(0.08))
                .frame(width: 220, height: 100)
                .offset(x: 140, y: 380)
        }
    }

    private func finish() {
        onboardingWeeklyFocusRaw = focus.rawValue

        do {
            let profile = try service.upsertProfile(context: context, weight: weight, unitSystem: unit, sex: sex)
            profile.notificationsEnabled = false
        } catch {
            print(L10n.format("Failed to save profile: %@", String(describing: error)))
        }
        didFinishOnboarding = true
    }
}

private enum WeeklyFocus: String, CaseIterable, Identifiable {
    case hydration
    case pace
    case morningCheckIn

    var id: String { rawValue }

    var title: String {
        switch self {
        case .hydration:
            return L10n.tr("Пить воду между напитками")
        case .pace:
            return L10n.tr("Снизить темп")
        case .morningCheckIn:
            return L10n.tr("Стабильный утренний check-in")
        }
    }

    var icon: String {
        switch self {
        case .hydration:
            return "heart"
        case .pace:
            return "clock"
        case .morningCheckIn:
            return "sun.min"
        }
    }
}
