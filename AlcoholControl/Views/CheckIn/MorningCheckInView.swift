import SwiftUI
import SwiftData

struct MorningCheckInView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    let session: Session
    var onSaved: (UUID) -> Void

    @State private var wellbeing: Int?
    @State private var selectedSymptoms: Set<MorningCheckIn.Symptom> = []
    @State private var sleepHours: Double = 7
    @State private var hadWater = true
    @State private var showValidation = false
    @State private var healthStatus = ""
    @State private var isHealthLoading = false

    private let symptomColumns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]

    private var nonEmptySymptoms: [MorningCheckIn.Symptom] {
        MorningCheckIn.Symptom.allCases.filter { $0 != .none }
    }

    private var saveDisabled: Bool {
        wellbeing == nil
    }

    private var recoveryText: String {
        let highlighted = selectedSymptoms.prefix(2).map(\.label)
        if !highlighted.isEmpty {
            return L10n.format(
                "Вы отметили: %@. Начните с воды, легкой еды и спокойного темпа утром.",
                highlighted.joined(separator: ", ")
            )
        }

        if let wellbeing, wellbeing <= 2 {
            return L10n.tr("Утро может быть непростым. Дайте себе больше пауз, воды и щадящий режим.")
        }

        return L10n.tr("Поддержите восстановление: вода, легкий завтрак и короткая прогулка без спешки.")
    }

    var body: some View {
        NavigationStack {
            ZStack {
                LinearGradient(
                    colors: [
                        Color(light: 0x111514, dark: 0x0E1211),
                        Color(light: 0x121A18, dark: 0x111917)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 26) {
                        topBar
                        titleBlock
                        wellbeingBlock
                        symptomsBlock
                        additionalBlock
                        recoveryBlock
                        completeButton
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 18)
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .alert(L10n.tr("Заполните оценку"), isPresented: $showValidation) {
                Button(L10n.tr("Ок"), role: .cancel) {}
            } message: {
                Text(L10n.tr("Выберите wellbeing score от 1 до 5."))
            }
        }
    }

    private var topBar: some View {
        HStack {
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.75))
                    .frame(width: 42, height: 42)
                    .background(
                        Circle()
                            .fill(Color.white.opacity(0.06))
                    )
            }

            Spacer()

            Text(L10n.tr("Утренний чек-ин"))
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .foregroundStyle(Color(light: 0x5D554A, dark: 0x5D554A))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
                .background(
                    Capsule(style: .continuous)
                        .fill(Color(light: 0xECE4D6, dark: 0xECE4D6))
                )
        }
    }

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L10n.tr("Как ты себя чувствуешь сегодня?"))
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundStyle(.white.opacity(0.95))

            Text(L10n.tr("Отмечай состояние без самокритики. Это помогает видеть паттерны и мягко восстанавливаться."))
                .font(.system(size: 15, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.62))
        }
    }

    private var wellbeingBlock: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(L10n.tr("Энергия тела"))
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundStyle(.white.opacity(0.93))

            HStack(spacing: 10) {
                ForEach(1...5, id: \.self) { score in
                    levelPill(score: score)
                }
            }

            HStack {
                Text(L10n.tr("Истощение"))
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.34))

                Spacer()

                Text(L10n.tr("Восстановление"))
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.34))
            }
        }
    }

    private func levelPill(score: Int) -> some View {
        let isSelected = wellbeing == score

        return Button {
            wellbeing = score
        } label: {
            Text("\(score)")
                .font(.system(size: 22, weight: .semibold, design: .rounded))
                .foregroundStyle(isSelected ? Color.black.opacity(0.8) : Color.white.opacity(0.66))
                .frame(maxWidth: .infinity)
                .frame(height: 56)
                .background(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .fill(isSelected ? AppDesign.Colors.primary : Color.white.opacity(0.07))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .stroke(Color.white.opacity(isSelected ? 0.1 : 0.08), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }

    private var symptomsBlock: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(L10n.tr("Есть дискомфорт?"))
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundStyle(.white.opacity(0.93))

            LazyVGrid(columns: symptomColumns, spacing: 12) {
                ForEach(nonEmptySymptoms) { symptom in
                    symptomChip(symptom)
                }
            }
        }
    }

    private func symptomChip(_ symptom: MorningCheckIn.Symptom) -> some View {
        let isSelected = selectedSymptoms.contains(symptom)

        return Button {
            if isSelected {
                selectedSymptoms.remove(symptom)
            } else {
                selectedSymptoms.insert(symptom)
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: iconName(for: symptom))
                    .font(.system(size: 14, weight: .semibold))

                Text(symptom.label)
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .foregroundStyle(isSelected ? Color.black.opacity(0.78) : .white.opacity(0.86))
            .frame(maxWidth: .infinity)
            .frame(height: 54)
            .background(
                RoundedRectangle(cornerRadius: 30, style: .continuous)
                    .fill(isSelected ? AppDesign.Colors.primary.opacity(0.95) : Color.white.opacity(0.06))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 30, style: .continuous)
                    .stroke(Color.white.opacity(0.09), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private func iconName(for symptom: MorningCheckIn.Symptom) -> String {
        switch symptom {
        case .headache: return "brain.head.profile"
        case .nausea: return "facemask"
        case .fatigue: return "cloud"
        case .thirst: return "drop"
        case .anxiety: return "heart"
        case .none: return "checkmark"
        }
    }

    private var additionalBlock: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(L10n.tr("Безопасность и паттерны"))
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundStyle(.white.opacity(0.93))

            VStack(spacing: 12) {
                supportRow(
                    icon: "drop",
                    title: L10n.tr("Пил(а) воду"),
                    subtitle: L10n.tr("Отметь, если вода была в конце сессии")
                ) {
                    Toggle("", isOn: $hadWater)
                        .labelsHidden()
                        .tint(AppDesign.Colors.primary)
                }

                supportRow(
                    icon: "bed.double",
                    title: L10n.tr("Сон"),
                    subtitle: L10n.format("%.1f ч", sleepHours)
                ) {
                    Button {
                        Task { await importSleepFromHealth() }
                    } label: {
                        Text(isHealthLoading ? L10n.tr("Импортируем...") : L10n.tr("Импорт из Health"))
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white.opacity(0.86))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .background(
                                Capsule(style: .continuous)
                                    .fill(Color.white.opacity(0.08))
                            )
                    }
                    .buttonStyle(.plain)
                    .disabled(isHealthLoading)
                }
            }

            if !healthStatus.isEmpty {
                Text(healthStatus)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.6))
                    .padding(.horizontal, 4)
            }
        }
    }

    private func supportRow<Control: View>(
        icon: String,
        title: String,
        subtitle: String,
        @ViewBuilder control: () -> Control
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(AppDesign.Colors.primary)
                .frame(width: 44, height: 44)
                .background(
                    Circle()
                        .fill(Color.black.opacity(0.25))
                )

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.93))

                Text(subtitle)
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.58))
            }

            Spacer(minLength: 8)

            control()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color.white.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
    }

    private var recoveryBlock: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: "figure.mind.and.body")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Color.black.opacity(0.72))
                .frame(width: 52, height: 52)
                .background(
                    Circle()
                        .fill(AppDesign.Colors.primary.opacity(0.75))
                )

            VStack(alignment: .leading, spacing: 6) {
                Text(L10n.tr("Шаг восстановления"))
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.black.opacity(0.72))

                Text(recoveryText)
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundStyle(Color.black.opacity(0.6))
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(Color(light: 0xEEEAE4, dark: 0xE8E3DA))
        )
    }

    private var completeButton: some View {
        Button(L10n.tr("Завершить check-in")) {
            save()
        }
        .buttonStyle(.plain)
        .font(.system(size: 20, weight: .semibold, design: .rounded))
        .foregroundStyle(saveDisabled ? Color.black.opacity(0.45) : Color.black.opacity(0.8))
        .frame(maxWidth: .infinity)
        .frame(height: 56)
        .background(
            Capsule(style: .continuous)
                .fill(AppDesign.Colors.primary.opacity(saveDisabled ? 0.55 : 0.95))
        )
        .padding(.top, 4)
        .padding(.bottom, 16)
        .disabled(saveDisabled)
    }

    private func save() {
        guard let wellbeing else {
            showValidation = true
            return
        }

        let checkIn = MorningCheckIn(
            wellbeingScore: wellbeing,
            symptoms: Array(selectedSymptoms),
            sleepHours: sleepHours,
            hadWater: hadWater,
            session: session
        )

        session.morningCheckIn = checkIn
        session.isActive = false
        session.endAt = session.endAt ?? .now
        context.insert(checkIn)

        onSaved(session.id)
        dismiss()
    }

    private func importSleepFromHealth() async {
        isHealthLoading = true
        defer { isHealthLoading = false }

        guard HealthKitService.shared.isAvailable else {
            healthStatus = L10n.tr("Apple Health недоступен на этом устройстве")
            return
        }

        let granted = await HealthKitService.shared.requestSleepAuthorization()
        guard granted else {
            healthStatus = L10n.tr("Доступ к данным сна не предоставлен.")
            return
        }

        if let imported = await HealthKitService.shared.fetchLastNightSleepHours() {
            sleepHours = imported
            healthStatus = L10n.format("Импортировано: %.1f ч сна.", imported)
        } else {
            healthStatus = L10n.tr("Не удалось получить данные сна за последнюю ночь.")
        }
    }
}
