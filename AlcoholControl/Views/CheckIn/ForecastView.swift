import SwiftUI
import SwiftData

private struct RecoveryChecklistItem: Identifiable {
    let id: String
    let title: String
    var isDone: Bool
}

struct ForecastView: View {
    @Query(sort: [SortDescriptor<Session>(\.startAt, order: .reverse)]) private var sessions: [Session]

    let session: Session
    let profile: UserProfile?
    private let insightService = SessionInsightService()
    @State private var showGlossaryTooltip = false
    @State private var showGlossarySheet = false
    @State private var healthSleepHours: Double?
    @State private var healthStepCount: Int?
    @State private var healthRestingHR: Int?
    @State private var healthHRV: Double?
    @State private var healthSleepEfficiency: Double?
    @State private var loadedHealthData = false
    @State private var recoveryChecklist: [RecoveryChecklistItem] = []
    @Query(sort: [SortDescriptor<HealthDailySnapshot>(\.day, order: .reverse)]) private var healthSnapshots: [HealthDailySnapshot]
    private let baselineCalculator = BaselineCalculator()

    private var healthContext: SessionHealthContext {
        SessionHealthContext(
            sleepHours: healthSleepHours,
            stepCount: healthStepCount,
            restingHeartRate: healthRestingHR,
            hrvSdnn: healthHRV,
            sleepEfficiency: healthSleepEfficiency
        )
    }

    private var baselines: HealthBaselineSet {
        let anchor = recoveryDate(for: session)
        return HealthBaselineSet(
            steps: baselineCalculator.stats(for: .steps, snapshots: healthSnapshots, anchorDay: anchor),
            restingHeartRate: baselineCalculator.stats(for: .restingHeartRate, snapshots: healthSnapshots, anchorDay: anchor),
            hrv: baselineCalculator.stats(for: .heartRateVariability, snapshots: healthSnapshots, anchorDay: anchor),
            sleep: baselineCalculator.stats(for: .sleepDuration, snapshots: healthSnapshots, anchorDay: anchor)
        )
    }

    private var assessment: EveningInsightAssessment {
        insightService.assess(session: session, profile: profile, health: healthContext)
    }

    private var recoveryIndex: RecoveryIndexSnapshot {
        insightService.recoveryIndex(session: session, assessment: assessment, health: healthContext, baselines: baselines)
    }

    private var patternAssessment: PersonalizedPatternAssessment {
        insightService.personalizedPatterns(
            current: session,
            history: sessions,
            profile: profile
        )
    }

    private var standardDrinks: Double {
        session.drinks.reduce(0.0) { partial, drink in
            let grams = drink.volumeMl * (drink.abvPercent / 100) * 0.789
            return partial + (grams / 14.0)
        }
    }

    private var sessionDurationHours: Double {
        max(0, (session.endAt ?? .now).timeIntervalSince(session.startAt) / 3600)
    }

    private var completedHistorySessions: [Session] {
        sessions
            .filter { !$0.isActive && $0.id != session.id }
            .sorted(by: { $0.startAt > $1.startAt })
    }

    private var recentHistorySessions: [Session] {
        Array(completedHistorySessions.prefix(8))
    }

    private var baselinePeakBAC: Double? {
        let values = recentHistorySessions.map(\.cachedPeakBAC).filter { $0 > 0 }
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }

    private var baselineWellbeing: Double? {
        let values = recentHistorySessions.compactMap { $0.morningCheckIn?.wellbeingScore }
        guard !values.isEmpty else { return nil }
        return Double(values.reduce(0, +)) / Double(values.count)
    }

    private var baselineHydrationProgress: Double? {
        let values = recentHistorySessions.map { historySession in
            hydrationProgress(for: historySession)
        }
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }

    private var currentHydrationProgress: Double {
        hydrationProgress(for: session)
    }

    private var historyComparisonInsights: [String] {
        var insights: [String] = []

        if let baselinePeakBAC {
            let diff = session.cachedPeakBAC - baselinePeakBAC
            if diff >= 0.02 {
                insights.append(L10n.format("Текущий пик BAC выше вашего среднего примерно на %.3f.", diff))
            } else if diff <= -0.02 {
                insights.append(L10n.format("Текущий пик BAC ниже вашего среднего примерно на %.3f.", abs(diff)))
            } else {
                insights.append(L10n.tr("Текущий пик BAC близок к вашему обычному уровню."))
            }
        }

        if let baselineHydrationProgress {
            let diff = currentHydrationProgress - baselineHydrationProgress
            let percent = Int((abs(diff) * 100).rounded())
            if diff >= 0.12 {
                insights.append(L10n.format("Гидратация сегодня лучше вашего обычного уровня примерно на %d%%.", percent))
            } else if diff <= -0.12 {
                insights.append(L10n.format("Гидратация сегодня ниже вашего обычного уровня примерно на %d%%.", percent))
            }
        }

        if let baselineWellbeing, let today = session.morningCheckIn?.wellbeingScore {
            let diff = Double(today) - baselineWellbeing
            if diff >= 1 {
                insights.append(L10n.format("Ваш чек-ин сегодня лучше среднего примерно на %.1f балла.", diff))
            } else if diff <= -1 {
                insights.append(L10n.format("Ваш чек-ин сегодня ниже среднего примерно на %.1f балла.", abs(diff)))
            }
        }

        return Array(insights.prefix(3))
    }

    private var healthCorrelationInsights: [String] {
        let sample = recentHistorySessions.filter { $0.morningCheckIn != nil }
        guard sample.count >= 3 else { return [] }

        var insights: [String] = []
        let heavyMornings = sample.filter { ($0.morningCheckIn?.wellbeingScore ?? 5) <= 2 }

        if heavyMornings.count >= 2 {
            let sleepLinked = heavyMornings.filter { ($0.morningCheckIn?.sleepHours ?? 99) < 6 }.count
            if sleepLinked >= max(2, heavyMornings.count / 2) {
                insights.append(
                    L10n.format(
                        "По вашей истории при сне <6ч тяжелые утра встречались чаще (%d из %d).",
                        sleepLinked,
                        heavyMornings.count
                    )
                )
            }

            let heavyWithSteps = heavyMornings.compactMap { session -> Int? in
                HealthKitService.shared.cachedStepCount(on: recoveryDate(for: session))
            }
            let lowSteps = heavyWithSteps.filter { $0 < 5_000 }.count
            if heavyWithSteps.count >= 2, lowSteps >= max(2, heavyWithSteps.count / 2) {
                insights.append(
                    L10n.format(
                        "После утр с <5000 шагов вы чаще отмечали более тяжелое состояние (%d из %d).",
                        lowSteps,
                        heavyWithSteps.count
                    )
                )
            }

            let heavyWithHR = heavyMornings.compactMap { session -> Int? in
                HealthKitService.shared.cachedRestingHeartRate(on: recoveryDate(for: session))
            }
            let highHR = heavyWithHR.filter { $0 >= 75 }.count
            if heavyWithHR.count >= 2, highHR >= max(2, heavyWithHR.count / 2) {
                insights.append(
                    L10n.format(
                        "При пульсе покоя >=75 тяжелые утра встречались чаще (%d из %d).",
                        highHR,
                        heavyWithHR.count
                    )
                )
            }
        }

        if let sleep = healthSleepHours, sleep < 6 {
            insights.append(L10n.tr("Сегодня сон ниже 6ч, по вашей истории это повышает риск более тяжелого утра."))
        }
        if let steps = healthStepCount, steps >= 12_000 {
            insights.append(L10n.tr("Сегодня высокая активность, по истории вам лучше усилить гидратацию и снизить темп утра."))
        }
        if let hr = healthRestingHR, hr >= 75 {
            insights.append(L10n.tr("Пульс в покое выше нормы: по вашей истории лучше избегать перегрузки утром."))
        }

        var unique: [String] = []
        for line in insights where !unique.contains(line) {
            unique.append(line)
        }
        return Array(unique.prefix(4))
    }

    private var personalizedSummary: String {
        let base: String
        switch (assessment.morningRisk, assessment.memoryRisk) {
        case (.high, _):
            base = L10n.tr("Сегодня может быть тяжело. Лучше запланировать щадящий режим и паузы на восстановление.")
        case (.medium, .high):
            base = L10n.tr("Состояние может быть средним, но риск фрагментов памяти повышен. Держите день в более спокойном темпе.")
        case (.medium, _):
            base = L10n.tr("Вероятно среднее самочувствие утром. При нормальном питьевом режиме состояние обычно улучшается в первой половине дня.")
        case (.low, .high):
            base = L10n.tr("По утру риск невысокий, но есть заметный риск, что часть эпизодов запомнилась хуже обычного.")
        case (.low, .medium):
            base = L10n.tr("Утро вероятно пройдет относительно легко, но есть умеренный риск фрагментарной памяти о части эпизодов.")
        case (.low, .low):
            base = L10n.tr("По текущим данным утро должно пройти относительно легко.")
        }

        if let firstInsight = patternAssessment.notes.first {
            return "\(base) \(firstInsight)"
        }
        if let firstInsight = healthCorrelationInsights.first {
            return "\(base) \(firstInsight)"
        }
        if let firstInsight = historyComparisonInsights.first {
            return "\(base) \(firstInsight)"
        }
        return base
    }

    private var sessionProcessScore: Int {
        var score = 30
        score += Int((assessment.waterBalance.progress * 35).rounded())
        if !session.meals.isEmpty {
            score += 15
        }
        let pace = sessionDurationHours > 0.3 ? standardDrinks / sessionDurationHours : standardDrinks
        if pace <= patternAssessment.paceRiskThreshold {
            score += 10
        }
        score += Int((Double(assessment.confidence.scorePercent) * 0.1).rounded())
        return min(100, max(0, score))
    }

    private var sessionProcessHint: String {
        switch sessionProcessScore {
        case 75...:
            return L10n.tr("Процесс вечера выглядел устойчиво и обычно даёт более мягкое восстановление.")
        case 50...74:
            return L10n.tr("Процесс средний: есть 1-2 точки роста, в первую очередь вода и темп.")
        default:
            return L10n.tr("Процесс был нагрузочным: в следующий раз лучше заранее задать лимит и воду.")
        }
    }

    private var improvementWindowText: String {
        guard let soberAt = session.cachedEstimatedSoberAt else {
            return L10n.tr("0.00 сейчас")
        }
        let minutes = max(0, Int(soberAt.timeIntervalSinceNow / 60))
        if minutes <= 0 { return L10n.tr("0.00 сейчас") }
        let hours = minutes / 60
        let rest = minutes % 60
        return hours > 0
            ? L10n.format("Окно улучшения: ~%d ч %d м", hours, rest)
            : L10n.format("Окно улучшения: ~%d м", rest)
    }

    private var personalizedFactors: [(title: String, value: String, hint: String)] {
        let hydration = L10n.format("%d / ~%d мл", assessment.waterBalance.consumedMl, assessment.waterBalance.targetMl)
        let meals = session.meals.isEmpty ? L10n.tr("Нет отметок") : L10n.format("%d прием(ов)", session.meals.count)
        let pace = sessionDurationHours > 0.5 ? L10n.format("%.1f ст.др./ч", standardDrinks / sessionDurationHours) : L10n.tr("Короткая сессия")
        var factors: [(title: String, value: String, hint: String)] = [
            (L10n.tr("Пик BAC"), String(format: "%.3f", session.cachedPeakBAC), L10n.tr("Оценка максимальной нагрузки")),
            (L10n.tr("Темп"), pace, L10n.tr("Выше темп -> выше утренний риск")),
            (L10n.tr("Водный баланс"), hydration, L10n.format("Статус: %@", assessment.waterBalance.status.title)),
            (L10n.tr("Приемы пищи"), meals, assessment.mealImpact)
        ]

        if let healthSleepHours {
            let hint = healthSleepHours < 6
                ? L10n.tr("Сон ниже 6ч может усиливать утомление и тяжесть утра")
                : L10n.tr("Сон из Apple Health может уточнять прогноз")
            factors.append((L10n.tr("Сон (Health)"), L10n.format("%.1f ч", healthSleepHours), hint))
        }
        if let healthStepCount {
            let hint = healthStepCount >= 12_000
                ? L10n.tr("Высокая активность + алкоголь может усиливать обезвоживание")
                : L10n.tr("Умеренная активность обычно лучше для восстановления")
            factors.append((L10n.tr("Шаги сегодня"), L10n.format("%d", healthStepCount), hint))
        }
        if let healthRestingHR {
            let hint = healthRestingHR >= 75
                ? L10n.tr("Повышенный пульс в покое может указывать на повышенную нагрузку")
                : L10n.tr("Пульс в покое в рабочем диапазоне")
            factors.append((L10n.tr("Пульс в покое"), L10n.format("%d bpm", healthRestingHR), hint))
        }

        return factors
    }

    private var recoveryActions: [String] {
        var actions = assessment.actionsNow
        if let checkIn = session.morningCheckIn {
            if let sleep = checkIn.sleepHours, sleep < 6 {
                actions.append(L10n.tr("Добавьте короткий отдых днем, сон < 6 часов усиливает утомление"))
            }
            if checkIn.hadWater == false {
                actions.append(L10n.tr("Начните утро с воды, это поможет мягче пройти восстановление"))
            }
            if checkIn.wellbeingScore <= 2 {
                actions.append(L10n.tr("Снизьте интенсивные нагрузки на первую половину дня"))
            }
        }
        if assessment.waterBalance.deficitMl > 0 {
            actions.append(L10n.tr("Закройте дефицит воды постепенно в течение 2-3 часов"))
        }
        if let baselineHydrationProgress, currentHydrationProgress < baselineHydrationProgress {
            actions.append(L10n.tr("Сегодня гидратация ниже вашей обычной: добавьте 1-2 порции воды"))
        }
        if let baselineWellbeing, baselineWellbeing < 3 {
            actions.append(L10n.tr("По вашей истории утро часто непростое: держите план дня максимально легким"))
        }
        if let healthStepCount, healthStepCount >= 12000 {
            actions.append(L10n.tr("После высокой активности добавьте воду и планируйте более спокойный темп утра"))
        }
        if let healthRestingHR, healthRestingHR >= 75 {
            actions.append(L10n.tr("Пульс в покое выше обычного: лучше снизить кофеин и дать телу восстановиться"))
        }
        actions.append(contentsOf: patternAssessment.actions)
        var unique: [String] = []
        for action in actions where !unique.contains(action) {
            unique.append(action)
        }
        return Array(unique.prefix(5))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("Итог утра")
                    .font(.title2)

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        riskBadge(title: "Тяжелое утро", level: assessment.morningRisk, percent: assessment.morningProbabilityPercent)
                        riskBadge(title: "Провалы памяти", level: assessment.memoryRisk, percent: assessment.memoryProbabilityPercent)
                    }
                    HStack {
                        Text("Уверенность модели")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("~\(assessment.confidence.scorePercent)%")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(levelColor(assessment.confidence.level))
                    }
                    ProgressView(value: Double(assessment.confidence.scorePercent) / 100)
                        .tint(levelColor(assessment.confidence.level))
                    HStack {
                        Text(L10n.tr("Индекс восстановления"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("\(recoveryIndex.score)/100")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(levelColor(recoveryIndex.level))
                    }
                    ProgressView(value: Double(recoveryIndex.score) / 100)
                        .tint(levelColor(recoveryIndex.level))
                    Text(recoveryIndex.headline.capitalized)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    HStack {
                        Text(L10n.tr("Качество процесса"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("\(sessionProcessScore)/100")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(levelColor(sessionProcessScore >= 75 ? .low : (sessionProcessScore >= 50 ? .medium : .high)))
                    }
                    ProgressView(value: Double(sessionProcessScore) / 100)
                        .tint(levelColor(sessionProcessScore >= 75 ? .low : (sessionProcessScore >= 50 ? .medium : .high)))
                    Text(sessionProcessHint)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(improvementWindowText)
                        .foregroundStyle(.secondary)
                    Text(personalizedSummary)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.thinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 14))

                VStack(alignment: .leading, spacing: 8) {
                    Text("Персональные факторы")
                        .font(.headline)
                    ForEach(personalizedFactors, id: \.title) { factor in
                        HStack(alignment: .top) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(factor.title)
                                    .font(.subheadline.weight(.semibold))
                                Text(factor.hint)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(factor.value)
                                .font(.subheadline.weight(.semibold))
                        }
                        Divider()
                    }
                    Text("Оценка приблизительная и не является медицинским заключением.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.thinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 14))

                if !healthCorrelationInsights.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(L10n.tr("Health-корреляции по вашей истории"))
                            .font(.headline)
                        ForEach(healthCorrelationInsights, id: \.self) { insight in
                            Text("• \(insight)")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.thinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                }

                if !recentHistorySessions.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Сравнение с вашей историей")
                            .font(.headline)
                        comparisonRow(
                            title: "Ваш средний пик BAC",
                            value: baselinePeakBAC.map { String(format: "%.3f", $0) } ?? "Нет данных"
                        )
                        comparisonRow(
                            title: "Ваш средний чек-ин",
                            value: baselineWellbeing.map { String(format: "%.1f/5", $0) } ?? "Нет данных"
                        )
                        comparisonRow(
                            title: "Гидратация сегодня",
                            value: "\(Int((currentHydrationProgress * 100).rounded()))%"
                        )
                        ForEach(historyComparisonInsights, id: \.self) { line in
                            Text("• \(line)")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.thinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Персональные пороги риска")
                        .font(.headline)
                    comparisonRow(
                        title: "Порог peak BAC",
                        value: String(format: "%.3f", patternAssessment.peakRiskThreshold)
                    )
                    comparisonRow(
                        title: "Порог памяти (peak BAC)",
                        value: String(format: "%.3f", patternAssessment.memoryRiskThreshold)
                    )
                    comparisonRow(
                        title: "Порог темпа",
                        value: String(format: "%.1f ст.др./ч", patternAssessment.paceRiskThreshold)
                    )
                    comparisonRow(
                        title: "Личный ориентир гидратации",
                        value: "\(Int((patternAssessment.hydrationGoalProgress * 100).rounded()))%"
                    )
                    HStack(spacing: 8) {
                        trendBadge(title: "Тренд peak BAC", direction: patternAssessment.peakTrend)
                        trendBadge(title: "Тренд воды", direction: patternAssessment.hydrationTrend)
                    }
                    if let wellbeingTrend = patternAssessment.wellbeingTrend {
                        trendBadge(title: "Тренд чек-ина", direction: wellbeingTrend)
                    }
                    Text(L10n.format("Серия воды: %d · Серия еды: %d", patternAssessment.waterStreak, patternAssessment.mealStreak))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.thinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 14))

                if let checkIn = session.morningCheckIn {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Ваш утренний чек-ин")
                            .font(.headline)
                        Text("Самочувствие: \(checkIn.wellbeingScore)/5")
                        if !checkIn.symptoms.isEmpty {
                            Text("Симптомы: \(checkIn.symptoms.map { $0.label }.joined(separator: ", "))")
                        }
                        if let sleep = checkIn.sleepHours {
                            Text("Сон: \(sleep, format: .number) ч")
                        }
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.thinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("План восстановления")
                        .font(.headline)
                    ForEach(recoveryActions, id: \.self) { action in
                        Text("• \(action)")
                            .foregroundStyle(.secondary)
                    }
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.thinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 14))

                VStack(alignment: .leading, spacing: 8) {
                    Text(L10n.tr("План восстановления (2-4ч)"))
                        .font(.headline)
                    Text("Отмечайте шаги по мере выполнения, чтобы мягче пройти восстановление.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    ForEach(recoveryChecklist) { item in
                        Button {
                            toggleRecoveryTask(item.id)
                        } label: {
                            HStack {
                                Image(systemName: item.isDone ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(item.isDone ? .green : .secondary)
                                Text(item.title)
                                    .foregroundStyle(.primary)
                                Spacer()
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.thinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 14))

                VStack(alignment: .leading, spacing: 6) {
                    Text("Почему такой прогноз")
                        .font(.headline)
                    ForEach(assessment.morningReasons + Array(assessment.memoryReasons.prefix(1)), id: \.self) { reason in
                        Text("• \(reason)")
                            .foregroundStyle(.secondary)
                    }
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.thinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 14))

                if !assessment.riskEvents.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("События, повлиявшие на прогноз")
                            .font(.headline)
                        ForEach(assessment.riskEvents.prefix(4)) { event in
                            VStack(alignment: .leading, spacing: 3) {
                                HStack {
                                    Text(event.title)
                                        .font(.subheadline.weight(.semibold))
                                    Spacer()
                                    Text(event.date, style: .time)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                                Text(event.detail)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(levelColor(event.severity).opacity(0.10))
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                        }
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.thinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                }

                Text("Оценка приблизительная, не медицинская. Не использовать для решения, можно ли водить.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding()
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        showGlossaryTooltip.toggle()
                    }
                } label: {
                    Image(systemName: "questionmark.circle")
                }
                .accessibilityLabel("Подсказки по терминам")
            }
        }
        .overlay(alignment: .topTrailing) {
            if showGlossaryTooltip {
                GlossaryTooltipView {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        showGlossaryTooltip = false
                    }
                    showGlossarySheet = true
                }
                .padding(.top, 8)
                .padding(.trailing, 12)
                .transition(.scale(scale: 0.96, anchor: .topTrailing).combined(with: .opacity))
                .zIndex(3)
            }
        }
        .sheet(isPresented: $showGlossarySheet) {
            GlossaryView()
        }
        .task(id: session.id) {
            loadRecoveryChecklist()
            await loadHealthDataIfNeeded()
        }
    }

    private func riskBadge(title: String, level: InsightLevel, percent: Int) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(level.title.capitalized)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(levelColor(level))
            Text("~\(percent)%")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(levelColor(level).opacity(0.10))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private func levelColor(_ level: InsightLevel) -> Color {
        switch level {
        case .low:
            return .green
        case .medium:
            return .orange
        case .high:
            return .red
        }
    }

    private func hydrationProgress(for session: Session) -> Double {
        insightService.assess(session: session, profile: profile).waterBalance.progress
    }

    private func recoveryDate(for session: Session) -> Date {
        let calendar = Calendar.current
        let startDay = calendar.startOfDay(for: session.startAt)
        return calendar.date(byAdding: .day, value: 1, to: startDay) ?? startDay
    }

    private func comparisonRow(title: String, value: String) -> some View {
        HStack {
            Text(title)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.subheadline.weight(.semibold))
        }
    }

    private func trendBadge(title: String, direction: TrendDirection) -> some View {
        HStack(spacing: 6) {
            Image(systemName: trendIcon(direction))
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(direction.title.capitalized)
                    .font(.caption.weight(.semibold))
            }
            Spacer()
        }
        .padding(8)
        .background(trendColor(direction).opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private func trendIcon(_ direction: TrendDirection) -> String {
        switch direction {
        case .improving: return "arrow.down.right"
        case .worsening: return "arrow.up.right"
        case .stable: return "equal"
        }
    }

    private func trendColor(_ direction: TrendDirection) -> Color {
        switch direction {
        case .improving: return .green
        case .worsening: return .red
        case .stable: return .orange
        }
    }

    private func loadHealthDataIfNeeded() async {
        guard !loadedHealthData else { return }
        loadedHealthData = true
        let targetDay = recoveryDate(for: session)
        deriveHealthFromSnapshots(for: targetDay)

        if healthStepCount == nil {
            healthStepCount = await HealthKitService.shared.fetchStepCount(on: targetDay)
        }
        if healthRestingHR == nil {
            healthRestingHR = await HealthKitService.shared.fetchRestingHeartRate(on: targetDay)
        }
        if healthHRV == nil {
            healthHRV = await HealthKitService.shared.fetchHrvSdnn(on: targetDay)
        }
        if healthSleepHours == nil {
            healthSleepHours = await HealthKitService.shared.fetchLastNightSleepHours()
        }
        loadRecoveryChecklist()
    }

    private func deriveHealthFromSnapshots(for day: Date) {
        let calendar = Calendar.current
        guard let snapshot = healthSnapshots.first(where: { calendar.isDate($0.day, inSameDayAs: day) }) else { return }
        if let steps = snapshot.steps { healthStepCount = steps }
        if let rhr = snapshot.restingHeartRate { healthRestingHR = rhr }
        if let hrv = snapshot.hrvSdnn { healthHRV = hrv }
        if let minutes = snapshot.sleepMinutes { healthSleepHours = minutes / 60.0 }
        if let efficiency = snapshot.sleepEfficiency { healthSleepEfficiency = efficiency }
    }

    private func loadRecoveryChecklist() {
        let tasks = suggestedRecoveryTasks()
        recoveryChecklist = tasks.map { title in
            let taskID = taskIdentifier(for: title)
            let key = recoveryStateKey(taskID)
            let isDone = UserDefaults.standard.bool(forKey: key)
            return RecoveryChecklistItem(id: taskID, title: title, isDone: isDone)
        }
    }

    private func toggleRecoveryTask(_ id: String) {
        guard let index = recoveryChecklist.firstIndex(where: { $0.id == id }) else { return }
        recoveryChecklist[index].isDone.toggle()
        UserDefaults.standard.set(recoveryChecklist[index].isDone, forKey: recoveryStateKey(id))
    }

    private func suggestedRecoveryTasks() -> [String] {
        var tasks: [String] = []
        if assessment.waterBalance.deficitMl > 0 {
            tasks.append(L10n.format("Выпить ~%d мл воды в течение часа", assessment.waterBalance.suggestedTopUpMl))
        } else {
            tasks.append(L10n.tr("Поддерживать воду небольшими порциями"))
        }

        tasks.append(L10n.tr("Съесть легкую еду с углеводами и белком"))
        tasks.append(L10n.tr("Сделать спокойный режим на 2-4 часа"))

        if let healthSleepHours, healthSleepHours < 6 {
            tasks.append(L10n.tr("Добавить короткий дневной отдых 20-30 минут"))
        }
        if assessment.memoryRisk != .low {
            tasks.append(L10n.tr("Проверить важные сообщения/планы, если память фрагментарна"))
        }
        if let healthStepCount, healthStepCount >= 12000 {
            tasks.append(L10n.tr("Избегать дополнительной интенсивной активности"))
        }

        var unique: [String] = []
        for task in tasks where !unique.contains(task) {
            unique.append(task)
        }
        return Array(unique.prefix(5))
    }

    private func taskIdentifier(for task: String) -> String {
        String(task.unicodeScalars.map { CharacterSet.alphanumerics.contains($0) ? Character($0) : "_" })
    }

    private func recoveryStateKey(_ id: String) -> String {
        "recovery.task.\(session.id.uuidString).\(id)"
    }
}
