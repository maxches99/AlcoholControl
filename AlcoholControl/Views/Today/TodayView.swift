import SwiftUI
import SwiftData
import UserNotifications

private enum TodaySheet: Identifiable {
    case addDrink(UUID)
    case addMeal(UUID)
    case addWater(UUID)
    case endSession(UUID)
    case checkIn(UUID)
    case forecast(UUID)
    case waterReminders
    case share(UUID)
    case glossary
    case safetyCenter

    var id: String {
        switch self {
        case .addDrink(let id): return "addDrink-\(id.uuidString)"
        case .addMeal(let id): return "addMeal-\(id.uuidString)"
        case .addWater(let id): return "addWater-\(id.uuidString)"
        case .endSession(let id): return "endSession-\(id.uuidString)"
        case .checkIn(let id): return "checkIn-\(id.uuidString)"
        case .forecast(let id): return "forecast-\(id.uuidString)"
        case .share(let id): return "share-\(id.uuidString)"
        case .waterReminders: return "waterReminders"
        case .glossary: return "glossary"
        case .safetyCenter: return "safetyCenter"
        }
    }
}

private enum SessionEvent: Identifiable {
    case drink(DrinkEntry)
    case meal(MealEntry)
    case water(WaterEntry)

    var id: UUID {
        switch self {
        case .drink(let drink): return drink.id
        case .meal(let meal): return meal.id
        case .water(let water): return water.id
        }
    }

    var date: Date {
        switch self {
        case .drink(let drink): return drink.createdAt
        case .meal(let meal): return meal.createdAt
        case .water(let water): return water.createdAt
        }
    }
}

private enum SessionLimitLevel {
    case onTrack
    case nearLimit
    case exceeded

    var title: String {
        switch self {
        case .onTrack:
            return L10n.tr("В пределах лимита")
        case .nearLimit:
            return L10n.tr("Близко к лимиту")
        case .exceeded:
            return L10n.tr("Лимит превышен")
        }
    }

    var hint: String {
        switch self {
        case .onTrack:
            return L10n.tr("Темп пока в вашем плане, удерживайте воду и паузы.")
        case .nearLimit:
            return L10n.tr("Осталось мало запаса. Лучше перейти на более медленный темп и воду.")
        case .exceeded:
            return L10n.tr("Сейчас безопаснее остановить алкоголь и перейти к восстановлению.")
        }
    }

    var color: Color {
        switch self {
        case .onTrack:
            return .green
        case .nearLimit:
            return .orange
        case .exceeded:
            return .red
        }
    }
}

private struct SessionLimitState {
    let level: SessionLimitLevel
    let standardDrinks: Double
    let goalStdDrinks: Double

    var progress: Double {
        min(1.4, standardDrinks / max(goalStdDrinks, 0.1))
    }
}

struct TodayView: View {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.modelContext) private var context
    @Environment(\.openURL) private var openURL
    @EnvironmentObject private var appState: AppState

    @Query(sort: [SortDescriptor<Session>(\.startAt, order: .reverse)]) private var sessions: [Session]
    @Query(sort: [SortDescriptor<DrinkEntry>(\.createdAt, order: .reverse)]) private var allDrinks: [DrinkEntry]
    @Query private var profiles: [UserProfile]
    @Query(sort: [SortDescriptor<HealthDailySnapshot>(\.day, order: .reverse)]) private var healthSnapshots: [HealthDailySnapshot]
    @Query(sort: [SortDescriptor<RiskModelRun>(\.updatedAt, order: .reverse)]) private var riskModelRuns: [RiskModelRun]

    @State private var activeSheet: TodaySheet?
    @State private var showEmergencyConfirm = false
    @State private var showGlossaryTooltip = false
    @State private var showPromilleInfo = false
    @State private var activeTermHint: TermHintOverlayState?
    @State private var infoMessage: String?
    @State private var healthSleepHours: Double?
    @State private var healthStepCount: Int?
    @State private var healthRestingHR: Int?
    @State private var healthHRV: Double?
    @State private var healthSleepEfficiency: Double?
    @State private var loadedHealthData = false
    @AppStorage("goalStdDrinks") private var goalStdDrinks = 4.0
    @AppStorage("goalWaterMl") private var goalWaterMl = 1200.0
    @AppStorage("goalEndHour") private var goalEndHour = 1
    @AppStorage("preSessionPlanEnabled") private var preSessionPlanEnabled = true
    @AppStorage("autoFinishSuggestionHours") private var autoFinishSuggestionHours = 6
    @AppStorage("liveActivityEnabled") private var liveActivityEnabled = true
    @AppStorage(HealthKitService.StorageKey.syncWaterWithHealth) private var syncWaterWithHealth = true
    @AppStorage("safetyModeEnabled") private var safetyModeEnabled = false
    @AppStorage("trustedContactPhone") private var trustedContactPhone = ""
    @AppStorage("riskModelVariant") private var riskModelVariant = "A"
    @AppStorage("shadowRiskModeEnabled") private var shadowRiskModeEnabled = true
    @AppStorage("shadowRolloutMinHistory") private var shadowRolloutMinHistory = 5
    @AppStorage("shadowRolloutMinConfidence") private var shadowRolloutMinConfidence = 55

    private let sessionService = SessionService()
    private let calculator = BACCalculator()
    private let insightService = SessionInsightService()
    private let baselineCalculator = BaselineCalculator()
    private var healthBaselines: HealthBaselineSet {
        let anchor = Calendar.current.startOfDay(for: .now)
        return HealthBaselineSet(
            steps: baselineCalculator.stats(for: .steps, snapshots: healthSnapshots, anchorDay: anchor),
            restingHeartRate: baselineCalculator.stats(for: .restingHeartRate, snapshots: healthSnapshots, anchorDay: anchor),
            hrv: baselineCalculator.stats(for: .heartRateVariability, snapshots: healthSnapshots, anchorDay: anchor),
            sleep: baselineCalculator.stats(for: .sleepDuration, snapshots: healthSnapshots, anchorDay: anchor)
        )
    }

    init() {
        _sessions = Query(sort: [SortDescriptor<Session>(\.startAt, order: .reverse)])
        _allDrinks = Query(sort: [SortDescriptor<DrinkEntry>(\.createdAt, order: .reverse)])
        _profiles = Query()
        _healthSnapshots = Query(sort: [SortDescriptor<HealthDailySnapshot>(\.day, order: .reverse)])
        _riskModelRuns = Query(sort: [SortDescriptor<RiskModelRun>(\.updatedAt, order: .reverse)])
    }

    private var activeSession: Session? {
        sessions.first(where: { $0.isActive })
    }

    private var latestSessionWithoutCheckIn: Session? {
        sessions.first(where: { !$0.isActive && $0.morningCheckIn == nil })
    }

    private var profile: UserProfile? {
        profiles.first
    }

    private var latestDrinkTemplate: DrinkEntry? {
        allDrinks.first
    }

    private var recentPresets: [DrinkPresetModel] {
        var seen = Set<String>()
        var result: [DrinkPresetModel] = []

        for drink in allDrinks {
            let key = "\(drink.title ?? drink.category.rawValue)-\(Int(drink.volumeMl))\(Int(drink.abvPercent))"
            if seen.contains(key) { continue }
            seen.insert(key)
            result.append(
                DrinkPresetModel(
                    id: key,
                    title: drink.title ?? drink.category.label,
                    subtitle: drink.category.label,
                    category: drink.category,
                    volumeMl: drink.volumeMl,
                    abv: drink.abvPercent,
                    group: group(for: drink.category)
                )
            )
            if result.count == 5 { break }
        }
        return result
    }

    private func group(for category: DrinkEntry.Category) -> DrinkPresetGroup {
        switch category {
        case .beer:
            return .beer
        case .wine:
            return .wine
        case .spirits:
            return .spirits
        case .cocktail:
            return .cocktails
        case .cider, .seltzer, .liqueur, .other:
            return .light
        }
    }

    private var oneTapPresets: [DrinkPresetModel] {
        let targetCategories: [DrinkEntry.Category] = [.beer, .wine, .cocktail]
        return targetCategories.compactMap { category in
            if let recent = recentPresets.first(where: { $0.category == category }) {
                return recent
            }
            return DrinkCatalog.defaults.first(where: { $0.category == category })
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if let session = activeSession {
                    activeSessionView(session)
                } else {
                    emptyState
                }
            }
            .navigationTitle("Сегодня")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        activeTermHint = nil
                        withAnimation(.easeInOut(duration: 0.18)) {
                            showGlossaryTooltip.toggle()
                        }
                    } label: {
                        Image(systemName: "questionmark.circle")
                    }
                    .accessibilityLabel("Подсказки по терминам")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        activeSheet = .safetyCenter
                    } label: {
                        Image(systemName: "cross.case.fill")
                    }
                    .accessibilityLabel(L10n.tr("Открыть центр безопасности"))
                }
                if let session = activeSession {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Завершить") {
                            activeSheet = .endSession(session.id)
                        }
                        .accessibilityLabel("Завершить сессию")
                    }
                }
            }
            .sheet(item: $activeSheet) { sheet in
                switch sheet {
                case .addDrink(let sessionID):
                    if let session = sessionByID(sessionID) {
                        AddDrinkFlowSheet(session: session, profile: profile, recentPresets: recentPresets)
                    }
                case .addMeal(let sessionID):
                    if let session = sessionByID(sessionID) {
                        AddMealSheet(session: session, profile: profile)
                    }
                case .addWater(let sessionID):
                    if let session = sessionByID(sessionID) {
                        AddWaterSheet(session: session, profile: profile)
                    }
                case .endSession(let sessionID):
                    if let session = sessionByID(sessionID) {
                        EndSessionSheet(session: session, profile: profile)
                    }
                case .checkIn(let sessionID):
                    if let session = sessionByID(sessionID) {
                        MorningCheckInView(session: session) { completedSessionID in
                            appState.pendingMorningCheckInSessionID = nil
                            appState.openForecast(sessionID: completedSessionID)
                        }
                    }
                case .forecast(let sessionID):
                    if let session = sessionByID(sessionID) {
                        ForecastView(session: session, profile: profile)
                    }
                case .share(let sessionID):
                    if let session = sessionByID(sessionID) {
                        ShareCardView(session: session)
                    }
                case .waterReminders:
                    NavigationStack {
                        NotificationsSettingsView()
                    }
                case .glossary:
                    GlossaryView()
                case .safetyCenter:
                    SafetyCenterView()
                }
            }
            .sheet(isPresented: $showPromilleInfo) {
                PromilleInfoSheet()
            }
            .overlay(alignment: .topLeading) {
                if showGlossaryTooltip {
                    GlossaryTooltipView {
                        withAnimation(.easeInOut(duration: 0.18)) {
                            showGlossaryTooltip = false
                        }
                        activeSheet = .glossary
                    }
                    .padding(.top, 8)
                    .padding(.leading, 12)
                    .transition(.scale(scale: 0.96, anchor: .topLeading).combined(with: .opacity))
                    .zIndex(3)
                }
            }
            .overlayPreferenceValue(TermHintAnchorPreferenceKey.self) { anchors in
                GeometryReader { proxy in
                    if let activeTermHint, let anchor = anchors[activeTermHint.id] {
                        let sourceRect = proxy[anchor]
                        let x = termHintX(for: sourceRect, containerWidth: proxy.size.width)
                        TermHintOverlayCard(hint: activeTermHint) {
                            self.activeTermHint = nil
                        }
                        .offset(x: x, y: sourceRect.maxY + 8)
                        .transition(.scale(scale: 0.96, anchor: .topTrailing).combined(with: .opacity))
                        .zIndex(4)
                    }
                }
            }
            .alert("Экстренная помощь", isPresented: $showEmergencyConfirm) {
                Button("Позвонить 112") {
                    guard let url = URL(string: "tel://112") else { return }
                    openURL(url)
                }
                Button("Отмена", role: .cancel) {}
            } message: {
                Text("Если состояние резко ухудшается, вызовите экстренную помощь.")
            }
            .onAppear {
                presentPendingRouteIfNeeded()
                applyPendingWatchActionsIfNeeded()
                updateModelQualityMetricsIfPossible()
            }
            .onChange(of: appState.pendingMorningCheckInSessionID) { _, _ in
                presentPendingRouteIfNeeded()
            }
            .onChange(of: appState.pendingOpenLatestMorningCheckIn) { _, _ in
                presentPendingRouteIfNeeded()
            }
            .onChange(of: appState.pendingForecastSessionID) { _, newValue in
                guard let id = newValue else { return }
                activeSheet = .forecast(id)
                appState.pendingForecastSessionID = nil
            }
            .onChange(of: scenePhase) { _, newValue in
                guard newValue == .active else { return }
                applyPendingWatchActionsIfNeeded()
                loadedHealthData = false
                Task {
                    await loadTodayHealthDataIfNeeded()
                }
            }
            .onChange(of: activeTermHint) { _, newValue in
                if newValue != nil {
                    showGlossaryTooltip = false
                }
            }
            .onChange(of: showGlossaryTooltip) { _, isPresented in
                if isPresented {
                    activeTermHint = nil
                }
            }
            .onChange(of: sessions.count) { _, _ in
                updateModelQualityMetricsIfPossible()
            }
        }
    }

    @ViewBuilder
    private func activeSessionView(_ session: Session) -> some View {
        let timeline = profile.map { calculator.compute(for: session, profile: $0) }
        let healthContext = SessionHealthContext(
            sleepHours: healthSleepHours,
            stepCount: healthStepCount,
            restingHeartRate: healthRestingHR,
            hrvSdnn: healthHRV,
            sleepEfficiency: healthSleepEfficiency
        )
        let baselines = healthBaselines
        let insights = insightService.assess(
            session: session,
            profile: profile,
            health: healthContext,
            history: sessions
        )
        let recoveryIndex = insightService.recoveryIndex(session: session, assessment: insights, health: healthContext, baselines: baselines)
        let patterns = insightService.personalizedPatterns(current: session, history: sessions, profile: profile)
        let scenarios = insightService.eveningScenarios(for: session, profile: profile, history: sessions)
        let projections = insightService.memoryProjections(for: session, profile: profile, history: sessions)
        let shadowAssessment = shadowRiskModeEnabled
            ? insightService.assessShadow(
                session: session,
                profile: profile,
                health: healthContext,
                history: sessions,
                baseline: insights
            )
            : nil
        let completedHistoryCount = sessions.filter { !$0.isActive && $0.id != session.id }.count
        let shouldShowShadowBlock = (shadowAssessment?.status == .ready) &&
            completedHistoryCount >= shadowRolloutMinHistory &&
            (shadowAssessment?.confidencePercent ?? 0) >= shadowRolloutMinConfidence
        let standardDrinks = standardDrinksInSession(session)
        let consumedWaterMl = session.waters.compactMap(\.volumeMl).reduce(0, +)
        let limitState = sessionLimitState(standardDrinks: standardDrinks)

        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if let infoMessage {
                    infoMessageView(infoMessage)
                }
                if shouldSuggestSessionFinish(session) {
                    autoFinishSuggestionCard(session)
                }
                sessionOverviewCard(
                    currentBAC: timeline?.currentBAC ?? 0,
                    soberAt: timeline?.estimatedSoberAt,
                    confidence: insights.confidence,
                    memoryRisk: insights.memoryRisk,
                    memoryRiskPercent: insights.memoryProbabilityPercent,
                    recoveryIndex: recoveryIndex
                )
                hydrationSummaryCard(insights.waterBalance)
                goalsProgressCard(
                    session: session,
                    standardDrinks: standardDrinks,
                    consumedWaterMl: consumedWaterMl
                )
                sessionLimitCard(limitState)
                oneTapDrinkCard(session: session)
                eveningProcessCoachCard(
                    session: session,
                    insights: insights,
                    patterns: patterns,
                    standardDrinks: standardDrinks
                )

                EveningInsightsCard(
                    insights: insights,
                    shadowAssessment: shouldShowShadowBlock ? shadowAssessment : nil,
                    recoveryIndex: recoveryIndex,
                    patterns: patterns,
                    scenarios: scenarios,
                    projections: projections,
                    onOpenGlossary: {
                        activeTermHint = nil
                        showGlossaryTooltip = true
                    },
                    onOpenForecast: {
                        activeSheet = .forecast(session.id)
                    }
                )

                if let bac = timeline?.currentBAC, bac >= 0.16 {
                    safetyBanner
                }

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                    actionButton(title: L10n.tr("+ Напиток"), icon: "wineglass.fill", tint: .orange) {
                        activeSheet = .addDrink(session.id)
                    }
                    .accessibilityLabel("Добавить напиток")

                    actionButton(title: L10n.tr("+ Еда"), icon: "fork.knife", tint: .brown) {
                        activeSheet = .addMeal(session.id)
                    }
                    .accessibilityLabel("Добавить прием пищи")

                    actionButton(title: L10n.tr("+ Вода"), icon: "drop.fill", tint: .blue) {
                        activeSheet = .addWater(session.id)
                    }
                    .accessibilityLabel("Добавить воду")
                    actionButton(title: L10n.tr("Напоминания"), icon: "bell", tint: .indigo) {
                        activeSheet = .waterReminders
                    }
                    .accessibilityLabel("Открыть настройки напоминаний")

                    actionButton(title: "Share Card", icon: "square.and.arrow.up", tint: .teal) {
                        activeSheet = .share(session.id)
                    }
                    .accessibilityLabel("Поделиться карточкой")

                    actionButton(title: L10n.tr("Повторить последний"), icon: "arrow.clockwise", tint: .pink) {
                        repeatLastDrink(into: session)
                    }
                    .accessibilityLabel("Повторить последний напиток")

                    if liveActivityEnabled {
                        actionButton(title: "Live Activity", icon: "dot.radiowaves.left.and.right", tint: .green) {
                            Task {
                                let result = await LiveSessionActivityService.shared.upsert(
                                    sessionID: session.id,
                                    currentBAC: timeline?.currentBAC ?? 0,
                                    soberAt: timeline?.estimatedSoberAt
                                )
                                infoMessage = result.userMessage
                            }
                        }
                        .accessibilityLabel("Запустить Live Activity")
                    }
                }

                TimelineSection(
                    session: session,
                    onDeleteDrink: { drink in
                        sessionService.delete(entry: drink, from: session, context: context, profile: profile)
                    },
                    onDeleteMeal: { meal in
                        sessionService.delete(entry: meal, from: session, context: context, profile: profile)
                    },
                    onDeleteWater: { water in
                        sessionService.delete(entry: water, from: session, context: context, profile: profile)
                    }
                )
            }
            .padding(.horizontal)
            .padding(.top, 8)
            .padding(.bottom, 16)
        }
        .task(
            id: liveActivityTaskID(
                session: session,
                currentBAC: timeline?.currentBAC ?? 0,
                soberAt: timeline?.estimatedSoberAt,
                waterConsumed: insights.waterBalance.consumedMl,
                waterTarget: insights.waterBalance.targetMl,
                risk: insights.morningRisk
            )
        ) {
            await loadTodayHealthDataIfNeeded()
            if liveActivityEnabled {
                let liveResult = await LiveSessionActivityService.shared.upsert(
                    sessionID: session.id,
                    currentBAC: timeline?.currentBAC ?? 0,
                    soberAt: timeline?.estimatedSoberAt
                )
                switch liveResult {
                case .failed, .unavailable:
                    infoMessage = liveResult.userMessage
                default:
                    break
                }
            }
            WidgetSnapshotStore.update(
                isActive: true,
                currentBAC: timeline?.currentBAC ?? 0,
                soberAt: timeline?.estimatedSoberAt,
                waterConsumedMl: insights.waterBalance.consumedMl,
                waterTargetMl: insights.waterBalance.targetMl,
                morningRisk: insights.morningRisk,
                recoveryScore: recoveryIndex.score,
                recoveryLevel: recoveryIndex.level
            )
            await syncSmartReminder(sessionID: session.id, insights: insights)
            recordRiskModelRun(
                variant: riskModelVariant,
                confidencePercent: insights.confidence.scorePercent,
                morningProbability: insights.morningProbabilityPercent,
                memoryProbability: insights.memoryProbabilityPercent
            )
            if let shadowAssessment, shadowAssessment.status == .ready {
                recordRiskModelRun(
                    variant: "coreml-shadow-v1",
                    confidencePercent: shadowAssessment.confidencePercent,
                    morningProbability: shadowAssessment.morningProbabilityPercent ?? 0,
                    memoryProbability: shadowAssessment.memoryProbabilityPercent ?? 0
                )
            }
            updateModelQualityMetricsIfPossible()
        }
    }

    private var emptyState: some View {
        VStack(spacing: 18) {
            if let infoMessage {
                infoMessageView(infoMessage)
                    .padding(.horizontal)
            }

            if preSessionPlanEnabled {
                preSessionPlanCard
                    .padding(.horizontal)
            }

            Text("Сессия не активна")
                .font(.title3)
            Text("Начните вечер, чтобы логировать напитки, воду и видеть динамику BAC.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal)

            Button("Начать вечер") {
                startSessionWithPlanContext()
            }
            .buttonStyle(.borderedProminent)
            .accessibilityLabel("Начать вечер")

            if let pending = latestSessionWithoutCheckIn {
                Button("Утренний чек-ин") {
                    activeSheet = .checkIn(pending.id)
                }
                .buttonStyle(.bordered)
            }

            if !recentPresets.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Недавние напитки")
                        .font(.headline)
                    ForEach(recentPresets.prefix(3)) { preset in
                        HStack {
                            Text(preset.title.localized)
                            Spacer()
                            Text(L10n.format("%d мл @ %d%%", Int(preset.volumeMl), Int(preset.abv)))
                                .foregroundStyle(.secondary)
                        }
                        .font(.footnote)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task {
            await LiveSessionActivityService.shared.endAll()
            WidgetSnapshotStore.clear()
        }
    }

    private var preSessionPlanCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(L10n.tr("Pre-session plan"))
                    .font(.headline)
                Spacer()
                if safetyModeEnabled {
                    Text(L10n.tr("Safety mode"))
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(.red.opacity(0.15))
                        .clipShape(Capsule())
                }
            }
            Text(
                L10n.format(
                    "Лимит: %.1f ст.др. · Вода: %d мл · Стоп до %02d:00",
                    goalStdDrinks,
                    Int(goalWaterMl),
                    goalEndHour
                )
            )
                .font(.footnote)
                .foregroundStyle(.secondary)
            Text(
                safetyModeEnabled
                ? L10n.tr("В safety mode будут более частые risk-подсказки и ранние напоминания о паузе.")
                : L10n.tr("План помогает заранее задать лимиты и снизить риск тяжелого утра.")
            )
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private var safetyBanner: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Высокий риск")
                .font(.headline)
            Text("Текущая оценка BAC очень высокая. Следите за состоянием и не оставайтесь в одиночку.")
                .font(.subheadline)
            HStack {
                Button(L10n.tr("Центр безопасности")) {
                    activeSheet = .safetyCenter
                }
                .buttonStyle(.bordered)

                Button("Экстренная помощь") {
                    showEmergencyConfirm = true
                }
                .buttonStyle(.borderedProminent)
            }
            if !trustedContactPhone.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(L10n.tr("Можно быстро связаться с доверенным контактом из центра безопасности."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.red.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func sessionOverviewCard(
        currentBAC: Double,
        soberAt: Date?,
        confidence: InsightConfidence,
        memoryRisk: InsightLevel,
        memoryRiskPercent: Int,
        recoveryIndex: RecoveryIndexSnapshot
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(L10n.tr("BAC (примерно)"))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        TermHintBadge(
                            term: "BAC",
                            definition: "Оценка концентрации алкоголя в крови по модели, а не медицинское измерение.",
                            activeHint: $activeTermHint
                        )
                        Button {
                            showPromilleInfo = true
                        } label: {
                            Image(systemName: "info.circle")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(L10n.tr("Как понимать промилле"))
                    }
                    Text(String(format: "%.3f", currentBAC))
                        .font(.system(size: 46, weight: .bold, design: .rounded))
                    Text(L10n.format("Промилле (примерно): %.2f‰", currentBAC * 10))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    HStack(spacing: 6) {
                        Text("До ~0.00")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        TermHintBadge(
                            term: "До ~0.00",
                            definition: "Примерное время, когда BAC по модели снизится до нуля.",
                            activeHint: $activeTermHint
                        )
                    }
                    Text(soberText(for: soberAt).replacingOccurrences(of: "До ~0.00: ", with: ""))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                }
            }
            Text(L10n.tr("Оценка приблизительная. Не использовать для решения, можно ли водить."))
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack {
                Text("Уверенность оценки: ~\(confidence.scorePercent)%")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("Память: \(memoryRisk.title.capitalized) (~\(memoryRiskPercent)%)")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(levelColor(memoryRisk))
            }
            HStack {
                Text(L10n.tr("Индекс восстановления"))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(recoveryIndex.score)/100")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(levelColor(recoveryIndex.level))
            }
            ProgressView(value: Double(recoveryIndex.score) / 100)
                .tint(levelColor(recoveryIndex.level))
            Text(recoveryIndex.headline.capitalized)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(
                colors: [.blue.opacity(0.16), .mint.opacity(0.11)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: 16))
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

    private func termHintX(for sourceRect: CGRect, containerWidth: CGFloat) -> CGFloat {
        let tooltipWidth: CGFloat = 260
        let horizontalPadding: CGFloat = 12
        let preferredX = sourceRect.maxX - tooltipWidth
        let maxX = containerWidth - tooltipWidth - horizontalPadding
        return min(max(horizontalPadding, preferredX), max(horizontalPadding, maxX))
    }

    private func hydrationSummaryCard(_ waterBalance: WaterBalanceSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                HStack(spacing: 6) {
                    Text("Водный баланс")
                        .font(.headline)
                    TermHintBadge(
                        term: "Водный баланс",
                        definition: "Сравнение выпитой воды с ориентиром для текущей сессии.",
                        activeHint: $activeTermHint
                    )
                }
                Spacer()
                Text(waterBalance.status.title.capitalized)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(waterStatusColor(waterBalance.status))
            }

            Text("\(waterBalance.consumedMl) мл из ~\(waterBalance.targetMl) мл")
                .font(.footnote)
                .foregroundStyle(.secondary)
            ProgressView(value: waterBalance.progress)

            if waterBalance.deficitMl > 0 {
                Text("До цели еще ~\(waterBalance.deficitMl) мл. Сейчас лучше добавить ~\(waterBalance.suggestedTopUpMl) мл.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                Text("Баланс в норме. Поддерживайте текущий темп воды.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private func autoFinishSuggestionCard(_ session: Session) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Сессия выглядит неактивной")
                .font(.headline)
            Text("Давно не было новых записей. Можно завершить сессию и перейти к плану восстановления.")
                .font(.footnote)
                .foregroundStyle(.secondary)
            Button("Завершить сессию") {
                activeSheet = .endSession(session.id)
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.orange.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private func goalsProgressCard(session: Session, standardDrinks: Double, consumedWaterMl: Double) -> some View {
        let drinksProgress = min(1, standardDrinks / max(goalStdDrinks, 0.1))
        let waterProgress = min(1, consumedWaterMl / max(goalWaterMl, 1))
        let isPastGoalTime = Calendar.current.component(.hour, from: .now) >= goalEndHour

        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(L10n.tr("Цели вечера"))
                    .font(.headline)
                Spacer()
                Text(isPastGoalTime ? L10n.tr("Время завершаться") : L10n.tr("В процессе"))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(isPastGoalTime ? .orange : .secondary)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(L10n.format("Алкоголь: %.1f / %.1f ст.др.", standardDrinks, goalStdDrinks))
                    .font(.footnote)
                ProgressView(value: drinksProgress)
                    .tint(drinksProgress > 1 ? .red : .orange)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(L10n.format("Вода: %d / %d мл", Int(consumedWaterMl), Int(goalWaterMl)))
                    .font(.footnote)
                ProgressView(value: waterProgress)
                    .tint(waterProgress >= 1 ? .green : .blue)
            }

            if drinksProgress >= 1 {
                Text(L10n.tr("Лимит по алкоголю достигнут. Лучше перейти на воду и еду."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if waterProgress < 0.5 {
                Text(L10n.tr("Гидратация отстает. Добавьте 1-2 порции воды."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private func sessionLimitState(standardDrinks: Double) -> SessionLimitState {
        let ratio = standardDrinks / max(goalStdDrinks, 0.1)
        let level: SessionLimitLevel
        if ratio >= 1 {
            level = .exceeded
        } else if ratio >= 0.75 {
            level = .nearLimit
        } else {
            level = .onTrack
        }
        return SessionLimitState(
            level: level,
            standardDrinks: standardDrinks,
            goalStdDrinks: max(goalStdDrinks, 0.1)
        )
    }

    private func sessionLimitCard(_ state: SessionLimitState) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(L10n.tr("Личный лимит сессии"))
                    .font(.headline)
                Spacer()
                Text(state.level.title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(state.level.color)
            }

            Text(
                L10n.format(
                    "Сейчас %.1f из %.1f ст.др.",
                    state.standardDrinks,
                    state.goalStdDrinks
                )
            )
            .font(.footnote)
            .foregroundStyle(.secondary)

            ProgressView(value: min(1, state.progress))
                .tint(state.level.color)

            Text(state.level.hint)
                .font(.caption)
                .foregroundStyle(.secondary)

            if state.level != .onTrack {
                Button(L10n.tr("Запланировать паузу 20 минут")) {
                    Task {
                        await NotificationService.shared.schedulePauseReminder(after: 20)
                    }
                }
                .buttonStyle(.bordered)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(state.level.color.opacity(0.10))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private func oneTapDrinkCard(session: Session) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(L10n.tr("One-tap лог"))
                    .font(.headline)
                Spacer()
                Text(L10n.tr("Без открытия формы"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if oneTapPresets.isEmpty {
                Text(L10n.tr("Добавьте первый напиток, и появятся быстрые пресеты."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                HStack(spacing: 8) {
                    ForEach(oneTapPresets) { preset in
                        Button {
                            saveOneTapPreset(preset, into: session)
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(preset.category.label)
                                    .font(.caption2.weight(.semibold))
                                Text("\(Int(preset.volumeMl)) мл")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 6)
                            .padding(.horizontal, 8)
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private func eveningProcessCoachCard(
        session: Session,
        insights: EveningInsightAssessment,
        patterns: PersonalizedPatternAssessment,
        standardDrinks: Double
    ) -> some View {
        let pace = max(0.1, (session.endAt ?? .now).timeIntervalSince(session.startAt) / 3600)
        let drinksPerHour = standardDrinks / pace
        let hydrationOnTrack = insights.waterBalance.progress >= patterns.hydrationGoalProgress
        let mealOnTrack = hasMealNearFirstDrink(session: session)
        let paceOnTrack = drinksPerHour <= patterns.paceRiskThreshold
        let completeCount = [hydrationOnTrack, mealOnTrack, paceOnTrack].filter { $0 }.count

        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Процесс вечера")
                    .font(.headline)
                Spacer()
                Text("\(completeCount)/3")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(completeCount >= 2 ? .green : .orange)
            }
            processCheckpoint(
                title: L10n.tr("Гидратация в целевом диапазоне"),
                subtitle: L10n.format("%d%% vs цель %d%%", Int((insights.waterBalance.progress * 100).rounded()), Int((patterns.hydrationGoalProgress * 100).rounded())),
                isDone: hydrationOnTrack
            )
            processCheckpoint(
                title: L10n.tr("Еда отмечена вовремя"),
                subtitle: L10n.tr("До первого напитка или в первые 30 минут"),
                isDone: mealOnTrack
            )
            processCheckpoint(
                title: L10n.tr("Темп ниже личного порога"),
                subtitle: L10n.format("%.1f vs %.1f ст.др./ч", drinksPerHour, patterns.paceRiskThreshold),
                isDone: paceOnTrack
            )
            Text(processCoachHint(hydrationOnTrack: hydrationOnTrack, mealOnTrack: mealOnTrack, paceOnTrack: paceOnTrack))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private func processCheckpoint(title: String, subtitle: String, isDone: Bool) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: isDone ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(isDone ? .green : .secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline)
                Text(subtitle)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    private func processCoachHint(hydrationOnTrack: Bool, mealOnTrack: Bool, paceOnTrack: Bool) -> String {
        if !hydrationOnTrack {
            return L10n.tr("Сфокусируйтесь на воде: это самый быстрый способ улучшить прогноз утра.")
        }
        if !mealOnTrack {
            return L10n.tr("Добавьте прием пищи: по модели это поможет снизить риск тяжелого утра.")
        }
        if !paceOnTrack {
            return L10n.tr("Снизьте темп и добавьте паузу 25-30 минут.")
        }
        return L10n.tr("Процесс выглядит устойчиво: продолжайте в том же режиме.")
    }

    private func infoMessageView(_ message: String) -> some View {
        Text(message)
            .font(.footnote)
            .foregroundStyle(.secondary)
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.blue.opacity(0.10))
            .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private func actionButton(title: String, icon: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
        }
        .buttonStyle(.bordered)
        .controlSize(.large)
        .tint(tint)
    }

    private func soberText(for date: Date?) -> String {
        guard let date else { return "0.00 сейчас" }
        let interval = date.timeIntervalSinceNow
        guard interval > 1 else { return "0.00 сейчас" }
        let totalMinutes = Int(interval / 60)
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        return hours > 0 ? "До ~0.00: \(hours) ч \(minutes) м" : "До ~0.00: \(minutes) м"
    }

    private func standardDrinksInSession(_ session: Session) -> Double {
        session.drinks.reduce(0.0) { partial, drink in
            let grams = drink.volumeMl * (drink.abvPercent / 100) * 0.789
            return partial + (grams / 14.0)
        }
    }

    private func hasMealNearFirstDrink(session: Session) -> Bool {
        guard let firstDrinkAt = session.drinks.map(\.createdAt).min() else { return false }
        return session.meals.contains { meal in
            let deltaMinutes = meal.createdAt.timeIntervalSince(firstDrinkAt) / 60
            return (-90...30).contains(deltaMinutes)
        }
    }

    private func shouldSuggestSessionFinish(_ session: Session) -> Bool {
        guard autoFinishSuggestionHours > 0 else { return false }
        let threshold = Double(autoFinishSuggestionHours) * 3600
        return Date.now.timeIntervalSince(lastActivityDate(for: session)) >= threshold
    }

    private func lastActivityDate(for session: Session) -> Date {
        let drinkDate = session.drinks.map(\.createdAt).max()
        let waterDate = session.waters.map(\.createdAt).max()
        let mealDate = session.meals.map(\.createdAt).max()
        return [session.startAt, drinkDate, waterDate, mealDate].compactMap { $0 }.max() ?? session.startAt
    }

    private func repeatLastDrink(into session: Session) {
        guard let last = latestDrinkTemplate else {
            infoMessage = L10n.tr("Пока нет прошлых напитков для быстрого повтора.")
            return
        }

        sessionService.addDrink(
            to: session,
            context: context,
            profile: profile,
            createdAt: .now,
            volumeMl: last.volumeMl,
            abvPercent: last.abvPercent,
            title: last.title,
            category: last.category
        )
        infoMessage = L10n.format("Повторили: %@", (last.title ?? last.category.label).localized)
    }

    private func saveOneTapPreset(_ preset: DrinkPresetModel, into session: Session) {
        sessionService.addDrink(
            to: session,
            context: context,
            profile: profile,
            createdAt: .now,
            volumeMl: preset.volumeMl,
            abvPercent: preset.abv,
            title: preset.title,
            category: preset.category
        )
        infoMessage = L10n.format("Быстро добавлено: %@", preset.category.label)
        let assessment = insightService.assess(session: session, profile: profile, history: sessions)
        Task {
            await syncSmartReminder(sessionID: session.id, insights: assessment)
        }
    }

    private func startSessionWithPlanContext() {
        if let active = activeSession {
            activeSheet = .endSession(active.id)
            return
        }
        do {
            _ = try sessionService.startSession(context: context)
            if preSessionPlanEnabled {
                infoMessage = L10n.format(
                    "План активирован: лимит %.1f ст.др., вода %d мл.",
                    goalStdDrinks,
                    Int(goalWaterMl)
                )
            } else {
                infoMessage = nil
            }
        } catch {
            print("Failed to start session: \(error)")
        }
    }

    private func applyPendingWatchActionsIfNeeded() {
        let startRequested = WidgetSnapshotStore.consumePendingStartSessionRequest()
        let pendingMl = WidgetSnapshotStore.consumePendingWaterMl()
        let pendingDrink = WidgetSnapshotStore.consumePendingDrink()
        let pendingMealSize = WidgetSnapshotStore.consumePendingMealSize()
        let endRequested = WidgetSnapshotStore.consumePendingEndSessionRequest()
        let safetyRequested = WidgetSnapshotStore.consumePendingSafetyCheckRequest()
        let pauseMinutes = WidgetSnapshotStore.consumePendingPauseRequest()

        let needsActiveSession = startRequested || pendingMl > 0 || pendingDrink != nil || pendingMealSize != nil
        if needsActiveSession, activeSession == nil {
            do {
                _ = try sessionService.startSession(context: context)
                if startRequested {
                    infoMessage = L10n.tr("С часов/виджета запрошен старт сессии")
                }
            } catch {
                infoMessage = L10n.tr("Не удалось запустить сессию")
            }
        }

        guard let session = activeSession else {
            if safetyRequested {
                activeSheet = .safetyCenter
                infoMessage = L10n.tr("С часов пришел запрос открыть центр безопасности")
            }
            if let pauseMinutes {
                Task {
                    await NotificationService.shared.schedulePauseReminder(after: pauseMinutes)
                }
                infoMessage = L10n.format("Напоминание о паузе на %d мин запущено", pauseMinutes)
            }
            return
        }

        if pendingMl > 0 {
            sessionService.addWater(
                to: session,
                context: context,
                profile: profile,
                volumeMl: Double(pendingMl)
            )
            infoMessage = L10n.format("Добавлено с часов: +%d мл воды", pendingMl)
        }

        if let pendingDrink {
            sessionService.addDrink(
                to: session,
                context: context,
                profile: profile,
                createdAt: .now,
                volumeMl: pendingDrink.volumeMl,
                abvPercent: pendingDrink.abvPercent,
                title: pendingDrink.title,
                category: pendingDrink.category
            )
            infoMessage = L10n.format("Добавлено с часов: %@", pendingDrink.title)
        }

        if let mealSize = pendingMealSize {
            sessionService.addMeal(
                to: session,
                context: context,
                profile: profile,
                createdAt: .now,
                title: mealSize.label,
                size: mealSize
            )
            infoMessage = L10n.format("Добавлено с часов: %@", mealSize.label)
        }

        if endRequested {
            activeSheet = .endSession(session.id)
            infoMessage = L10n.tr("На часах запрошено завершение сессии")
        }

        if safetyRequested {
            activeSheet = .safetyCenter
            infoMessage = L10n.tr("С часов пришел запрос открыть центр безопасности")
        }

        if let pauseMinutes {
            Task {
                await NotificationService.shared.schedulePauseReminder(after: pauseMinutes)
            }
            infoMessage = L10n.format("Напоминание о паузе на %d мин запущено", pauseMinutes)
        }
    }

    private func loadTodayHealthDataIfNeeded() async {
        if !loadedHealthData {
            loadedHealthData = true
            deriveHealthFromSnapshots(for: .now)

            if healthSleepHours == nil {
                healthSleepHours = await HealthKitService.shared.fetchLastNightSleepHours()
            }
            if healthStepCount == nil {
                healthStepCount = await HealthKitService.shared.fetchTodayStepCount()
            }
            if healthRestingHR == nil {
                healthRestingHR = await HealthKitService.shared.fetchLatestRestingHeartRate()
            }
            if healthHRV == nil {
                healthHRV = await HealthKitService.shared.fetchHrvSdnn(on: .now)
            }
        }

        await importTodayWaterFromHealthIfNeeded()
    }

    private func importTodayWaterFromHealthIfNeeded() async {
        guard syncWaterWithHealth else { return }
        guard let session = activeSession else { return }
        let today = Calendar.current.startOfDay(for: .now)
        let externalSamples = await HealthKitService.shared.fetchNewExternalWaterSamples(on: today)
        guard !externalSamples.isEmpty else { return }

        var importedIDs: [UUID] = []
        var importedCount = 0
        var knownEntries: [(date: Date, volumeMl: Double)] = session.waters.compactMap { entry in
            guard let volumeMl = entry.volumeMl else { return nil }
            return (entry.createdAt, volumeMl)
        }

        for sample in externalSamples {
            let duplicate = knownEntries.contains { known in
                let closeVolume = abs(known.volumeMl - sample.volumeMl) < 1
                let closeDate = abs(known.date.timeIntervalSince(sample.date)) < 90
                return closeVolume && closeDate
            }

            importedIDs.append(sample.id)
            guard !duplicate else { continue }

            sessionService.addWater(
                to: session,
                context: context,
                profile: profile,
                createdAt: sample.date,
                volumeMl: sample.volumeMl,
                source: .healthKit
            )
            knownEntries.append((sample.date, sample.volumeMl))
            importedCount += 1
        }

        HealthKitService.shared.markWaterSamplesAsImported(importedIDs, on: today)
        if importedCount > 0 {
            HealthKitService.shared.recordWaterSync(direction: .importFromHealth)
            infoMessage = L10n.format("Импортировано из Apple Health: %d записей воды", importedCount)
        }
    }

    private func recordRiskModelRun(
        variant: String,
        confidencePercent: Int,
        morningProbability: Int,
        memoryProbability: Int
    ) {
        let calendar = Calendar.current
        let day = calendar.startOfDay(for: .now)
        let predicate = #Predicate<RiskModelRun> { run in
            run.day == day && run.variant == variant
        }
        var descriptor = FetchDescriptor<RiskModelRun>(predicate: predicate)
        descriptor.fetchLimit = 1
        if let existing = try? context.fetch(descriptor).first {
            existing.confidencePercent = confidencePercent
            existing.morningProbability = morningProbability
            existing.memoryProbability = memoryProbability
            existing.updatedAt = Date.now
        } else {
            let run = RiskModelRun(
                day: day,
                variant: variant,
                confidencePercent: confidencePercent,
                morningProbability: morningProbability,
                memoryProbability: memoryProbability
            )
            context.insert(run)
        }
        try? context.save()
    }

    private func updateModelQualityMetricsIfPossible() {
        let calendar = Calendar.current
        var changed = false

        for session in sessions where session.morningCheckIn != nil {
            let wellbeing = max(0, min(5, session.morningCheckIn?.wellbeingScore ?? 5))
            let observed = insightService.observedMorningProbability(for: wellbeing)
            let day = calendar.startOfDay(for: session.startAt)
            let dayRuns = riskModelRuns.filter { run in
                run.day == day && (run.variant == "coreml-shadow-v1" || run.variant == riskModelVariant)
            }

            for run in dayRuns {
                let error = abs(run.morningProbability - observed)
                let predicted = Double(run.morningProbability) / 100
                let observedNormalized = Double(observed) / 100
                let brier = (predicted - observedNormalized) * (predicted - observedNormalized)

                if run.observedWellbeingScore != wellbeing ||
                    run.observedMorningProbability != observed ||
                    run.absoluteErrorPercent != error ||
                    run.brierScore != brier
                {
                    run.observedWellbeingScore = wellbeing
                    run.observedMorningProbability = observed
                    run.absoluteErrorPercent = error
                    run.brierScore = brier
                    run.updatedAt = .now
                    changed = true
                }
            }
        }

        if changed {
            try? context.save()
        }
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

    private func syncSmartReminder(sessionID: UUID, insights: EveningInsightAssessment) async {
        guard profile?.notificationsEnabled == true else {
            NotificationService.shared.cancelHydrationNudge()
            NotificationService.shared.cancelSmartRiskNudge()
            NotificationService.shared.cancelWellbeingCheck()
            return
        }
        let status = await NotificationService.shared.authorizationStatus()
        guard status == .authorized || status == .provisional || status == .ephemeral else {
            NotificationService.shared.cancelHydrationNudge()
            NotificationService.shared.cancelSmartRiskNudge()
            NotificationService.shared.cancelWellbeingCheck()
            return
        }

        await NotificationService.shared.scheduleHydrationNudge(
            for: sessionID,
            requiredMl: insights.waterBalance.suggestedTopUpMl,
            after: safetyModeEnabled ? 8 * 60 : 20 * 60
        )

        await NotificationService.shared.scheduleSmartRiskNudge(
            for: sessionID,
            morningRisk: insights.morningRisk,
            memoryRisk: insights.memoryRisk,
            waterDeficitMl: insights.waterBalance.deficitMl
        )

        await NotificationService.shared.scheduleWellbeingCheck(
            for: sessionID,
            morningRisk: insights.morningRisk,
            memoryRisk: insights.memoryRisk
        )
    }

    private func liveActivityTaskID(
        session: Session,
        currentBAC: Double,
        soberAt: Date?,
        waterConsumed: Int,
        waterTarget: Int,
        risk: InsightLevel
    ) -> String {
        let minuteBucket = Int(Date.now.timeIntervalSince1970 / 60)
        let soberBucket = Int((soberAt?.timeIntervalSince1970 ?? 0) / 60)
        return "\(session.id.uuidString)-\(String(format: "%.3f", currentBAC))-\(soberBucket)-\(waterConsumed)-\(waterTarget)-\(risk.rawValue)-\(minuteBucket)"
    }

    private func sessionByID(_ id: UUID) -> Session? {
        sessions.first(where: { $0.id == id })
    }

    private func waterStatusColor(_ status: WaterBalanceStatus) -> Color {
        switch status {
        case .balanced:
            return .green
        case .mildDeficit:
            return .orange
        case .highDeficit:
            return .red
        }
    }

    private func presentPendingRouteIfNeeded() {
        if appState.pendingOpenLatestMorningCheckIn {
            if let session = latestSessionWithoutCheckIn {
                activeSheet = .checkIn(session.id)
            } else {
                infoMessage = L10n.tr("Нет доступного чек-ина для последней сессии")
            }
            appState.pendingOpenLatestMorningCheckIn = false
            return
        }

        if let sessionID = appState.pendingMorningCheckInSessionID,
           let session = sessionByID(sessionID),
           session.morningCheckIn == nil {
            activeSheet = .checkIn(sessionID)
            return
        }

        if appState.pendingMorningCheckInSessionID != nil {
            appState.pendingMorningCheckInSessionID = nil
            infoMessage = L10n.tr("Чек-ин уже заполнен или сессия не найдена")
        }
    }
}

private struct TimelineSection: View {
    let session: Session
    let onDeleteDrink: (DrinkEntry) -> Void
    let onDeleteMeal: (MealEntry) -> Void
    let onDeleteWater: (WaterEntry) -> Void

    private var events: [SessionEvent] {
        let drinkEvents = session.drinks.map(SessionEvent.drink)
        let mealEvents = session.meals.map(SessionEvent.meal)
        let waterEvents = session.waters.map(SessionEvent.water)
        return (drinkEvents + mealEvents + waterEvents).sorted { $0.date > $1.date }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Лента событий")
                .font(.headline)

            if events.isEmpty {
                Text("Пока нет записей")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(events) { event in
                    switch event {
                    case .drink(let drink):
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text((drink.title ?? drink.category.label).localized)
                                Text(drink.createdAt, style: .time)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(L10n.format("%d мл @ %d%%", Int(drink.volumeMl), Int(drink.abvPercent)))
                                .font(.footnote)
                        }
                        .swipeActions {
                            Button(role: .destructive) {
                                onDeleteDrink(drink)
                            } label: {
                                Label("Удалить", systemImage: "trash")
                            }
                        }
                    case .water(let water):
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Вода")
                                Text(water.createdAt, style: .time)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(water.volumeMl.map { L10n.format("%d мл", Int($0)) } ?? L10n.tr("Отметка"))
                                .font(.footnote)
                        }
                        .swipeActions {
                            Button(role: .destructive) {
                                onDeleteWater(water)
                            } label: {
                                Label("Удалить", systemImage: "trash")
                            }
                        }
                    case .meal(let meal):
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text((meal.title ?? "Прием пищи").localized)
                                Text(meal.createdAt, style: .time)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(meal.size.label)
                                .font(.footnote)
                        }
                        .swipeActions {
                            Button(role: .destructive) {
                                onDeleteMeal(meal)
                            } label: {
                                Label("Удалить", systemImage: "trash")
                            }
                        }
                    }
                    Divider()
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.thinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}

private struct EveningInsightsCard: View {
    let insights: EveningInsightAssessment
    let shadowAssessment: ShadowRiskAssessment?
    let recoveryIndex: RecoveryIndexSnapshot
    let patterns: PersonalizedPatternAssessment
    let scenarios: [EveningScenario]
    let projections: [MemoryProjection]
    let onOpenGlossary: () -> Void
    let onOpenForecast: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Аналитика вечера (примерно)")
                    .font(.headline)
                Spacer()
                Button {
                    onOpenGlossary()
                } label: {
                    Label("Термины", systemImage: "questionmark.circle")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            riskRow(
                title: L10n.tr("Насколько тяжело утром"),
                level: insights.morningRisk,
                percent: insights.morningProbabilityPercent,
                reason: insights.morningReasons.first ?? "Данных пока мало"
            )

            riskRow(
                title: L10n.tr("Риск провалов памяти"),
                level: insights.memoryRisk,
                percent: insights.memoryProbabilityPercent,
                reason: insights.memoryReasons.first ?? "Данных пока мало"
            )

            if let shadowAssessment {
                Divider()
                VStack(alignment: .leading, spacing: 6) {
                    Text(L10n.tr("Shadow-прогноз (на основе ваших данных)"))
                        .font(.subheadline.weight(.semibold))
                    switch shadowAssessment.status {
                    case .ready:
                        HStack {
                            Text(L10n.tr("Насколько тяжело утром"))
                            Spacer()
                            Text("~\(shadowAssessment.morningProbabilityPercent ?? 0)%")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(.orange)
                        }
                        HStack {
                            Text(L10n.tr("Риск провалов памяти"))
                            Spacer()
                            Text("~\(shadowAssessment.memoryProbabilityPercent ?? 0)%")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(.orange)
                        }
                        HStack {
                            Text(L10n.tr("Уверенность shadow-модели"))
                            Spacer()
                            Text("~\(shadowAssessment.confidencePercent)%")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                    case .insufficientData:
                        Text(L10n.tr("Персональных данных пока недостаточно для shadow-прогноза."))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    Text(shadowAssessment.note)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(L10n.tr("Уверенность модели"))
                    Spacer()
                    Text("~\(insights.confidence.scorePercent)%")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(confidenceColor(insights.confidence.level))
                }
                ProgressView(value: Double(insights.confidence.scorePercent) / 100)
                    .tint(confidenceColor(insights.confidence.level))
                ForEach(insights.confidence.reasons, id: \.self) { line in
                    Text("• \(line)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                HStack {
                    Text(L10n.tr("Индекс восстановления"))
                    Spacer()
                    Text("\(recoveryIndex.score)/100")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(confidenceColor(recoveryIndex.level))
                }
                ProgressView(value: Double(recoveryIndex.score) / 100)
                    .tint(confidenceColor(recoveryIndex.level))
                Text(recoveryIndex.headline.capitalized)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Text("Ваш peak порог риска: ~\(String(format: "%.3f", patterns.peakRiskThreshold))")
                .font(.footnote)
                .foregroundStyle(.secondary)
            Text("Ваш темп-порог: ~\(String(format: "%.1f", patterns.paceRiskThreshold)) ст.др./ч")
                .font(.footnote)
                .foregroundStyle(.secondary)
            Text(L10n.format("Серия воды: %d · Серия еды: %d", patterns.waterStreak, patterns.mealStreak))
                .font(.footnote)
                .foregroundStyle(.secondary)

            Text(L10n.format("Еда: %@", insights.mealImpact))
                .font(.footnote)
                .foregroundStyle(.secondary)

            Divider()

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(L10n.tr("Водный баланс"))
                    Spacer()
                    Text(insights.waterBalance.status.title.capitalized)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(waterStatusColor(insights.waterBalance.status))
                }
                Text("\(insights.waterBalance.consumedMl) мл из ~\(insights.waterBalance.targetMl) мл")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                ProgressView(value: insights.waterBalance.progress)
                if insights.waterBalance.deficitMl > 0 {
                    Text(L10n.format("Дефицит: ~%d мл", insights.waterBalance.deficitMl))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Text(L10n.format("Сейчас лучше допить ~%d мл", insights.waterBalance.suggestedTopUpMl))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                if insights.waterBalance.unknownMarksCount > 0 {
                    Text("Есть \(insights.waterBalance.unknownMarksCount) отметок воды без объема")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if !insights.riskEvents.isEmpty {
                Divider()

                VStack(alignment: .leading, spacing: 8) {
                    Text(L10n.tr("События риска"))
                        .font(.subheadline.weight(.semibold))
                    ForEach(insights.riskEvents.prefix(5)) { event in
                        VStack(alignment: .leading, spacing: 3) {
                            HStack {
                                Text(event.title)
                                    .font(.footnote.weight(.semibold))
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
            }

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Text("Сценарии на ближайший час")
                    .font(.subheadline.weight(.semibold))
                ForEach(scenarios) { scenario in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(scenario.title)
                            .font(.footnote.weight(.semibold))
                        Text(scenario.subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(scenario.impactText)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(scenario.recommendation)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(uiColor: .secondarySystemGroupedBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }
            }

            if !projections.isEmpty {
                Divider()

                VStack(alignment: .leading, spacing: 6) {
                    Text(L10n.tr("Проекция риска провалов памяти"))
                        .font(.subheadline.weight(.semibold))
                    ForEach(projections) { projection in
                        HStack {
                            Text("+\(projection.horizonMinutes) мин")
                                .font(.footnote.weight(.semibold))
                            Spacer()
                            Text("~\(projection.memoryProbabilityPercent)%")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                        Text(projection.comment)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 6) {
                Text("Что сделать сейчас")
                    .font(.subheadline.weight(.semibold))
                ForEach(insights.actionsNow, id: \.self) { action in
                    Text("• \(action)")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            Text("Это эвристика на основе BAC, темпа, длительности и воды.")
                .font(.caption)
                .foregroundStyle(.secondary)

            Button("Подробнее по прогнозу") {
                onOpenForecast()
            }
            .buttonStyle(.bordered)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private func riskRow(title: String, level: InsightLevel, percent: Int, reason: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                Spacer()
                HStack(spacing: 6) {
                    Text(level.title.capitalized)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(levelColor(level))
                    Text("~\(percent)%")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Text(reason)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
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

    private func waterStatusColor(_ status: WaterBalanceStatus) -> Color {
        switch status {
        case .balanced:
            return .green
        case .mildDeficit:
            return .orange
        case .highDeficit:
            return .red
        }
    }

    private func confidenceColor(_ level: InsightLevel) -> Color {
        switch level {
        case .low:
            return .green
        case .medium:
            return .orange
        case .high:
            return .red
        }
    }
}

private struct AddDrinkFlowSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @AppStorage("favoritePresetIDs") private var favoritePresetIDs = ""

    let session: Session
    let profile: UserProfile?
    let recentPresets: [DrinkPresetModel]

    private let service = SessionService()
    private let insightService = SessionInsightService()
    private let groupedDefaults = DrinkCatalog.groupedDefaults
    @State private var searchText = ""

    private var trimmedSearchText: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var filteredRecentPresets: [DrinkPresetModel] {
        Array(recentPresets.filter(matchesPreset).prefix(5))
    }

    private var favoritePresets: [DrinkPresetModel] {
        let ids = favoritePresetIDSet
        return DrinkCatalog.defaults.filter { ids.contains($0.id) && matchesPreset($0) }
    }

    private var filteredGroups: [(DrinkPresetGroup, [DrinkPresetModel])] {
        groupedDefaults.compactMap { group, presets in
            let filtered = presets.filter(matchesPreset)
            return filtered.isEmpty ? nil : (group, filtered)
        }
    }

    private var hasNoResults: Bool {
        !trimmedSearchText.isEmpty && filteredRecentPresets.isEmpty && filteredGroups.isEmpty
    }

    var body: some View {
        NavigationStack {
            List {
                if !favoritePresets.isEmpty {
                    Section("Избранное") {
                        ForEach(favoritePresets) { preset in
                            presetRowWithFavorite(preset)
                        }
                    }
                }

                if !filteredRecentPresets.isEmpty {
                    Section("Недавние") {
                        ForEach(filteredRecentPresets) { preset in
                            presetRowWithFavorite(preset)
                        }
                    }
                }

                ForEach(filteredGroups, id: \.0.id) { group, presets in
                    Section(group.title) {
                        ForEach(presets) { preset in
                            presetRowWithFavorite(preset)
                        }
                    }
                }

                if hasNoResults {
                    Section {
                        Text("По запросу ничего не найдено")
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Другое / Коктейль") {
                    NavigationLink("Открыть детали напитка") {
                        AddDrinkDetailsView(session: session, profile: profile)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always), prompt: "Поиск напитка или коктейля")
            .navigationTitle("Добавить напиток")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") {
                        dismiss()
                    }
                }
            }
        }
    }

    private func presetRow(_ preset: DrinkPresetModel) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text(preset.title.localized)
                    .foregroundStyle(.primary)
                Text(preset.subtitle.localized)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(L10n.format("%d мл @ %d%%", Int(preset.volumeMl), Int(preset.abv)))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: iconName(for: preset.category))
                .foregroundStyle(.tint)
        }
    }

    private func presetRowWithFavorite(_ preset: DrinkPresetModel) -> some View {
        HStack {
            Button {
                savePreset(preset)
            } label: {
                presetRow(preset)
            }
            .buttonStyle(.plain)

            Button {
                toggleFavorite(preset)
            } label: {
                Image(systemName: favoritePresetIDSet.contains(preset.id) ? "star.fill" : "star")
                    .foregroundStyle(.yellow)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(favoritePresetIDSet.contains(preset.id) ? "Убрать из избранного" : "Добавить в избранное")
        }
    }

    private func matchesPreset(_ preset: DrinkPresetModel) -> Bool {
        guard !trimmedSearchText.isEmpty else { return true }
        return preset.title.localized.localizedCaseInsensitiveContains(trimmedSearchText)
            || preset.subtitle.localized.localizedCaseInsensitiveContains(trimmedSearchText)
            || preset.title.localizedCaseInsensitiveContains(trimmedSearchText)
            || preset.subtitle.localizedCaseInsensitiveContains(trimmedSearchText)
            || preset.category.label.localizedCaseInsensitiveContains(trimmedSearchText)
    }

    private var favoritePresetIDSet: Set<String> {
        Set(
            favoritePresetIDs
                .split(separator: ",")
                .map { String($0) }
        )
    }

    private func toggleFavorite(_ preset: DrinkPresetModel) {
        var ids = favoritePresetIDSet
        if ids.contains(preset.id) {
            ids.remove(preset.id)
        } else {
            ids.insert(preset.id)
        }
        favoritePresetIDs = ids.sorted().joined(separator: ",")
    }

    private func iconName(for category: DrinkEntry.Category) -> String {
        switch category {
        case .beer: return "mug.fill"
        case .wine: return "wineglass.fill"
        case .spirits, .liqueur: return "flame.fill"
        case .cocktail: return "martini.glass.fill"
        case .cider, .seltzer: return "sparkles"
        case .other: return "plus.circle.fill"
        }
    }

    private func savePreset(_ preset: DrinkPresetModel) {
        service.addDrink(
            to: session,
            context: context,
            profile: profile,
            createdAt: .now,
            volumeMl: preset.volumeMl,
            abvPercent: preset.abv,
            title: preset.title,
            category: preset.category
        )
        scheduleHydrationNudgeIfNeeded()
        dismiss()
    }

    private func scheduleHydrationNudgeIfNeeded() {
        guard profile?.notificationsEnabled == true else { return }
        let assessment = insightService.assess(session: session, profile: profile)
        let requiredMl = assessment.waterBalance.suggestedTopUpMl

        Task {
            let status = await NotificationService.shared.authorizationStatus()
            guard status == .authorized || status == .provisional || status == .ephemeral else { return }

            if requiredMl > 0 {
                await NotificationService.shared.scheduleHydrationNudge(for: session.id, requiredMl: requiredMl)
            } else {
                NotificationService.shared.cancelHydrationNudge()
            }
        }
    }
}

private struct AddDrinkDetailsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    let session: Session
    let profile: UserProfile?

    @State private var customTitle = ""
    @State private var customVolume = 250.0
    @State private var customABV = 8.0
    @State private var customTime = Date.now
    @State private var customCategory: DrinkEntry.Category = .cocktail
    @State private var showHighABVWarning = false

    private let service = SessionService()
    private let insightService = SessionInsightService()

    var body: some View {
        Form {
            Picker("Категория", selection: $customCategory) {
                ForEach(DrinkEntry.Category.allCases) { category in
                    Text(category.label).tag(category)
                }
            }

            TextField("Название (опционально)", text: $customTitle)

            Stepper(value: $customVolume, in: 10...2000, step: 10) {
                HStack {
                    Text("Объем")
                    Spacer()
                    Text("\(Int(customVolume)) мл")
                }
            }

            Stepper(value: $customABV, in: 0.5...96, step: 0.5) {
                HStack {
                    Text("Крепость")
                    Spacer()
                    Text(String(format: "%.1f%%", customABV))
                }
            }

            DatePicker("Время", selection: $customTime, displayedComponents: [.date, .hourAndMinute])

            Button("Добавить") {
                if customABV > 80 {
                    showHighABVWarning = true
                } else {
                    save()
                }
            }
            .disabled(customVolume <= 0 || customABV <= 0)
        }
        .navigationTitle("Детали напитка")
        .alert("Высокая крепость", isPresented: $showHighABVWarning) {
            Button("Добавить") { save() }
            Button("Исправить", role: .cancel) {}
        } message: {
            Text("Крепость выше 80%. Проверьте значение и подтвердите добавление.")
        }
    }

    private func save() {
        service.addDrink(
            to: session,
            context: context,
            profile: profile,
            createdAt: customTime,
            volumeMl: customVolume,
            abvPercent: customABV,
            title: customTitle.isEmpty ? nil : customTitle,
            category: customCategory
        )
        scheduleHydrationNudgeIfNeeded()
        dismiss()
    }

    private func scheduleHydrationNudgeIfNeeded() {
        guard profile?.notificationsEnabled == true else { return }
        let assessment = insightService.assess(session: session, profile: profile)
        let requiredMl = assessment.waterBalance.suggestedTopUpMl

        Task {
            let status = await NotificationService.shared.authorizationStatus()
            guard status == .authorized || status == .provisional || status == .ephemeral else { return }

            if requiredMl > 0 {
                await NotificationService.shared.scheduleHydrationNudge(for: session.id, requiredMl: requiredMl)
            } else {
                NotificationService.shared.cancelHydrationNudge()
            }
        }
    }
}

private struct AddMealSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    let session: Session
    let profile: UserProfile?

    @State private var title = ""
    @State private var size: MealEntry.MealSize = .regular
    @State private var createdAt = Date.now

    private let service = SessionService()

    var body: some View {
        NavigationStack {
            Form {
                Section("Быстро добавить") {
                    HStack {
                        quickButton(.snack)
                        quickButton(.regular)
                        quickButton(.heavy)
                    }
                }

                Section("Детали приема пищи") {
                    TextField("Название (опционально)", text: $title)
                    Picker("Размер", selection: $size) {
                        ForEach(MealEntry.MealSize.allCases) { value in
                            Text(value.label).tag(value)
                        }
                    }
                    DatePicker("Время", selection: $createdAt, displayedComponents: [.date, .hourAndMinute])
                }

                Section {
                    Button("Добавить прием пищи") {
                        save(size: size, title: title.isEmpty ? nil : title, date: createdAt)
                    }
                }
            }
            .navigationTitle("+ Еда")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Закрыть") { dismiss() }
                }
            }
        }
    }

    private func quickButton(_ quickSize: MealEntry.MealSize) -> some View {
        Button(shortLabel(for: quickSize)) {
            save(size: quickSize, title: quickSize.label, date: .now)
        }
        .buttonStyle(.bordered)
        .frame(maxWidth: .infinity)
    }

    private func shortLabel(for size: MealEntry.MealSize) -> String {
        switch size {
        case .snack:
            return "Перекус"
        case .regular:
            return "Обычный"
        case .heavy:
            return "Плотный"
        }
    }

    private func save(size: MealEntry.MealSize, title: String?, date: Date) {
        service.addMeal(
            to: session,
            context: context,
            profile: profile,
            createdAt: date,
            title: title,
            size: size
        )
        dismiss()
    }
}

private struct AddWaterSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    let session: Session
    let profile: UserProfile?

    @State private var selectedVolume = 250.0
    @State private var showSavedHint = false

    private let service = SessionService()
    private let insightService = SessionInsightService()

    var body: some View {
        NavigationStack {
            Form {
                Section("Быстрый объем") {
                    HStack {
                        quickVolumeButton(200)
                        quickVolumeButton(300)
                        quickVolumeButton(500)
                    }
                }

                Section {
                    Stepper(value: $selectedVolume, in: 50...2000, step: 50) {
                        HStack {
                            Text("Свой объем")
                            Spacer()
                            Text("\(Int(selectedVolume)) мл")
                        }
                    }
                }

                Section {
                    Button("Добавить воду") {
                        save(volume: selectedVolume)
                    }
                    Button("Просто отметил(а)") {
                        save(volume: nil)
                    }
                }

                if showSavedHint {
                    Text("Сохранено")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("+ Вода")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Закрыть") {
                        dismiss()
                    }
                }
            }
        }
    }

    private func quickVolumeButton(_ volume: Double) -> some View {
        Button("\(Int(volume))") {
            save(volume: volume)
        }
        .buttonStyle(.bordered)
        .frame(maxWidth: .infinity)
    }

    private func save(volume: Double?) {
        service.addWater(to: session, context: context, profile: profile, volumeMl: volume)
        scheduleHydrationNudgeIfNeeded()
        showSavedHint = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            dismiss()
        }
    }

    private func scheduleHydrationNudgeIfNeeded() {
        guard profile?.notificationsEnabled == true else { return }
        let assessment = insightService.assess(session: session, profile: profile)
        let requiredMl = assessment.waterBalance.suggestedTopUpMl

        Task {
            let status = await NotificationService.shared.authorizationStatus()
            guard status == .authorized || status == .provisional || status == .ephemeral else { return }

            if requiredMl > 0 {
                await NotificationService.shared.scheduleHydrationNudge(for: session.id, requiredMl: requiredMl)
            } else {
                NotificationService.shared.cancelHydrationNudge()
            }
        }
    }
}

private struct PromilleInfoSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text(L10n.tr("Промилле (‰) в приложении"))
                        .font(.headline)
                    Text(L10n.tr("Промилле (‰) в приложении - это приблизительная оценка концентрации алкоголя в крови по модели, а не медицинское измерение."))
                        .font(.body)
                    Text(L10n.tr("Фактическое состояние может отличаться из-за сна, еды, самочувствия, лекарств и других факторов."))
                        .font(.body)
                    Text(L10n.tr("Эти данные только для личного harm-reduction трекинга и не подходят для решений о вождении, безопасности, медицине или законе."))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
            }
            .navigationTitle(L10n.tr("Как понимать промилле"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.tr("Закрыть")) {
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

private struct EndSessionSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    let session: Session
    let profile: UserProfile?

    @State private var remindMorningCheckIn = true
    @State private var remindWaterAtBed = true
    @State private var showEmptySessionChoice = false

    private let service = SessionService()

    var body: some View {
        NavigationStack {
            Form {
                Section("Итог") {
                    Text("Пик BAC (примерно): \(String(format: "%.3f", session.cachedPeakBAC))")
                    Text(L10n.format("Пик промилле (примерно): %.2f‰", session.cachedPeakBAC * 10))
                    if let sober = session.cachedEstimatedSoberAt {
                        Text("До ~0.00: \(sober, format: .dateTime.hour().minute())")
                    } else {
                        Text("До ~0.00: 0.00 сейчас")
                    }
                    if let lastDrink = session.drinks.sorted(by: { $0.createdAt > $1.createdAt }).first {
                        Text("Последний напиток: \(lastDrink.createdAt, format: .dateTime.hour().minute())")
                    }
                    if let lastMeal = session.meals.sorted(by: { $0.createdAt > $1.createdAt }).first {
                        Text("Последний прием пищи: \(lastMeal.createdAt, format: .dateTime.hour().minute())")
                    }
                }

                Section("Напоминания") {
                    Toggle("Утренний чек-ин", isOn: $remindMorningCheckIn)
                    Toggle("Напомнить воды перед сном", isOn: $remindWaterAtBed)
                }

                Section {
                    Button("Завершить") {
                        if session.drinks.isEmpty && session.waters.isEmpty && session.meals.isEmpty {
                            showEmptySessionChoice = true
                        } else {
                            finish(deleteIfEmpty: false)
                        }
                    }
                }
            }
            .navigationTitle("Завершить сессию")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") {
                        dismiss()
                    }
                }
            }
            .alert("Сессия пустая", isPresented: $showEmptySessionChoice) {
                Button("Удалить пустую сессию", role: .destructive) {
                    finish(deleteIfEmpty: true)
                }
                Button("Завершить без данных") {
                    finish(deleteIfEmpty: false)
                }
                Button("Отмена", role: .cancel) {}
            } message: {
                Text("Вы начали сессию, но не добавили записи.")
            }
        }
    }

    private func finish(deleteIfEmpty: Bool) {
        service.endSession(session, context: context, profile: profile)

        if deleteIfEmpty && session.drinks.isEmpty && session.waters.isEmpty && session.meals.isEmpty {
            service.deleteEmptySessionIfNeeded(session, context: context)
        }

        Task {
            await NotificationService.shared.cancelWaterReminders()
            NotificationService.shared.cancelHydrationNudge()
            NotificationService.shared.cancelSmartRiskNudge()
            NotificationService.shared.cancelWellbeingCheck()
            _ = await LiveSessionActivityService.shared.end(sessionID: session.id)
            WidgetSnapshotStore.clear()
            guard remindWaterAtBed || remindMorningCheckIn else { return }
            guard profile?.notificationsEnabled == true else { return }
            var status = await NotificationService.shared.authorizationStatus()
            if status == .notDetermined {
                _ = await NotificationService.shared.requestAuthorization()
                status = await NotificationService.shared.authorizationStatus()
            }
            guard status == .authorized || status == .provisional || status == .ephemeral else { return }
            if remindWaterAtBed {
                await NotificationService.shared.scheduleBedtimeWater(for: session.id)
            }
            if remindMorningCheckIn {
                let target = nextMorningDate()
                await NotificationService.shared.scheduleMorningCheckIn(for: session.id, at: target)
            }
        }

        dismiss()
    }

    private func nextMorningDate() -> Date {
        let calendar = Calendar.current
        let now = Date.now

        var components = calendar.dateComponents([.year, .month, .day], from: now)
        components.hour = 9
        components.minute = 0

        let todayAtNine = calendar.date(from: components) ?? now.addingTimeInterval(3600)
        if now < todayAtNine {
            return todayAtNine
        }

        return calendar.date(byAdding: .day, value: 1, to: todayAtNine) ?? now.addingTimeInterval(3600 * 12)
    }
}
