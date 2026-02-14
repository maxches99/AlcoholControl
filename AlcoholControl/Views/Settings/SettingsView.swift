import SwiftUI
import SwiftData

struct SettingsView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.openURL) private var openURL
    @Query private var profiles: [UserProfile]
    @Query private var sessions: [Session]
    @Query private var drinks: [DrinkEntry]
    @Query private var waters: [WaterEntry]
    @Query private var meals: [MealEntry]
    @Query private var checkIns: [MorningCheckIn]
    @Query(sort: [SortDescriptor<RiskModelRun>(\.updatedAt, order: .reverse)]) private var riskModelRuns: [RiskModelRun]

    @StateObject private var purchase = PurchaseService.shared

    @State private var weight = 70.0
    @State private var unitSystem: UserProfile.UnitSystem = .metric
    @State private var sex: UserProfile.BiologicalSex = .unspecified
    @State private var hideBACInSharing = true
    @State private var isInitialized = false
    @State private var showDeleteConfirm = false
    @State private var showPaywall = false
    @State private var showSafetyCenter = false
    @State private var statusMessage = ""
    @State private var connectingHealth = false
    @State private var csvExportURL: URL?
    @State private var jsonExportURL: URL?
    @AppStorage("selectedAppLanguage") private var selectedAppLanguage = AppLanguage.system.rawValue
    @AppStorage("goalStdDrinks") private var goalStdDrinks = 4.0
    @AppStorage("goalWaterMl") private var goalWaterMl = 1200.0
    @AppStorage("goalEndHour") private var goalEndHour = 1
    @AppStorage("preSessionPlanEnabled") private var preSessionPlanEnabled = true
    @AppStorage("autoFinishSuggestionHours") private var autoFinishSuggestionHours = 6
    @AppStorage("trustedContactName") private var trustedContactName = ""
    @AppStorage("trustedContactPhone") private var trustedContactPhone = ""
    @AppStorage("liveActivityEnabled") private var liveActivityEnabled = true
    @AppStorage(HealthKitService.StorageKey.syncWaterWithHealth) private var syncWaterWithHealth = true
    @AppStorage(HealthKitService.StorageKey.waterLastSyncAt) private var waterLastSyncAt = 0.0
    @AppStorage(HealthKitService.StorageKey.waterLastSyncDirection) private var waterLastSyncDirection = ""
    @AppStorage("safetyModeEnabled") private var safetyModeEnabled = false
    @AppStorage("weeklyHeavyMorningLimit") private var weeklyHeavyMorningLimit = 2
    @AppStorage("weeklyHighMemoryRiskLimit") private var weeklyHighMemoryRiskLimit = 2
    @AppStorage("weeklyHydrationHitTarget") private var weeklyHydrationHitTarget = 70
    @AppStorage("shadowRiskModeEnabled") private var shadowRiskModeEnabled = true
    @AppStorage("shadowRolloutMinHistory") private var shadowRolloutMinHistory = 5
    @AppStorage("shadowRolloutMinConfidence") private var shadowRolloutMinConfidence = 55
    @AppStorage("riskModelVariant") private var riskModelVariant = "A"

    private let service = SessionService()
    private let exportService = DataExportService()

    init() {
        _profiles = Query()
        _sessions = Query()
        _drinks = Query()
        _waters = Query()
        _meals = Query()
        _checkIns = Query()
        _riskModelRuns = Query(sort: [SortDescriptor<RiskModelRun>(\.updatedAt, order: .reverse)])
    }

    private var profile: UserProfile? {
        profiles.first
    }

    private var waterSyncStatusText: String {
        guard waterLastSyncAt > 0 else {
            return L10n.tr("Последняя синхронизация воды: пока нет данных")
        }

        let date = Date(timeIntervalSince1970: waterLastSyncAt)
        let timestamp = date.formatted(date: .abbreviated, time: .shortened)
        let directionText: String
        switch waterLastSyncDirection {
        case HealthKitService.WaterSyncDirection.importFromHealth.rawValue:
            directionText = L10n.tr("импорт из Apple Health")
        case HealthKitService.WaterSyncDirection.exportToHealth.rawValue:
            directionText = L10n.tr("экспорт в Apple Health")
        default:
            directionText = L10n.tr("синхронизация")
        }

        return L10n.format("Последняя синхронизация воды: %@ (%@)", timestamp, directionText)
    }

    private var latestShadowRun: RiskModelRun? {
        riskModelRuns.first(where: { $0.variant == "coreml-shadow-v1" })
    }

    private var shadowQualitySummary: String {
        let shadowRuns = riskModelRuns.filter {
            $0.variant == "coreml-shadow-v1" &&
            $0.absoluteErrorPercent != nil &&
            $0.brierScore != nil
        }
        guard !shadowRuns.isEmpty else {
            return L10n.tr("Качество shadow-модели появится после первых утренних check-in с прогнозом.")
        }

        let shadowMAE = shadowRuns.compactMap(\.absoluteErrorPercent).map(Double.init).reduce(0, +) / Double(shadowRuns.count)
        let shadowBrier = shadowRuns.compactMap(\.brierScore).reduce(0, +) / Double(shadowRuns.count)

        let baselineByDay = Dictionary(uniqueKeysWithValues: riskModelRuns.compactMap { run -> (Date, Int)? in
            guard run.variant == riskModelVariant, let error = run.absoluteErrorPercent else { return nil }
            return (run.day, error)
        })
        let overlapping = shadowRuns.compactMap { run -> (Double, Double)? in
            guard let shadowError = run.absoluteErrorPercent,
                  let baselineError = baselineByDay[run.day]
            else { return nil }
            return (Double(shadowError), Double(baselineError))
        }

        let deltaText: String
        if overlapping.isEmpty {
            deltaText = L10n.tr("Сравнение с базовой моделью появится после накопления совпадающих дней.")
        } else {
            let delta = overlapping.map { $0.0 - $0.1 }.reduce(0, +) / Double(overlapping.count)
            if delta < -0.01 {
                deltaText = L10n.format("Средняя ошибка ниже базовой примерно на %.1f п.п.", abs(delta))
            } else if delta > 0.01 {
                deltaText = L10n.format("Средняя ошибка выше базовой примерно на %.1f п.п.", delta)
            } else {
                deltaText = L10n.tr("Средняя ошибка примерно на уровне базовой модели.")
            }
        }

        return L10n.format("MAE: %.1f п.п. · Brier: %.3f. %@", shadowMAE, shadowBrier, deltaText)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(L10n.tr("Профиль")) {
                    Picker(L10n.tr("Единицы"), selection: $unitSystem) {
                        Text(L10n.tr("Метрические")).tag(UserProfile.UnitSystem.metric)
                        Text(L10n.tr("Имперские")).tag(UserProfile.UnitSystem.imperial)
                    }

                    Stepper(value: $weight, in: 30...200, step: 1) {
                        HStack {
                            Text(L10n.tr("Вес"))
                            Spacer()
                            Text(String(format: "%.0f %@", weight, unitSystem == .metric ? "кг" : "lbs"))
                        }
                    }

                    Picker(L10n.tr("Пол (опционально)"), selection: $sex) {
                        ForEach(UserProfile.BiologicalSex.allCases) { value in
                            Text(value.label).tag(value)
                        }
                    }
                }

                Section(L10n.tr("Язык")) {
                    Picker(L10n.tr("Язык приложения"), selection: $selectedAppLanguage) {
                        ForEach(AppLanguage.allCases) { language in
                            Text(language.title).tag(language.rawValue)
                        }
                    }
                }

                Section(L10n.tr("Уведомления")) {
                    NavigationLink(L10n.tr("Настройки уведомлений")) {
                        NotificationsSettingsView()
                    }
                }

                Section(L10n.tr("Цели вечера")) {
                    Toggle(L10n.tr("Pre-session plan"), isOn: $preSessionPlanEnabled)

                    Stepper(value: $goalStdDrinks, in: 1...12, step: 0.5) {
                        HStack {
                            Text(L10n.tr("Лимит алкоголя"))
                            Spacer()
                            Text(String(format: "%.1f ст.др.", goalStdDrinks))
                                .foregroundStyle(.secondary)
                        }
                    }

                    Stepper(value: $goalWaterMl, in: 400...3000, step: 100) {
                        HStack {
                            Text(L10n.tr("Цель воды"))
                            Spacer()
                            Text("\(Int(goalWaterMl)) мл")
                                .foregroundStyle(.secondary)
                        }
                    }

                    Stepper(value: $goalEndHour, in: 0...23) {
                        HStack {
                            Text(L10n.tr("План завершить до"))
                            Spacer()
                            Text(String(format: "%02d:00", goalEndHour))
                                .foregroundStyle(.secondary)
                        }
                    }

                    Stepper(value: $autoFinishSuggestionHours, in: 2...12) {
                        HStack {
                            Text(L10n.tr("Авто-подсказка завершить через"))
                            Spacer()
                            Text("\(autoFinishSuggestionHours) ч")
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Section(L10n.tr("Недельные цели harm-reduction")) {
                    Stepper(value: $weeklyHeavyMorningLimit, in: 0...7) {
                        HStack {
                            Text(L10n.tr("Лимит тяжелых утр"))
                            Spacer()
                            Text("\(weeklyHeavyMorningLimit)")
                                .foregroundStyle(.secondary)
                        }
                    }
                    Stepper(value: $weeklyHighMemoryRiskLimit, in: 0...7) {
                        HStack {
                            Text(L10n.tr("Лимит сессий с высоким риском памяти"))
                            Spacer()
                            Text("\(weeklyHighMemoryRiskLimit)")
                                .foregroundStyle(.secondary)
                        }
                    }
                    Stepper(value: $weeklyHydrationHitTarget, in: 40...100, step: 5) {
                        HStack {
                            Text(L10n.tr("Цель гидратации в неделю"))
                            Spacer()
                            Text("\(weeklyHydrationHitTarget)%")
                                .foregroundStyle(.secondary)
                        }
                    }
                    Text(L10n.tr("Цели используются в разделе Аналитика для недельного контроля безопасности."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section(L10n.tr("Безопасность")) {
                    Toggle(L10n.tr("Safety mode"), isOn: $safetyModeEnabled)
                    if safetyModeEnabled {
                        Text(L10n.tr("Более ранние подсказки риска, акцент на паузы и воду, приоритет действий безопасности."))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Button(L10n.tr("Открыть центр безопасности")) {
                        showSafetyCenter = true
                    }

                    TextField(L10n.tr("Имя доверенного контакта"), text: $trustedContactName)
                        .textInputAutocapitalization(.words)

                    TextField(L10n.tr("Телефон доверенного контакта"), text: $trustedContactPhone)
                        .keyboardType(.phonePad)

                    if !trustedContactPhone.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Button(L10n.tr("Проверить звонок контакту")) {
                            callTrustedContact()
                        }
                    }
                }

                Section(L10n.tr("Интеграции")) {
                    Toggle(L10n.tr("Live Activity (beta)"), isOn: $liveActivityEnabled)
                    Toggle(isOn: $syncWaterWithHealth) {
                        Text(L10n.tr("Синхронизировать воду с Apple Health"))
                    }
                    Text(L10n.tr("Когда включено, вода импортируется из Apple Health и новые записи из приложения отправляются обратно в Health."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(waterSyncStatusText)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Button(connectingHealth ? L10n.tr("Подключаем Apple Health...") : L10n.tr("Подключить Apple Health (сон / вода / шаги / пульс)")) {
                        Task { await connectHealthKit() }
                    }
                    .disabled(connectingHealth)
                }

                Section(L10n.tr("CoreML shadow")) {
                    Toggle(L10n.tr("Включить shadow-прогноз"), isOn: $shadowRiskModeEnabled)
                    Text(L10n.tr("Версия модели: coreml-shadow-v1"))
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if let latestShadowRun {
                        Text(L10n.format("Последний успешный инференс: %@", latestShadowRun.updatedAt.formatted(date: .abbreviated, time: .shortened)))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text(L10n.tr("Последний успешный инференс: пока нет данных"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Stepper(value: $shadowRolloutMinHistory, in: 3...20) {
                        HStack {
                            Text(L10n.tr("Мин. завершенных сессий"))
                            Spacer()
                            Text("\(shadowRolloutMinHistory)")
                                .foregroundStyle(.secondary)
                        }
                    }

                    Stepper(value: $shadowRolloutMinConfidence, in: 30...95, step: 5) {
                        HStack {
                            Text(L10n.tr("Мин. уверенность для UI"))
                            Spacer()
                            Text("\(shadowRolloutMinConfidence)%")
                                .foregroundStyle(.secondary)
                        }
                    }

                    Text(L10n.tr("Shadow отображается только при достаточной истории и confidence-пороге; основной риск это не меняет."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(shadowQualitySummary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section(L10n.tr("Приватность")) {
                    Toggle(L10n.tr("Скрывать BAC в шаринге"), isOn: $hideBACInSharing)
                }

                Section(L10n.tr("Подписка")) {
                    Text(purchase.isPremium ? L10n.tr("Статус: Premium активен") : L10n.tr("Статус: базовый"))
                        .foregroundStyle(.secondary)
                    Button(purchase.isPremium ? L10n.tr("Управлять подпиской") : L10n.tr("Оформить Premium")) {
                        showPaywall = true
                    }
                    Button(L10n.tr("Restore purchases")) {
                        Task { await purchase.restoreFromAppStore() }
                    }
                }

                Section(L10n.tr("Управление данными")) {
                    Button(L10n.tr("Экспорт CSV")) {
                        exportCSV()
                    }
                    if let csvExportURL {
                        ShareLink(L10n.tr("Поделиться CSV"), item: csvExportURL)
                    }

                    Button(L10n.tr("Экспорт JSON-резерва")) {
                        exportJSON()
                    }
                    if let jsonExportURL {
                        ShareLink(L10n.tr("Поделиться JSON-резервом"), item: jsonExportURL)
                    }

                    Button(role: .destructive) {
                        showDeleteConfirm = true
                    } label: {
                        Text(L10n.tr("Удалить все данные"))
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
            .navigationTitle(L10n.tr("Настройки"))
            .task {
                await loadInitialStateIfNeeded()
                await purchase.restore()
            }
            .onChange(of: weight) { _, _ in saveProfileAndRecompute() }
            .onChange(of: unitSystem) { _, _ in saveProfileAndRecompute() }
            .onChange(of: sex) { _, _ in saveProfileAndRecompute() }
            .onChange(of: hideBACInSharing) { _, _ in saveProfileAndRecompute() }
            .alert(L10n.tr("Удалить все данные?"), isPresented: $showDeleteConfirm) {
                Button(L10n.tr("Удалить"), role: .destructive) {
                    deleteAllData()
                }
                Button(L10n.tr("Отмена"), role: .cancel) {}
            } message: {
                Text(L10n.tr("Удалятся все сессии, записи и чек-ины. Подписка сохранится отдельно."))
            }
            .sheet(isPresented: $showPaywall) {
                PaywallView()
            }
            .sheet(isPresented: $showSafetyCenter) {
                SafetyCenterView()
            }
        }
    }

    @MainActor
    private func loadInitialStateIfNeeded() async {
        guard !isInitialized else { return }
        isInitialized = true

        if let profile {
            weight = profile.weight
            unitSystem = profile.unitSystem
            sex = profile.sex
            hideBACInSharing = profile.hideBACInSharing
            return
        }

        do {
            let created = try service.fetchOrCreateProfile(context: context)
            weight = created.weight
            unitSystem = created.unitSystem
            sex = created.sex
            hideBACInSharing = created.hideBACInSharing
        } catch {
            statusMessage = L10n.tr("Не удалось загрузить профиль")
        }
    }

    @MainActor
    private func saveProfileAndRecompute() {
        guard isInitialized else { return }
        do {
            let profile = try service.upsertProfile(context: context, weight: weight, unitSystem: unitSystem, sex: sex)
            profile.hideBACInSharing = hideBACInSharing
            profile.updatedAt = .now
            try service.recomputeAllSessions(context: context, profile: profile)
        } catch {
            statusMessage = L10n.tr("Ошибка сохранения профиля")
        }
    }

    @MainActor
    private func deleteAllData() {
        for drink in drinks {
            context.delete(drink)
        }
        for water in waters {
            context.delete(water)
        }
        for meal in meals {
            context.delete(meal)
        }
        for checkIn in checkIns {
            context.delete(checkIn)
        }
        for session in sessions {
            context.delete(session)
        }
        if let profile {
            context.delete(profile)
        }
        statusMessage = L10n.tr("Данные удалены")
    }

    @MainActor
    private func exportCSV() {
        do {
            let url = try exportService.exportCSV(sessions: sessions)
            csvExportURL = url
            statusMessage = "CSV подготовлен"
        } catch {
            statusMessage = "Не удалось экспортировать CSV"
        }
    }

    @MainActor
    private func exportJSON() {
        do {
            let url = try exportService.exportJSON(sessions: sessions, profile: profile)
            jsonExportURL = url
            statusMessage = L10n.tr("JSON-резерв подготовлен")
        } catch {
            statusMessage = L10n.tr("Не удалось экспортировать JSON-резерв")
        }
    }

    private func callTrustedContact() {
        let sanitized = trustedContactPhone.filter { $0.isNumber || $0 == "+" }
        guard let url = URL(string: "tel://\(sanitized)") else { return }
        openURL(url)
    }

    @MainActor
    private func connectHealthKit() async {
        guard !connectingHealth else { return }
        connectingHealth = true
        defer { connectingHealth = false }

        guard HealthKitService.shared.isAvailable else {
            statusMessage = L10n.tr("Apple Health недоступен на этом устройстве")
            return
        }
        statusMessage = L10n.tr("Подключаем Apple Health...")

        let granted = await HealthKitService.shared.requestSleepAuthorization()
        guard granted else {
            statusMessage = L10n.tr("Доступ к Apple Health не предоставлен")
            return
        }

        async let syncedDays = HealthKitService.shared.syncRecentStepCounts(days: 14)
        async let syncedHRDays = HealthKitService.shared.syncRecentRestingHeartRates(days: 14)
        async let syncedSnapshots = HealthSnapshotSyncService.shared.syncRecentDays(days: 28, modelContext: context)
        let (stepsDays, hrDays, snapshotDays) = await (syncedDays, syncedHRDays, syncedSnapshots)

        statusMessage = L10n.format(
            "Apple Health подключен (сон, вода, шаги, пульс, HRV). Синхронизировано: шаги %d дн., пульс %d дн., слепки %d дн.",
            stepsDays,
            hrDays,
            snapshotDays
        )
    }
}
