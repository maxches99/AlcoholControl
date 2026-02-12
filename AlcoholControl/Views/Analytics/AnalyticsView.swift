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
    @AppStorage("weeklyHeavyMorningLimit") private var weeklyHeavyMorningLimit = 2
    @AppStorage("weeklyHighMemoryRiskLimit") private var weeklyHighMemoryRiskLimit = 2
    @AppStorage("weeklyHydrationHitTarget") private var weeklyHydrationHitTarget = 70
    private let insightService = SessionInsightService()

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
                health: healthContext
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

    private var weeklySummaryText: String {
        L10n.format(
            "Weekly summary: heavy mornings %d, high memory-risk %d, hydration %d%%, process quality %d/100, recovery load %d/100.",
            weeklySnapshot.heavyMorningCount,
            weeklySnapshot.highMemoryRiskCount,
            weeklySnapshot.hydrationHitRatePercent,
            processQualityScore,
            recoveryLoadScore
        )
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

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    heroCard
                    if purchase.isPremium {
                        premiumContent
                    } else {
                        lockedContent
                    }
                }
                .padding()
            }
            .navigationTitle("Аналитика")
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
        }
    }

    private var heroCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Ваши тренды")
                .font(.headline)
            Text("Оценка по последним сессиям. Все значения приблизительные.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            HStack(spacing: 10) {
                metricChip(title: "Ср. peak BAC", value: avgPeakBAC > 0 ? String(format: "%.3f", avgPeakBAC) : "Нет")
                metricChip(title: "Ср. вода", value: String(format: "%.1f", avgWaterMarks))
                metricChip(title: "Сессий", value: "\(sessions.count)")
            }
            Text(weeklySnapshot.headline)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(
                colors: [.teal.opacity(0.15), .blue.opacity(0.12)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private var premiumContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Premium аналитика")
                .font(.title3.weight(.semibold))

            VStack(alignment: .leading, spacing: 10) {
                Text("Пик BAC по сессиям")
                    .font(.headline)

                if recentSessions.isEmpty {
                    Text("Пока нет данных для графика")
                        .foregroundStyle(.secondary)
                } else {
                    VStack(spacing: 8) {
                        ForEach(recentSessions) { session in
                            HStack {
                                Text(session.startAt, format: .dateTime.month().day())
                                    .font(.caption)
                                    .frame(width: 56, alignment: .leading)

                                GeometryReader { proxy in
                                    let width = max(4, proxy.size.width * min(1, session.cachedPeakBAC / 0.20))
                                    RoundedRectangle(cornerRadius: 5)
                                        .fill(.blue.opacity(0.75))
                                        .frame(width: width, height: 10)
                                }
                                .frame(height: 10)

                                Text(String(format: "%.3f", session.cachedPeakBAC))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .frame(height: 16)
                        }
                    }
                    .frame(minHeight: CGFloat(max(56, recentSessions.count * 22)))
                }
            }
            .padding()
            .background(.thinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 14))

            VStack(alignment: .leading, spacing: 10) {
                Text("Вода по сессиям")
                    .font(.headline)

                ForEach(recentSessions) { session in
                    HStack {
                        Text(session.startAt, format: .dateTime.month().day())
                        Spacer()
                        Text("\(session.waters.count) отметок воды")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding()
            .background(.thinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 14))

            VStack(alignment: .leading, spacing: 10) {
                Text(L10n.tr("Weekly safety digest"))
                .font(.headline)
                HStack(spacing: 8) {
                    metricChip(title: L10n.tr("Heavy mornings"), value: "\(weeklySnapshot.heavyMorningCount)")
                    metricChip(title: L10n.tr("High memory risk"), value: "\(weeklySnapshot.highMemoryRiskCount)")
                }
                HStack(spacing: 8) {
                    metricChip(title: L10n.tr("Hydration hit rate"), value: "\(weeklySnapshot.hydrationHitRatePercent)%")
                    metricChip(title: L10n.tr("Meal coverage"), value: "\(weeklySnapshot.mealCoveragePercent)%")
                }
                HStack(spacing: 8) {
                    metricChip(title: L10n.tr("Avg peak"), value: weeklySnapshot.averagePeakBAC > 0 ? String(format: "%.3f", weeklySnapshot.averagePeakBAC) : "Нет")
                    metricChip(
                        title: L10n.tr("Avg check-in"),
                        value: weeklySnapshot.averageWellbeingScore.map { String(format: "%.1f/5", $0) } ?? "Нет"
                    )
                }
            }
            .padding()
            .background(.thinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 14))

            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(L10n.tr("Шаги восстановления (Apple Health)"))
                        .font(.headline)
                    Spacer()
                    if syncingSteps {
                        ProgressView()
                            .controlSize(.small)
                    }
                }

                HStack(spacing: 8) {
                    metricChip(
                        title: L10n.tr("Среднее шагов"),
                        value: averageRecoverySteps.map { "\($0)" } ?? "Нет"
                    )
                    metricChip(
                        title: L10n.tr("Покрытие шагов"),
                        value: "\(stepCoveragePercent)%"
                    )
                }

                HStack(spacing: 8) {
                    metricChip(title: L10n.tr("Низкая активность"), value: "\(lowActivityRecoveryCount)")
                    metricChip(title: L10n.tr("Сессий (7д)"), value: "\(weekSessions.count)")
                }

                Button(syncingSteps ? L10n.tr("Синхронизация...") : L10n.tr("Синхронизировать шаги")) {
                    Task { await syncRecoveryStepsFromHealth() }
                }
                .buttonStyle(.bordered)
                .disabled(syncingSteps)

                if !stepSyncStatus.isEmpty {
                    Text(stepSyncStatus)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding()
            .background(.thinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 14))

            VStack(alignment: .leading, spacing: 10) {
                Text(L10n.tr("Статус недельных целей"))
                    .font(.headline)
                limitRow(heavyMorningStatus)
                limitRow(memoryRiskStatus)
                limitRow(hydrationStatus)
            }
            .padding()
            .background(.thinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 14))

            VStack(alignment: .leading, spacing: 10) {
                Text(L10n.tr("Тренд восстановления и рисков"))
                    .font(.headline)
                if trendSnapshots.isEmpty {
                    Text("Пока нет завершенных сессий для тренда")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(trendSnapshots) { item in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(item.date, format: .dateTime.month().day())
                                    .font(.caption.weight(.semibold))
                                Spacer()
                                Text(L10n.format("Recovery %d/100", item.recoveryScore))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
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
                        .padding(8)
                        .background(Color(uiColor: .secondarySystemGroupedBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                }
            }
            .padding()
            .background(.thinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 14))

            VStack(alignment: .leading, spacing: 10) {
                Text(L10n.tr("Качество процесса вечера"))
                    .font(.headline)
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
                    .foregroundStyle(.secondary)
            }
            .padding()
            .background(.thinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 14))

            VStack(alignment: .leading, spacing: 10) {
                Text(L10n.tr("Shareable weekly summary"))
                    .font(.headline)
                Text(weeklySummaryText)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Button(weeklySummaryCopied ? L10n.tr("Скопировано") : L10n.tr("Скопировать summary")) {
                    copyWeeklySummary()
                }
                .buttonStyle(.bordered)
            }
            .padding()
            .background(.thinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 14))

            if !triggerPatterns.hits.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text(L10n.tr("Паттерны триггеров"))
                        .font(.headline)
                    Text("Паттерны, которые чаще ведут к тяжелому утру или риску памяти.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    ForEach(triggerPatterns.hits) { hit in
                        VStack(alignment: .leading, spacing: 3) {
                            HStack {
                                Text(hit.title)
                                    .font(.subheadline.weight(.semibold))
                                Spacer()
                                Text(hit.value)
                                    .font(.subheadline.weight(.semibold))
                            }
                            Text(hit.impact)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(8)
                        .background(Color(uiColor: .secondarySystemGroupedBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                }
                .padding()
                .background(.thinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 14))
            }

            if let personalizedPattern {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Персональные паттерны")
                        .font(.headline)
                    HStack(spacing: 8) {
                        trendChip(title: L10n.tr("Пик BAC"), direction: personalizedPattern.peakTrend)
                        trendChip(title: L10n.tr("Гидратация"), direction: personalizedPattern.hydrationTrend)
                    }
                    if let wellbeingTrend = personalizedPattern.wellbeingTrend {
                        trendChip(title: L10n.tr("Чек-ин"), direction: wellbeingTrend)
                    }
                    Text(L10n.format("Серия воды: %d · Серия еды: %d", personalizedPattern.waterStreak, personalizedPattern.mealStreak))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    ForEach(personalizedPattern.notes, id: \.self) { note in
                        Text("• \(note)")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding()
                .background(.thinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 14))
            }

            Button("Открыть Premium: Привычки") {
                showingHabits = true
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private var lockedContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Premium аналитика")
                .font(.title2)

            Text("Откройте детальные тренды BAC, динамику воды и персональные паттерны.")
                .foregroundStyle(.secondary)

            lockedCard(title: "Пик BAC по неделям")
            lockedCard(title: "Распределение напитков")
            lockedCard(title: "Связь воды и самочувствия")

            Button("Открыть Paywall") {
                showingPaywall = true
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
        .background(.thinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private func lockedCard(title: String) -> some View {
        Button {
            showingPaywall = true
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .foregroundStyle(.primary)
                    Text("Доступно в Premium")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "lock.fill")
                    .foregroundStyle(.secondary)
            }
            .padding()
            .background(.thinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }

    private func metricChip(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.subheadline.weight(.semibold))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private func trendLine(title: String, value: Double, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(Int((min(1, max(0, value)) * 100).rounded()))%")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
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

    private func limitRow(_ status: (ok: Bool, text: String)) -> some View {
        HStack {
            Image(systemName: status.ok ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(status.ok ? .green : .orange)
            Text(status.text)
                .font(.footnote)
            Spacer()
        }
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

    private func averagePace(for session: Session) -> Double {
        let durationHours = max(0.1, (session.endAt ?? .now).timeIntervalSince(session.startAt) / 3600)
        let standardDrinks = session.drinks.reduce(0.0) { partial, drink in
            let grams = drink.volumeMl * (drink.abvPercent / 100) * 0.789
            return partial + (grams / 14.0)
        }
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
                    Text("Привычки за неделю")
                        .font(.title2)

                    habitCard(
                        title: "Гидратация",
                        subtitle: "Цель: >= \(Int((hydrationGoalProgress * 100).rounded()))% водного баланса",
                        value: hydrationHits,
                        total: goalTarget,
                        tint: .blue
                    )
                    habitCard(
                        title: "Прием пищи",
                        subtitle: "Цель: отмечать еду в сессии",
                        value: mealHits,
                        total: goalTarget,
                        tint: .brown
                    )
                    habitCard(
                        title: "Умеренный темп",
                        subtitle: "Цель: темп ниже персонального порога",
                        value: paceHits,
                        total: goalTarget,
                        tint: .green
                    )

                    if let pattern {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Персональные советы")
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

                    Text("Сессий за 7 дней: \(weekSessionsCount)")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .padding()
            }
            .navigationTitle("Premium Привычки")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Закрыть") { dismiss() }
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
