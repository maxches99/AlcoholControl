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

    private let service = SessionService()
    private let exportService = DataExportService()

    init() {
        _profiles = Query()
        _sessions = Query()
        _drinks = Query()
        _waters = Query()
        _meals = Query()
        _checkIns = Query()
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

    var body: some View {
        NavigationStack {
            Form {
                Section("Профиль") {
                    Picker("Единицы", selection: $unitSystem) {
                        Text("Метрические").tag(UserProfile.UnitSystem.metric)
                        Text("Имперские").tag(UserProfile.UnitSystem.imperial)
                    }

                    Stepper(value: $weight, in: 30...200, step: 1) {
                        HStack {
                            Text("Вес")
                            Spacer()
                            Text(String(format: "%.0f %@", weight, unitSystem == .metric ? "кг" : "lbs"))
                        }
                    }

                    Picker("Пол (опционально)", selection: $sex) {
                        ForEach(UserProfile.BiologicalSex.allCases) { value in
                            Text(value.label).tag(value)
                        }
                    }
                }

                Section("Язык") {
                    Picker("Язык приложения", selection: $selectedAppLanguage) {
                        ForEach(AppLanguage.allCases) { language in
                            Text(language.title).tag(language.rawValue)
                        }
                    }
                }

                Section("Уведомления") {
                    NavigationLink("Настройки уведомлений") {
                        NotificationsSettingsView()
                    }
                }

                Section("Цели вечера") {
                    Toggle("Pre-session plan", isOn: $preSessionPlanEnabled)

                    Stepper(value: $goalStdDrinks, in: 1...12, step: 0.5) {
                        HStack {
                            Text("Лимит алкоголя")
                            Spacer()
                            Text(String(format: "%.1f ст.др.", goalStdDrinks))
                                .foregroundStyle(.secondary)
                        }
                    }

                    Stepper(value: $goalWaterMl, in: 400...3000, step: 100) {
                        HStack {
                            Text("Цель воды")
                            Spacer()
                            Text("\(Int(goalWaterMl)) мл")
                                .foregroundStyle(.secondary)
                        }
                    }

                    Stepper(value: $goalEndHour, in: 0...23) {
                        HStack {
                            Text("План завершить до")
                            Spacer()
                            Text(String(format: "%02d:00", goalEndHour))
                                .foregroundStyle(.secondary)
                        }
                    }

                    Stepper(value: $autoFinishSuggestionHours, in: 2...12) {
                        HStack {
                            Text("Авто-подсказка завершить через")
                            Spacer()
                            Text("\(autoFinishSuggestionHours) ч")
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Section("Weekly harm-reduction goals") {
                    Stepper(value: $weeklyHeavyMorningLimit, in: 0...7) {
                        HStack {
                            Text("Лимит тяжелых утр")
                            Spacer()
                            Text("\(weeklyHeavyMorningLimit)")
                                .foregroundStyle(.secondary)
                        }
                    }
                    Stepper(value: $weeklyHighMemoryRiskLimit, in: 0...7) {
                        HStack {
                            Text("Лимит high memory-risk сессий")
                            Spacer()
                            Text("\(weeklyHighMemoryRiskLimit)")
                                .foregroundStyle(.secondary)
                        }
                    }
                    Stepper(value: $weeklyHydrationHitTarget, in: 40...100, step: 5) {
                        HStack {
                            Text("Цель гидратации в неделю")
                            Spacer()
                            Text("\(weeklyHydrationHitTarget)%")
                                .foregroundStyle(.secondary)
                        }
                    }
                    Text("Цели используются в разделе Аналитика для weekly safety контроля.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Безопасность") {
                    Toggle("Safety mode", isOn: $safetyModeEnabled)
                    if safetyModeEnabled {
                        Text("Более ранние risk-подсказки, акцент на паузы и воду, приоритет safety действий.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Button("Открыть Safety Center") {
                        showSafetyCenter = true
                    }

                    TextField("Имя доверенного контакта", text: $trustedContactName)
                        .textInputAutocapitalization(.words)

                    TextField("Телефон доверенного контакта", text: $trustedContactPhone)
                        .keyboardType(.phonePad)

                    if !trustedContactPhone.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Button("Проверить звонок контакту") {
                            callTrustedContact()
                        }
                    }
                }

                Section("Интеграции") {
                    Toggle("Live Activity (beta)", isOn: $liveActivityEnabled)
                    Toggle(isOn: $syncWaterWithHealth) {
                        Text(L10n.tr("Синхронизировать воду с Apple Health"))
                    }
                    Text(L10n.tr("Когда включено, вода импортируется из Apple Health и новые записи из приложения отправляются обратно в Health."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(waterSyncStatusText)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Button(connectingHealth ? "Подключаем Apple Health..." : "Подключить Apple Health (сон / вода / шаги / пульс)") {
                        Task { await connectHealthKit() }
                    }
                    .disabled(connectingHealth)
                }

                Section("Приватность") {
                    Toggle("Скрывать BAC в шаринге", isOn: $hideBACInSharing)
                }

                Section("Подписка") {
                    Text(purchase.isPremium ? "Статус: Premium активен" : "Статус: базовый")
                        .foregroundStyle(.secondary)
                    Button(purchase.isPremium ? "Управлять подпиской" : "Оформить Premium") {
                        showPaywall = true
                    }
                    Button("Restore purchases") {
                        Task { await purchase.restoreFromAppStore() }
                    }
                }

                Section("Управление данными") {
                    Button("Экспорт CSV") {
                        exportCSV()
                    }
                    if let csvExportURL {
                        ShareLink("Поделиться CSV", item: csvExportURL)
                    }

                    Button("Экспорт JSON backup") {
                        exportJSON()
                    }
                    if let jsonExportURL {
                        ShareLink("Поделиться JSON backup", item: jsonExportURL)
                    }

                    Button(role: .destructive) {
                        showDeleteConfirm = true
                    } label: {
                        Text("Удалить все данные")
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
            .navigationTitle("Настройки")
            .task {
                await loadInitialStateIfNeeded()
                await purchase.restore()
            }
            .onChange(of: weight) { _, _ in saveProfileAndRecompute() }
            .onChange(of: unitSystem) { _, _ in saveProfileAndRecompute() }
            .onChange(of: sex) { _, _ in saveProfileAndRecompute() }
            .onChange(of: hideBACInSharing) { _, _ in saveProfileAndRecompute() }
            .alert("Удалить все данные?", isPresented: $showDeleteConfirm) {
                Button("Удалить", role: .destructive) {
                    deleteAllData()
                }
                Button("Отмена", role: .cancel) {}
            } message: {
                Text("Удалятся все сессии, записи и чек-ины. Подписка сохранится отдельно.")
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
            statusMessage = "JSON backup подготовлен"
        } catch {
            statusMessage = "Не удалось экспортировать JSON backup"
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
