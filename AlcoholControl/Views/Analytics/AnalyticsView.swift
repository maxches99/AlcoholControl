import SwiftUI
import SwiftData
import UIKit

struct AnalyticsView: View {
    @Query(sort: [SortDescriptor<Session>(\.startAt, order: .reverse)]) private var sessions: [Session]
    @Query private var profiles: [UserProfile]
    @StateObject private var purchase = PurchaseService.shared
    @State private var syncedRecoverySteps: [UUID: Int] = [:]
    @State private var stepSyncStatus = ""
    @State private var syncingSteps = false
    @State private var showingPaywall = false
    @State private var showingHabits = false
    @State private var weeklySummaryCopied = false
    @State private var generatedWeeklySummaryText: String?
    @State private var weeklySummaryLoading = false
    @AppStorage("weeklyHeavyMorningLimit") private var weeklyHeavyMorningLimit = 2
    @AppStorage("weeklyHighMemoryRiskLimit") private var weeklyHighMemoryRiskLimit = 2
    @AppStorage("weeklyHydrationHitTarget") private var weeklyHydrationHitTarget = 70
    private let insightService = SessionInsightService()
    private let weeklySummaryNarrativeService = WeeklySummaryNarrativeService()

    init() {
        _sessions = Query(sort: [SortDescriptor<Session>(\.startAt, order: .reverse)])
        _profiles = Query()
    }

    private var recentSessions: [Session] {
        Array(sessions.prefix(7).reversed())
    }

    private var profile: UserProfile? { profiles.first }
    private let calendar = Calendar.current

    private var completedSessions: [Session] {
        sessions
            .filter { !$0.isActive }
            .sorted(by: { $0.startAt > $1.startAt })
    }

    private var trendSessions: [Session] {
        Array(completedSessions.prefix(7).reversed())
    }

    private var weekSessions: [Session] {
        let start = Calendar.current.date(byAdding: .day, value: -7, to: .now) ?? .now
        return sessions
            .filter { !$0.isActive && $0.startAt >= start }
            .sorted(by: { $0.startAt > $1.startAt })
    }

    private var avgPeakBAC: Double {
        let values = sessions.prefix(10).map(\.cachedPeakBAC).filter { $0 > 0 }
        guard !values.isEmpty else { return 0 }
        return values.reduce(0, +) / Double(values.count)
    }

    private var avgWaterMarks: Double {
        let values = sessions.prefix(10).map { Double($0.waters.count) }
        guard !values.isEmpty else { return 0 }
        return values.reduce(0, +) / Double(values.count)
    }

    private var latestCompletedSession: Session? {
        sessions.first(where: { !$0.isActive })
    }

    private var personalizedPattern: PersonalizedPatternAssessment? {
        guard let latestCompletedSession else { return nil }
        return insightService.personalizedPatterns(
            current: latestCompletedSession,
            history: sessions,
            profile: profile
        )
    }

    private var hydrationGoalProgress: Double {
        personalizedPattern?.hydrationGoalProgress ?? 0.8
    }

    private var hydrationHits: Int {
        weekSessions.filter { session in
            insightService.assess(session: session, profile: profile).waterBalance.progress >= hydrationGoalProgress
        }.count
    }

    private var mealHits: Int {
        weekSessions.filter { !$0.meals.isEmpty }.count
    }

    private var paceHits: Int {
        let threshold = personalizedPattern?.paceRiskThreshold ?? 1.6
        return weekSessions.filter { averagePace(for: $0) <= threshold }.count
    }

    private var weeklyGoalTarget: Int {
        max(4, min(7, weekSessions.count))
    }

    private var weeklySnapshot: WeeklyInsightSnapshot {
        insightService.weeklySnapshot(sessions: sessions, profile: profile)
    }

    private var recoveryStepValues: [Int] {
        weekSessions.compactMap { syncedRecoverySteps[$0.id] }
    }

    private var averageRecoverySteps: Int? {
        guard !recoveryStepValues.isEmpty else { return nil }
        return Int((Double(recoveryStepValues.reduce(0, +)) / Double(recoveryStepValues.count)).rounded())
    }

    private var lowActivityRecoveryCount: Int {
        weekSessions.filter { session in
            guard let steps = syncedRecoverySteps[session.id] else { return false }
            return steps < 5000
        }.count
    }

    private var stepCoveragePercent: Int {
        guard !weekSessions.isEmpty else { return 0 }
        return Int((Double(recoveryStepValues.count) / Double(weekSessions.count) * 100).rounded())
    }

    private var triggerPatterns: TriggerPatternsSummary {
        insightService.triggerPatterns(sessions: sessions, profile: profile)
    }

    private var trendSnapshots: [TrendSnapshot] {
        trendSessions.map { session in
            let recoveryDay = recoveryDate(for: session)
            let healthContext = SessionHealthContext(
                sleepHours: session.morningCheckIn?.sleepHours,
                stepCount: HealthKitService.shared.cachedStepCount(on: recoveryDay),
                restingHeartRate: HealthKitService.shared.cachedRestingHeartRate(on: recoveryDay),
                hrvSdnn: nil,
                sleepEfficiency: nil
            )
            let assessment = insightService.assess(
                session: session,
                profile: profile,
                at: session.endAt ?? .now,
                health: healthContext,
                history: sessions
            )
            let recovery = insightService.recoveryIndex(
                session: session,
                assessment: assessment,
                health: healthContext,
                baselines: nil
            )
            return TrendSnapshot(
                id: session.id,
                date: session.startAt,
                recoveryScore: recovery.score,
                recoveryLevel: recovery.level,
                morningRiskPercent: assessment.morningProbabilityPercent,
                morningRiskLevel: assessment.morningRisk,
                memoryRiskPercent: assessment.memoryProbabilityPercent,
                memoryRiskLevel: assessment.memoryRisk,
                hydrationDeficitMl: assessment.waterBalance.deficitMl
            )
        }
    }

    private var averageHydrationDeficitMl: Int {
        guard !trendSnapshots.isEmpty else { return 0 }
        let total = trendSnapshots.reduce(0) { $0 + $1.hydrationDeficitMl }
        return Int((Double(total) / Double(trendSnapshots.count)).rounded())
    }

    private var mealTimingHits: Int {
        trendSessions.filter(hasMealNearFirstDrink).count
    }

    private var safeSessionStreak: Int {
        var streak = 0
        for item in trendSnapshots.reversed() {
            if item.morningRiskLevel != .high && item.memoryRiskLevel != .high {
                streak += 1
            } else {
                break
            }
        }
        return streak
    }

    private var recoveryLoadScore: Int {
        let heavyPenalty = weeklySnapshot.heavyMorningCount * 20
        let memoryPenalty = weeklySnapshot.highMemoryRiskCount * 18
        let hydrationPenalty = min(24, averageHydrationDeficitMl / 25)
        return max(0, 100 - heavyPenalty - memoryPenalty - hydrationPenalty)
    }

    private var processQualityScore: Int {
        guard !weekSessions.isEmpty else { return 0 }
        let hydrationPart = Int((Double(weeklySnapshot.hydrationHitRatePercent) * 0.45).rounded())
        let mealPart = Int((Double(mealTimingHits) / Double(max(1, trendSessions.count)) * 35).rounded())
        let pacePart = Int((Double(paceHits) / Double(max(1, weekSessions.count)) * 20).rounded())
        return min(100, hydrationPart + mealPart + pacePart)
    }

    private var weeklyFocusText: String {
        if weeklySnapshot.highMemoryRiskCount > weeklyHighMemoryRiskLimit {
            return L10n.tr("Главный фокус недели: снизить high memory-risk сессии. Снизьте темп и крепость после середины вечера.")
        }
        if weeklySnapshot.hydrationHitRatePercent < weeklyHydrationHitTarget {
            return L10n.tr("Главный фокус недели: гидратация. Добавляйте воду раньше и чаще, чтобы выйти на целевой процент.")
        }
        if mealTimingHits < max(2, trendSessions.count / 2) {
            return L10n.tr("Главный фокус недели: время еды. Старайтесь отмечать прием пищи до первого напитка или в первые 30 минут.")
        }
        if weeklySnapshot.heavyMorningCount > weeklyHeavyMorningLimit {
            return L10n.tr("Главный фокус недели: сократить тяжелые утра. Планируйте более раннее завершение сессий.")
        }
        return L10n.tr("Фокус недели: удерживать текущий режим. По вашим данным тренд выглядит стабильным.")
    }

    private var weeklySummaryInput: WeeklySummaryNarrativeInput {
        WeeklySummaryNarrativeInput(
            heavyMorningCount: weeklySnapshot.heavyMorningCount,
            highMemoryRiskCount: weeklySnapshot.highMemoryRiskCount,
            hydrationHitRatePercent: weeklySnapshot.hydrationHitRatePercent,
            processQualityScore: processQualityScore,
            recoveryLoadScore: recoveryLoadScore,
            weeklyFocusText: weeklyFocusText
        )
    }

    private var weeklySummaryFallbackText: String {
        weeklySummaryNarrativeService.fallbackSummary(for: weeklySummaryInput)
    }

    private var weeklySummaryText: String {
        generatedWeeklySummaryText ?? weeklySummaryFallbackText
    }

    private var usesAISummaryText: Bool {
        generatedWeeklySummaryText != nil
    }

    private var weeklySummarySignature: String {
        [
            "\(weeklySummaryInput.heavyMorningCount)",
            "\(weeklySummaryInput.highMemoryRiskCount)",
            "\(weeklySummaryInput.hydrationHitRatePercent)",
            "\(weeklySummaryInput.processQualityScore)",
            "\(weeklySummaryInput.recoveryLoadScore)",
            weeklySummaryInput.weeklyFocusText
        ].joined(separator: "|")
    }

    private var heavyMorningStatus: (ok: Bool, text: String) {
        let isOK = weeklySnapshot.heavyMorningCount <= weeklyHeavyMorningLimit
        let text = L10n.format(
            "Тяжелые утра: %d / лимит %d",
            weeklySnapshot.heavyMorningCount,
            weeklyHeavyMorningLimit
        )
        return (isOK, text)
    }

    private var memoryRiskStatus: (ok: Bool, text: String) {
        let isOK = weeklySnapshot.highMemoryRiskCount <= weeklyHighMemoryRiskLimit
        let text = L10n.format(
            "Высокий риск памяти: %d / лимит %d",
            weeklySnapshot.highMemoryRiskCount,
            weeklyHighMemoryRiskLimit
        )
        return (isOK, text)
    }

    private var hydrationStatus: (ok: Bool, text: String) {
        let isOK = weeklySnapshot.hydrationHitRatePercent >= weeklyHydrationHitTarget
        let text = L10n.format(
            "Гидратация: %d%% / цель %d%%",
            weeklySnapshot.hydrationHitRatePercent,
            weeklyHydrationHitTarget
        )
        return (isOK, text)
    }

    private var weekInterval: DateInterval {
        let end = calendar.startOfDay(for: .now)
        let start = calendar.date(byAdding: .day, value: -6, to: end) ?? end
        return DateInterval(start: start, end: end)
    }

    private var weekdayUnitItems: [WeekdayUnits] {
        (0..<7).compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: offset, to: weekInterval.start) else { return nil }
            let start = calendar.startOfDay(for: day)
            guard let end = calendar.date(byAdding: .day, value: 1, to: start) else { return nil }
            let units = weekSessions
                .filter { session in
                    session.startAt >= start && session.startAt < end
                }
                .reduce(0.0) { partial, session in
                    partial + standardUnits(in: session)
                }
            return WeekdayUnits(
                id: offset,
                label: weekdayLabel(for: start),
                units: units
            )
        }
    }

    private var averageWeeklyUnits: Double {
        guard !weekdayUnitItems.isEmpty else { return 0 }
        return weekdayUnitItems.reduce(0, { $0 + $1.units }) / Double(weekdayUnitItems.count)
    }

    private var averageCheckInText: String {
        weeklySnapshot.averageWellbeingScore.map { String(format: "%.1f/5", $0) } ?? L10n.tr("Нет")
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    heroCard
                    if purchase.isPremium {
                        premiumContent
                    } else {
                        lockedContent
                    }
                }
                .padding()
            }
            .background(
                LinearGradient(
                    colors: [
                        Color(red: 0.06, green: 0.08, blue: 0.08),
                        Color(red: 0.08, green: 0.10, blue: 0.10),
                        Color(red: 0.05, green: 0.08, blue: 0.07)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()
            )
            .tint(AppDesign.Colors.primary)
            .navigationTitle(L10n.tr("Аналитика"))
            .sheet(isPresented: $showingPaywall) {
                PaywallView()
            }
            .sheet(isPresented: $showingHabits) {
                if let pattern = personalizedPattern {
                    PremiumHabitsView(
                        weekSessionsCount: weekSessions.count,
                        goalTarget: weeklyGoalTarget,
                        hydrationHits: hydrationHits,
                        hydrationGoalProgress: hydrationGoalProgress,
                        mealHits: mealHits,
                        paceHits: paceHits,
                        pattern: pattern
                    )
                } else {
                    PremiumHabitsView(
                        weekSessionsCount: weekSessions.count,
                        goalTarget: weeklyGoalTarget,
                        hydrationHits: hydrationHits,
                        hydrationGoalProgress: hydrationGoalProgress,
                        mealHits: mealHits,
                        paceHits: paceHits,
                        pattern: nil
                    )
                }
            }
            .task {
                await purchase.loadProducts()
                await purchase.restore()
                loadCachedRecoverySteps()
            }
            .onChange(of: sessions.count) { _, _ in
                loadCachedRecoverySteps()
            }
            .task(id: weeklySummarySignature) {
                await refreshWeeklySummaryText()
            }
        }
    }

    private var heroCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(L10n.tr("Weekly safety digest"))
                        .font(.system(.title2, design: .rounded).weight(.bold))
                        .foregroundStyle(.white)
                    Text(weekInterval.start..<weekInterval.end, format: .interval.month(.abbreviated).day())
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.72))
                }
                Spacer()
                Image(systemName: "calendar")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.82))
                    .padding(12)
                    .background(Color.black.opacity(0.15))
                    .clipShape(Circle())
            }

            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Image(systemName: "checkmark.circle")
                    Text(weeklySnapshot.headline)
                }
                .font(.headline.weight(.semibold))
                .foregroundStyle(Color(red: 0.36, green: 0.44, blue: 0.36))
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Color.white.opacity(0.86))
                .clipShape(Capsule())

                HStack(spacing: 10) {
                    metricChip(
                        title: L10n.tr("Ср. peak BAC"),
                        value: avgPeakBAC > 0 ? String(format: "%.3f", avgPeakBAC) : L10n.tr("Нет")
                    )
                    metricChip(title: L10n.tr("Ср. вода"), value: String(format: "%.1f", avgWaterMarks))
                    metricChip(title: L10n.tr("Сессий"), value: "\(sessions.count)")
                }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(
                colors: [
                    Color(red: 0.63, green: 0.69, blue: 0.60),
                    Color(red: 0.58, green: 0.65, blue: 0.56)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .overlay(alignment: .trailing) {
            Circle()
                .fill(Color.white.opacity(0.16))
                .frame(width: 190, height: 190)
                .offset(x: 70, y: 20)
        }
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
    }

    private var premiumContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(L10n.tr("Premium аналитика"))
                .font(.system(.title3, design: .rounded).weight(.bold))
                .foregroundStyle(.white)

            analyticsCard {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(L10n.tr("Распределение напитков"))
                                .font(.headline)
                                .foregroundStyle(.white)
                            Text(L10n.tr("Сессий (7д)"))
                                .font(.subheadline)
                                .foregroundStyle(.white.opacity(0.66))
                        }
                        Spacer()
                        Text(L10n.format("Avg: %.1f", averageWeeklyUnits))
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color.black.opacity(0.28))
                            .clipShape(Capsule())
                    }

                    let maxUnits = max(1.0, weekdayUnitItems.map(\.units).max() ?? 1)
                    HStack(alignment: .bottom, spacing: 12) {
                        ForEach(weekdayUnitItems) { item in
                            VStack(spacing: 8) {
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(Color(red: 0.82, green: 0.64, blue: 0.66))
                                    .frame(height: max(6, 140 * (item.units / maxUnits)))
                                Text(item.label)
                                    .font(.caption)
                                    .foregroundStyle(.white.opacity(0.7))
                            }
                            .frame(maxWidth: .infinity)
                        }
                    }
                    .frame(height: 168, alignment: .bottom)

                    VStack(alignment: .leading, spacing: 8) {
                        Text(L10n.tr("Пик BAC по сессиям"))
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.9))

                        if recentSessions.isEmpty {
                            Text(L10n.tr("Пока нет данных для графика"))
                                .font(.caption)
                                .foregroundStyle(.white.opacity(0.66))
                        } else {
                            ForEach(recentSessions) { session in
                                HStack(spacing: 8) {
                                    Text(session.startAt, format: .dateTime.month().day())
                                        .font(.caption)
                                        .foregroundStyle(.white.opacity(0.7))
                                        .frame(width: 48, alignment: .leading)
                                    GeometryReader { proxy in
                                        let width = max(6, proxy.size.width * min(1, session.cachedPeakBAC / 0.20))
                                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                                            .fill(Color(red: 0.44, green: 0.62, blue: 0.92))
                                            .frame(width: width, height: 8)
                                    }
                                    .frame(height: 8)
                                    Text(String(format: "%.3f", session.cachedPeakBAC))
                                        .font(.caption2)
                                        .foregroundStyle(.white.opacity(0.7))
                                }
                                .frame(height: 14)
                            }
                        }
                    }
                }
            }

            HStack(spacing: 12) {
                dashboardMiniCard(
                    title: L10n.tr("Гидратация"),
                    value: "\(weeklySnapshot.hydrationHitRatePercent)%",
                    subtitle: L10n.tr("Hydration hit rate")
                )
                dashboardMiniCard(
                    title: L10n.tr("Avg check-in"),
                    value: averageCheckInText,
                    subtitle: L10n.tr("Weekly safety digest")
                )
            }

            analyticsCard {
                VStack(alignment: .leading, spacing: 10) {
                    Text(L10n.tr("Вода по сессиям"))
                        .font(.headline)
                        .foregroundStyle(.white)

                    ForEach(recentSessions) { session in
                        HStack {
                            Text(session.startAt, format: .dateTime.month().day())
                                .foregroundStyle(.white.opacity(0.78))
                            Spacer()
                            Text(L10n.format("%d отметок воды", session.waters.count))
                                .foregroundStyle(.white.opacity(0.66))
                        }
                        .font(.subheadline)
                    }
                }
            }

            analyticsCard {
                VStack(alignment: .leading, spacing: 10) {
                    Text(L10n.tr("Weekly safety digest"))
                        .font(.headline)
                        .foregroundStyle(.white)
                    HStack(spacing: 8) {
                        metricChip(title: L10n.tr("Heavy mornings"), value: "\(weeklySnapshot.heavyMorningCount)")
                        metricChip(title: L10n.tr("High memory risk"), value: "\(weeklySnapshot.highMemoryRiskCount)")
                    }
                    HStack(spacing: 8) {
                        metricChip(title: L10n.tr("Hydration hit rate"), value: "\(weeklySnapshot.hydrationHitRatePercent)%")
                        metricChip(title: L10n.tr("Meal coverage"), value: "\(weeklySnapshot.mealCoveragePercent)%")
                    }
                    HStack(spacing: 8) {
                        metricChip(title: L10n.tr("Avg peak"), value: weeklySnapshot.averagePeakBAC > 0 ? String(format: "%.3f", weeklySnapshot.averagePeakBAC) : L10n.tr("Нет"))
                        metricChip(title: L10n.tr("Avg check-in"), value: averageCheckInText)
                    }
                }
            }

            analyticsCard {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text(L10n.tr("Шаги восстановления (Apple Health)"))
                            .font(.headline)
                            .foregroundStyle(.white)
                        Spacer()
                        if syncingSteps {
                            ProgressView()
                                .controlSize(.small)
                                .tint(.white.opacity(0.9))
                        }
                    }

                    metricChip(
                        title: L10n.tr("Среднее шагов"),
                        value: averageRecoverySteps.map { "\($0)" } ?? L10n.tr("Нет")
                    )
                    metricChip(title: L10n.tr("Покрытие шагов"), value: "\(stepCoveragePercent)%")
                    metricChip(title: L10n.tr("Низкая активность"), value: "\(lowActivityRecoveryCount)")
                    metricChip(title: L10n.tr("Сессий (7д)"), value: "\(weekSessions.count)")

                    Button(syncingSteps ? L10n.tr("Синхронизация...") : L10n.tr("Синхронизировать шаги")) {
                        Task { await syncRecoveryStepsFromHealth() }
                    }
                    .buttonStyle(.bordered)
                    .tint(.white)
                    .disabled(syncingSteps)

                    if !stepSyncStatus.isEmpty {
                        Text(stepSyncStatus)
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.66))
                    }
                }
            }

            analyticsCard {
                VStack(alignment: .leading, spacing: 10) {
                    Text(L10n.tr("Паттерны триггеров"))
                        .font(.system(.title3, design: .rounded).weight(.bold))
                        .foregroundStyle(.white)
                    limitRow(heavyMorningStatus)
                    limitRow(memoryRiskStatus)
                    limitRow(hydrationStatus)
                }
            }

            analyticsCard {
                VStack(alignment: .leading, spacing: 10) {
                    Text(L10n.tr("Тренд восстановления и рисков"))
                        .font(.headline)
                        .foregroundStyle(.white)
                    if trendSnapshots.isEmpty {
                        Text(L10n.tr("Пока нет завершенных сессий для тренда"))
                            .foregroundStyle(.white.opacity(0.66))
                    } else {
                        ForEach(trendSnapshots) { item in
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Text(item.date, format: .dateTime.month().day())
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(.white.opacity(0.84))
                                    Spacer()
                                    Text(L10n.format("Recovery %d/100", item.recoveryScore))
                                        .font(.caption)
                                        .foregroundStyle(.white.opacity(0.66))
                                }
                                trendLine(
                                    title: L10n.tr("Recovery"),
                                    value: Double(item.recoveryScore) / 100,
                                    tint: levelColor(item.recoveryLevel)
                                )
                                trendLine(
                                    title: L10n.tr("Morning risk"),
                                    value: Double(item.morningRiskPercent) / 100,
                                    tint: levelColor(item.morningRiskLevel)
                                )
                                trendLine(
                                    title: L10n.tr("Memory risk"),
                                    value: Double(item.memoryRiskPercent) / 100,
                                    tint: levelColor(item.memoryRiskLevel)
                                )
                            }
                            .padding(10)
                            .background(Color.white.opacity(0.06))
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                    }
                }
            }

            analyticsCard {
                VStack(alignment: .leading, spacing: 10) {
                    Text(L10n.tr("Качество процесса вечера"))
                        .font(.headline)
                        .foregroundStyle(.white)
                    HStack(spacing: 8) {
                        metricChip(title: L10n.tr("Process quality"), value: "\(processQualityScore)/100")
                        metricChip(title: L10n.tr("Recovery load"), value: "\(recoveryLoadScore)/100")
                    }
                    HStack(spacing: 8) {
                        metricChip(title: L10n.tr("Avg water deficit"), value: "\(averageHydrationDeficitMl) ml")
                        metricChip(title: L10n.tr("Meal timing"), value: "\(mealTimingHits)/\(trendSessions.count)")
                    }
                    HStack(spacing: 8) {
                        metricChip(title: L10n.tr("Safe streak"), value: "\(safeSessionStreak)")
                        metricChip(title: L10n.tr("Pace hits"), value: "\(paceHits)/\(weekSessions.count)")
                    }
                    Text(weeklyFocusText)
                        .font(.footnote)
                        .foregroundStyle(.white.opacity(0.66))
                }
            }

            analyticsCard(tint: Color(red: 0.83, green: 0.79, blue: 0.68).opacity(0.2)) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 8) {
                        Text(L10n.tr("Shareable weekly summary"))
                            .font(.headline)
                            .foregroundStyle(.white)
                        if usesAISummaryText {
                            Text(L10n.tr("AI"))
                                .font(.caption2.weight(.semibold))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(Color.white.opacity(0.14))
                                .clipShape(Capsule())
                                .foregroundStyle(.white)
                        }
                    }
                    if weeklySummaryLoading {
                        Text(L10n.tr("Формируем персональное пояснение..."))
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.66))
                    }
                    Text(weeklySummaryText)
                        .font(.footnote)
                        .foregroundStyle(.white.opacity(0.8))
                    Button(weeklySummaryCopied ? L10n.tr("Скопировано") : L10n.tr("Скопировать summary")) {
                        copyWeeklySummary()
                    }
                    .buttonStyle(.bordered)
                    .tint(.white)
                }
            }

            if !triggerPatterns.hits.isEmpty {
                analyticsCard {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(L10n.tr("Паттерны триггеров"))
                            .font(.headline)
                            .foregroundStyle(.white)
                        Text(L10n.tr("Паттерны, которые чаще ведут к тяжелому утру или риску памяти."))
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.66))
                        ForEach(triggerPatterns.hits) { hit in
                            VStack(alignment: .leading, spacing: 3) {
                                HStack {
                                    Text(hit.title)
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(.white.opacity(0.9))
                                    Spacer()
                                    Text(hit.value)
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(.white)
                                }
                                Text(hit.impact)
                                    .font(.caption)
                                    .foregroundStyle(.white.opacity(0.66))
                            }
                            .padding(10)
                            .background(Color.white.opacity(0.05))
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                    }
                }
            }

            if let personalizedPattern {
                analyticsCard {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(L10n.tr("Персональные паттерны"))
                            .font(.headline)
                            .foregroundStyle(.white)
                        HStack(spacing: 8) {
                            trendChip(title: L10n.tr("Пик BAC"), direction: personalizedPattern.peakTrend)
                            trendChip(title: L10n.tr("Гидратация"), direction: personalizedPattern.hydrationTrend)
                        }
                        if let wellbeingTrend = personalizedPattern.wellbeingTrend {
                            trendChip(title: L10n.tr("Чек-ин"), direction: wellbeingTrend)
                        }
                        Text(L10n.format("Серия воды: %d · Серия еды: %d", personalizedPattern.waterStreak, personalizedPattern.mealStreak))
                            .font(.footnote)
                            .foregroundStyle(.white.opacity(0.66))
                        ForEach(personalizedPattern.notes, id: \.self) { note in
                            Text("• \(note)")
                                .font(.footnote)
                                .foregroundStyle(.white.opacity(0.75))
                        }
                    }
                }
            }

            Button(L10n.tr("Открыть Premium: Привычки")) {
                showingHabits = true
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private var lockedContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(L10n.tr("Premium аналитика"))
                .font(.title2.weight(.bold))
                .foregroundStyle(.white)

            Text(L10n.tr("Откройте детальные тренды BAC, динамику воды и персональные паттерны."))
                .foregroundStyle(.white.opacity(0.7))

            lockedCard(title: L10n.tr("Пик BAC по неделям"))
            lockedCard(title: L10n.tr("Распределение напитков"))
            lockedCard(title: L10n.tr("Связь воды и самочувствия"))

            Button(L10n.tr("Открыть Paywall")) {
                showingPaywall = true
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color.white.opacity(0.09), Color.white.opacity(0.05)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
    }

    private func lockedCard(title: String) -> some View {
        Button {
            showingPaywall = true
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .foregroundStyle(.white)
                    Text(L10n.tr("Доступно в Premium"))
                        .font(.footnote)
                        .foregroundStyle(.white.opacity(0.66))
                }
                Spacer()
                Image(systemName: "lock.fill")
                    .foregroundStyle(.white.opacity(0.66))
            }
            .padding()
            .background(Color.white.opacity(0.06))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }

    private func metricChip(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.62))
            Text(value)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Color.white.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func trendLine(title: String, value: Double, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.66))
                Spacer()
                Text("\(Int((min(1, max(0, value)) * 100).rounded()))%")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.66))
            }
            ProgressView(value: min(1, max(0, value)))
                .tint(tint)
        }
    }

    private func trendChip(title: String, direction: TrendDirection) -> some View {
        HStack(spacing: 6) {
            Image(systemName: trendIcon(direction))
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.66))
                Text(direction.title.capitalized)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white)
            }
            Spacer()
        }
        .padding(10)
        .background(trendColor(direction).opacity(0.2))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func limitRow(_ status: (ok: Bool, text: String)) -> some View {
        HStack {
            Image(systemName: status.ok ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(status.ok ? .green : .orange)
            Text(status.text)
                .font(.footnote)
                .foregroundStyle(.white.opacity(0.82))
            Spacer()
        }
        .padding(10)
        .background(Color.white.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func analyticsCard<Content: View>(
        tint: Color = Color.white.opacity(0.07),
        @ViewBuilder content: () -> Content
    ) -> some View {
        content()
            .padding(18)
            .background(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [tint, Color.black.opacity(0.20)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .stroke(Color.white.opacity(0.06), lineWidth: 1)
            )
    }

    private func dashboardMiniCard(title: String, value: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
                .foregroundStyle(.white.opacity(0.66))
            Text(value)
                .font(.system(size: 48, weight: .bold, design: .rounded))
                .minimumScaleFactor(0.55)
                .lineLimit(1)
                .foregroundStyle(.white)
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.white.opacity(0.55))
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color.white.opacity(0.09), Color.white.opacity(0.04)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
    }

    private func weekdayLabel(for date: Date) -> String {
        let index = calendar.component(.weekday, from: date) - 1
        guard calendar.shortWeekdaySymbols.indices.contains(index) else { return "-" }
        return String(calendar.shortWeekdaySymbols[index].prefix(1)).uppercased()
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

    private func levelColor(_ level: InsightLevel) -> Color {
        switch level {
        case .low: return .green
        case .medium: return .orange
        case .high: return .red
        }
    }

    private func standardUnits(in session: Session) -> Double {
        session.drinks.reduce(0.0) { partial, drink in
            let grams = drink.volumeMl * (drink.abvPercent / 100) * 0.789
            return partial + (grams / 14.0)
        }
    }

    private func averagePace(for session: Session) -> Double {
        let durationHours = max(0.1, (session.endAt ?? .now).timeIntervalSince(session.startAt) / 3600)
        let standardDrinks = standardUnits(in: session)
        guard standardDrinks > 0 else { return 0 }
        return standardDrinks / durationHours
    }

    private func recoveryDate(for session: Session) -> Date {
        let startDay = calendar.startOfDay(for: session.startAt)
        return calendar.date(byAdding: .day, value: 1, to: startDay) ?? startDay
    }

    private func hasMealNearFirstDrink(_ session: Session) -> Bool {
        guard let firstDrink = session.drinks.map(\.createdAt).min() else { return false }
        return session.meals.contains { meal in
            let deltaMinutes = meal.createdAt.timeIntervalSince(firstDrink) / 60
            return (-90...30).contains(deltaMinutes)
        }
    }

    private func copyWeeklySummary() {
        UIPasteboard.general.string = weeklySummaryText
        weeklySummaryCopied = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
            weeklySummaryCopied = false
        }
    }

    @MainActor
    private func loadCachedRecoverySteps() {
        var map: [UUID: Int] = [:]
        for session in weekSessions {
            if let value = HealthKitService.shared.cachedStepCount(on: recoveryDate(for: session)) {
                map[session.id] = value
            }
        }
        syncedRecoverySteps = map
    }

    @MainActor
    private func syncRecoveryStepsFromHealth() async {
        guard HealthKitService.shared.isAvailable else {
            stepSyncStatus = L10n.tr("Apple Health недоступен на этом устройстве")
            return
        }

        let granted = await HealthKitService.shared.requestSleepAuthorization()
        guard granted else {
            stepSyncStatus = L10n.tr("Нет доступа к Apple Health.")
            return
        }

        syncingSteps = true
        defer { syncingSteps = false }

        var map = syncedRecoverySteps
        var updated = 0

        for session in weekSessions {
            if let steps = await HealthKitService.shared.fetchStepCount(on: recoveryDate(for: session)) {
                map[session.id] = steps
                updated += 1
            }
        }

        syncedRecoverySteps = map
        stepSyncStatus = L10n.format("Обновлено шагов для %d сессий.", updated)
    }

    @MainActor
    private func refreshWeeklySummaryText() async {
        generatedWeeklySummaryText = nil
        guard weeklySummaryNarrativeService.supportsFoundationModels() else {
            weeklySummaryLoading = false
            return
        }

        weeklySummaryLoading = true
        defer { weeklySummaryLoading = false }
        let summary = await weeklySummaryNarrativeService.makeSummary(for: weeklySummaryInput)
        guard !Task.isCancelled else { return }
        generatedWeeklySummaryText = summary == weeklySummaryFallbackText ? nil : summary
    }
}

private struct TrendSnapshot: Identifiable {
    let id: UUID
    let date: Date
    let recoveryScore: Int
    let recoveryLevel: InsightLevel
    let morningRiskPercent: Int
    let morningRiskLevel: InsightLevel
    let memoryRiskPercent: Int
    let memoryRiskLevel: InsightLevel
    let hydrationDeficitMl: Int
}

private struct WeekdayUnits: Identifiable {
    let id: Int
    let label: String
    let units: Double
}

private struct PremiumHabitsView: View {
    @Environment(\.dismiss) private var dismiss

    let weekSessionsCount: Int
    let goalTarget: Int
    let hydrationHits: Int
    let hydrationGoalProgress: Double
    let mealHits: Int
    let paceHits: Int
    let pattern: PersonalizedPatternAssessment?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text(L10n.tr("Привычки за неделю"))
                        .font(.title2)

                    habitCard(
                        title: L10n.tr("Гидратация"),
                        subtitle: L10n.format("Цель: >= %d%% водного баланса", Int((hydrationGoalProgress * 100).rounded())),
                        value: hydrationHits,
                        total: goalTarget,
                        tint: .blue
                    )
                    habitCard(
                        title: L10n.tr("Прием пищи"),
                        subtitle: L10n.tr("Цель: отмечать еду в сессии"),
                        value: mealHits,
                        total: goalTarget,
                        tint: .brown
                    )
                    habitCard(
                        title: L10n.tr("Умеренный темп"),
                        subtitle: L10n.tr("Цель: темп ниже персонального порога"),
                        value: paceHits,
                        total: goalTarget,
                        tint: .green
                    )

                    if let pattern {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(L10n.tr("Персональные советы"))
                                .font(.headline)
                            ForEach(pattern.actions, id: \.self) { action in
                                Text("• \(action)")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.thinMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                    }

                    Text(L10n.format("Сессий за 7 дней: %d", weekSessionsCount))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .padding()
            }
            .navigationTitle(L10n.tr("Premium Привычки"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.tr("Закрыть")) { dismiss() }
                }
            }
        }
    }

    private func habitCard(title: String, subtitle: String, value: Int, total: Int, tint: Color) -> some View {
        let safeTotal = max(1, total)
        let progress = min(1, Double(value) / Double(safeTotal))
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                    .font(.headline)
                Spacer()
                Text("\(value)/\(safeTotal)")
                    .font(.subheadline.weight(.semibold))
            }
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
            ProgressView(value: progress)
                .tint(tint)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}
