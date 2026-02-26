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
    @Query(sort: [SortDescriptor<PersonalPatternRun>(\.updatedAt, order: .reverse)]) private var personalPatternRuns: [PersonalPatternRun]

    @StateObject private var purchase = PurchaseService.shared

    @State private var weight = 70.0
    @State private var unitSystem: UserProfile.UnitSystem = .metric
    @State private var sex: UserProfile.BiologicalSex = .unspecified
    @State private var hideBACInSharing = true
    @State private var isInitialized = false
    @State private var isApplyingUnitConversion = false
    @State private var showDeleteConfirm = false
    @State private var showPaywall = false
    @State private var showSafetyCenter = false
    @State private var statusMessage = ""
    @State private var connectingHealth = false
    @State private var csvExportURL: URL?
    @State private var jsonExportURL: URL?
    @AppStorage("debugMenuUnlocked") private var debugMenuUnlocked = false
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
    @AppStorage("personalTrendsEnabled") private var personalTrendsEnabled = true
    @AppStorage("personalTrendsCoreMLEnabled") private var personalTrendsCoreMLEnabled = true
    @AppStorage("personalTrendsMinHistory") private var personalTrendsMinHistory = 8
    @AppStorage("personalTrendsMinConfidence") private var personalTrendsMinConfidence = 55
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
        _personalPatternRuns = Query(sort: [SortDescriptor<PersonalPatternRun>(\.updatedAt, order: .reverse)])
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

    private var latestPersonalTrendRun: PersonalPatternRun? {
        personalPatternRuns.first
    }

    private var personalTrendsSummary: String {
        guard !personalPatternRuns.isEmpty else {
            return L10n.tr("Сводка персональных паттернов появится после накопления истории с утренними check-in.")
        }
        let top = personalPatternRuns
            .sorted(by: { $0.confidencePercent > $1.confidencePercent })
            .prefix(3)
        let lines = top.map { run in
            L10n.format(
                "%@ -> %@ (%d%%, %d/%d)",
                run.trigger,
                run.outcome,
                run.confidencePercent,
                run.supportSessions,
                run.sampleSessions
            )
        }
        return lines.joined(separator: " · ")
    }

    @ViewBuilder
    private func settingsSectionHeader(_ title: String) -> some View {
        AppSectionHeader(title: title)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    Text(L10n.tr("Настройте приложение под свои цели и ритм."))
                        .font(.title3.weight(.medium))
                        .foregroundStyle(Color.white.opacity(0.56))
                        .onTapGesture(count: 5) {
                            debugMenuUnlocked = true
                            statusMessage = L10n.tr("Debug меню разблокировано")
                        }

                    Button {
                        showPaywall = true
                    } label: {
                        HStack(spacing: 14) {
                            Circle()
                                .fill(Color.white.opacity(0.7))
                                .frame(width: 56, height: 56)
                                .overlay(
                                    Image(systemName: "sparkles")
                                        .font(.title3)
                                        .foregroundStyle(Color(red: 0.73, green: 0.56, blue: 0.58))
                                )
                            VStack(alignment: .leading, spacing: 4) {
                                Text(purchase.isPremium ? L10n.tr("Premium активен") : L10n.tr("Открыть Premium"))
                                    .font(.system(.title3, design: .rounded).weight(.bold))
                                    .foregroundStyle(Color.black.opacity(0.62))
                                Text(purchase.isPremium ? L10n.tr("Управляйте подпиской и восстановлением покупок.") : L10n.tr("Расширенная аналитика и персональные инсайты."))
                                    .font(.body.weight(.medium))
                                    .foregroundStyle(Color.black.opacity(0.46))
                                    .multilineTextAlignment(.leading)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.headline.weight(.bold))
                                .foregroundStyle(Color.black.opacity(0.44))
                        }
                        .padding(AppDesign.Spacing.md + 2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            LinearGradient(
                                colors: [
                                    Color(red: 0.86, green: 0.82, blue: 0.74),
                                    Color(red: 0.84, green: 0.67, blue: 0.70)
                                ],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .clipShape(RoundedRectangle(cornerRadius: AppDesign.Radius.xxl, style: .continuous))
                    }
                    .buttonStyle(.plain)

                    settingsSectionHeader(L10n.tr("Приватность"))
                    settingsCard {
                        settingsRow(
                            icon: "shield.lefthalf.filled",
                            title: L10n.tr("Скрывать BAC в шаринге"),
                            subtitle: L10n.tr("Скрывает BAC в карточках и экспортах")
                        ) {
                            Toggle("", isOn: $hideBACInSharing)
                                .labelsHidden()
                        }
                    }

                    settingsSectionHeader(L10n.tr("Профиль"))
                    settingsCard {
                        Picker(selection: $unitSystem) {
                            Text(L10n.tr("Метрические")).tag(UserProfile.UnitSystem.metric)
                            Text(L10n.tr("Имперские")).tag(UserProfile.UnitSystem.imperial)
                        } label: {
                            settingsInlineLabel(icon: "scalemass", title: L10n.tr("Единицы"))
                        }
                        .pickerStyle(.menu)
                        settingsDivider()

                        Stepper(value: $weight, in: unitSystem.weightRange, step: 1) {
                            settingsInlineLabel(
                                icon: "figure.stand",
                                title: L10n.tr("Вес"),
                                trailing: String(format: "%.0f %@", weight, unitSystem == .metric ? "кг" : "lbs")
                            )
                        }
                        settingsDivider()

                        Picker(selection: $sex) {
                            ForEach(UserProfile.BiologicalSex.allCases) { value in
                                Text(value.label).tag(value)
                            }
                        } label: {
                            settingsInlineLabel(icon: "person.text.rectangle", title: L10n.tr("Пол (опционально)"))
                        }
                        .pickerStyle(.menu)
                        settingsDivider()

                        Picker(selection: $selectedAppLanguage) {
                            ForEach(AppLanguage.allCases) { language in
                                Text(language.title).tag(language.rawValue)
                            }
                        } label: {
                            settingsInlineLabel(icon: "globe", title: L10n.tr("Язык приложения"))
                        }
                        .pickerStyle(.menu)
                    }

                    settingsSectionHeader(L10n.tr("Цели вечера"))
                    settingsCard {
                        settingsRow(icon: "list.clipboard", title: L10n.tr("Pre-session plan")) {
                            Toggle("", isOn: $preSessionPlanEnabled)
                                .labelsHidden()
                        }
                        settingsDivider()
                        Stepper(value: $goalStdDrinks, in: 1...12, step: 0.5) {
                            settingsInlineLabel(
                                icon: "wineglass",
                                title: L10n.tr("Лимит алкоголя"),
                                trailing: String(format: "%.1f ст.др.", goalStdDrinks)
                            )
                        }
                        settingsDivider()
                        Stepper(value: $goalWaterMl, in: 400...3000, step: 100) {
                            settingsInlineLabel(
                                icon: "drop",
                                title: L10n.tr("Цель воды"),
                                trailing: "\(Int(goalWaterMl)) мл"
                            )
                        }
                        settingsDivider()
                        Stepper(value: $goalEndHour, in: 0...23) {
                            settingsInlineLabel(
                                icon: "clock",
                                title: L10n.tr("План завершить до"),
                                trailing: String(format: "%02d:00", goalEndHour)
                            )
                        }
                        settingsDivider()
                        Stepper(value: $autoFinishSuggestionHours, in: 2...12) {
                            settingsInlineLabel(
                                icon: "hourglass",
                                title: L10n.tr("Авто-подсказка завершить через"),
                                trailing: "\(autoFinishSuggestionHours) ч"
                            )
                        }
                    }

                    settingsSectionHeader(L10n.tr("Недельные цели harm-reduction"))
                    settingsCard {
                        Stepper(value: $weeklyHeavyMorningLimit, in: 0...7) {
                            settingsInlineLabel(
                                icon: "cloud.sun.rain",
                                title: L10n.tr("Лимит тяжелых утр"),
                                trailing: "\(weeklyHeavyMorningLimit)"
                            )
                        }
                        settingsDivider()
                        Stepper(value: $weeklyHighMemoryRiskLimit, in: 0...7) {
                            settingsInlineLabel(
                                icon: "brain.head.profile",
                                title: L10n.tr("Лимит сессий с высоким риском памяти"),
                                trailing: "\(weeklyHighMemoryRiskLimit)"
                            )
                        }
                        settingsDivider()
                        Stepper(value: $weeklyHydrationHitTarget, in: 40...100, step: 5) {
                            settingsInlineLabel(
                                icon: "drop.circle",
                                title: L10n.tr("Цель гидратации в неделю"),
                                trailing: "\(weeklyHydrationHitTarget)%"
                            )
                        }
                        settingsDivider()
                        Text(L10n.tr("Цели используются в разделе Аналитика для недельного контроля безопасности."))
                            .font(.caption)
                            .foregroundStyle(Color.white.opacity(0.52))
                    }

                    settingsSectionHeader(L10n.tr("Безопасность"))
                    settingsCard {
                        settingsRow(
                            icon: "lock.shield",
                            title: L10n.tr("Safety mode"),
                            subtitle: L10n.tr("Ранние подсказки риска и акцент на восстановление")
                        ) {
                            Toggle("", isOn: $safetyModeEnabled)
                                .labelsHidden()
                        }
                        if safetyModeEnabled {
                            Text(L10n.tr("Более ранние подсказки риска, акцент на паузы и воду, приоритет действий безопасности."))
                                .font(.caption)
                                .foregroundStyle(Color.white.opacity(0.52))
                        }
                        settingsDivider()
                        Button {
                            showSafetyCenter = true
                        } label: {
                            settingsRow(
                                icon: "cross.case",
                                title: L10n.tr("Открыть центр безопасности")
                            ) {
                                Image(systemName: "chevron.right")
                                    .foregroundStyle(Color.white.opacity(0.35))
                            }
                        }
                        settingsDivider()
                        TextField(L10n.tr("Имя доверенного контакта"), text: $trustedContactName)
                            .textInputAutocapitalization(.words)
                        settingsDivider()
                        TextField(L10n.tr("Телефон доверенного контакта"), text: $trustedContactPhone)
                            .keyboardType(.phonePad)
                        if !trustedContactPhone.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            settingsDivider()
                            Button {
                                callTrustedContact()
                            } label: {
                                settingsRow(icon: "phone.fill", title: L10n.tr("Проверить звонок контакту")) {
                                    Image(systemName: "chevron.right")
                                        .foregroundStyle(Color.white.opacity(0.35))
                                }
                            }
                        }
                    }

                    settingsSectionHeader(L10n.tr("Интеграции"))
                    settingsCard {
                        NavigationLink {
                            NotificationsSettingsView()
                        } label: {
                            settingsRow(icon: "bell.badge", title: L10n.tr("Настройки уведомлений")) {
                                Image(systemName: "chevron.right")
                                    .foregroundStyle(Color.white.opacity(0.35))
                            }
                        }
                        settingsDivider()
                        settingsRow(icon: "waveform.path.ecg", title: L10n.tr("Live Activity (beta)")) {
                            Toggle("", isOn: $liveActivityEnabled)
                                .labelsHidden()
                        }
                        settingsDivider()
                        settingsRow(icon: "drop.fill", title: L10n.tr("Синхронизировать воду с Apple Health")) {
                            Toggle("", isOn: $syncWaterWithHealth)
                                .labelsHidden()
                        }
                        settingsDivider()
                        Text(L10n.tr("Когда включено, вода импортируется из Apple Health и новые записи из приложения отправляются обратно в Health."))
                            .font(.caption)
                            .foregroundStyle(Color.white.opacity(0.52))
                        Text(waterSyncStatusText)
                            .font(.caption)
                            .foregroundStyle(Color.white.opacity(0.52))
                        settingsDivider()
                        Button {
                            Task { await connectHealthKit() }
                        } label: {
                            settingsRow(
                                icon: "heart.text.square",
                                title: connectingHealth ? L10n.tr("Подключаем Apple Health...") : L10n.tr("Подключить Apple Health (сон / вода / шаги / пульс)")
                            ) {
                                Image(systemName: "arrow.up.right")
                                    .foregroundStyle(Color.white.opacity(0.35))
                            }
                        }
                        .disabled(connectingHealth)
                    }

                    settingsSectionHeader(L10n.tr("CoreML shadow"))
                    settingsCard {
                        settingsRow(icon: "cpu", title: L10n.tr("Включить shadow-прогноз")) {
                            Toggle("", isOn: $shadowRiskModeEnabled)
                                .labelsHidden()
                        }
                        settingsDivider()
                        Text(L10n.tr("Версия модели: coreml-shadow-v1"))
                            .font(.caption)
                            .foregroundStyle(Color.white.opacity(0.52))
                        if let latestShadowRun {
                            Text(L10n.format("Последний успешный инференс: %@", latestShadowRun.updatedAt.formatted(date: .abbreviated, time: .shortened)))
                                .font(.caption)
                                .foregroundStyle(Color.white.opacity(0.52))
                        } else {
                            Text(L10n.tr("Последний успешный инференс: пока нет данных"))
                                .font(.caption)
                                .foregroundStyle(Color.white.opacity(0.52))
                        }
                        settingsDivider()
                        Stepper(value: $shadowRolloutMinHistory, in: 3...20) {
                            settingsInlineLabel(
                                icon: "clock.arrow.circlepath",
                                title: L10n.tr("Мин. завершенных сессий"),
                                trailing: "\(shadowRolloutMinHistory)"
                            )
                        }
                        settingsDivider()
                        Stepper(value: $shadowRolloutMinConfidence, in: 30...95, step: 5) {
                            settingsInlineLabel(
                                icon: "checkmark.seal",
                                title: L10n.tr("Мин. уверенность для UI"),
                                trailing: "\(shadowRolloutMinConfidence)%"
                            )
                        }
                        settingsDivider()
                        Text(L10n.tr("Shadow отображается только при достаточной истории и confidence-пороге; основной риск это не меняет."))
                            .font(.caption)
                            .foregroundStyle(Color.white.opacity(0.52))
                        Text(shadowQualitySummary)
                            .font(.caption)
                            .foregroundStyle(Color.white.opacity(0.52))
                    }

                    settingsSectionHeader(L10n.tr("Персональные паттерны"))
                    settingsCard {
                        settingsRow(icon: "waveform.path", title: L10n.tr("Включить персональные паттерны")) {
                            Toggle("", isOn: $personalTrendsEnabled)
                                .labelsHidden()
                        }
                        settingsDivider()
                        settingsRow(icon: "brain", title: L10n.tr("Использовать CoreML для паттернов")) {
                            Toggle("", isOn: $personalTrendsCoreMLEnabled)
                                .labelsHidden()
                        }
                        settingsDivider()
                        if let latestPersonalTrendRun {
                            Text(L10n.format("Последнее обновление паттернов: %@", latestPersonalTrendRun.updatedAt.formatted(date: .abbreviated, time: .shortened)))
                                .font(.caption)
                                .foregroundStyle(Color.white.opacity(0.52))
                        } else {
                            Text(L10n.tr("Последнее обновление паттернов: пока нет данных"))
                                .font(.caption)
                                .foregroundStyle(Color.white.opacity(0.52))
                        }
                        settingsDivider()
                        Stepper(value: $personalTrendsMinHistory, in: 5...30) {
                            settingsInlineLabel(
                                icon: "calendar.badge.clock",
                                title: L10n.tr("Мин. завершенных сессий для паттернов"),
                                trailing: "\(personalTrendsMinHistory)"
                            )
                        }
                        settingsDivider()
                        Stepper(value: $personalTrendsMinConfidence, in: 30...95, step: 5) {
                            settingsInlineLabel(
                                icon: "percent",
                                title: L10n.tr("Мин. уверенность паттерна"),
                                trailing: "\(personalTrendsMinConfidence)%"
                            )
                        }
                        settingsDivider()
                        Text(personalTrendsSummary)
                            .font(.caption)
                            .foregroundStyle(Color.white.opacity(0.52))
                        Text(L10n.tr("Паттерны показывают только наблюдаемые связи в ваших данных и не являются медицинским заключением."))
                            .font(.caption)
                            .foregroundStyle(Color.white.opacity(0.52))
                    }

                    if debugMenuUnlocked {
                        settingsSectionHeader(L10n.tr("Debug меню"))
                        settingsCard {
                            Toggle(
                                L10n.tr("Принудительно включить Premium"),
                                isOn: Binding(
                                    get: { purchase.debugPremiumOverrideEnabled },
                                    set: { purchase.setDebugPremiumOverride($0) }
                                )
                            )
                            settingsDivider()
                            Text(L10n.tr("Используйте только для локальной отладки. Оформление подписки не выполняется."))
                                .font(.caption)
                                .foregroundStyle(Color.white.opacity(0.52))
                        }
                    }

                    settingsSectionHeader(L10n.tr("Подписка"))
                    settingsCard {
                        settingsRow(
                            icon: "crown.fill",
                            title: purchase.isPremium ? L10n.tr("Статус: Premium активен") : L10n.tr("Статус: базовый")
                        )
                        settingsDivider()
                        Button {
                            showPaywall = true
                        } label: {
                            settingsRow(icon: "sparkles", title: purchase.isPremium ? L10n.tr("Управлять подпиской") : L10n.tr("Оформить Premium")) {
                                Image(systemName: "chevron.right")
                                    .foregroundStyle(Color.white.opacity(0.35))
                            }
                        }
                        settingsDivider()
                        Button {
                            Task { await purchase.restoreFromAppStore() }
                        } label: {
                            settingsRow(icon: "arrow.clockwise", title: L10n.tr("Restore purchases")) {
                                Image(systemName: "arrow.clockwise")
                                    .foregroundStyle(Color.white.opacity(0.35))
                            }
                        }
                    }

                    settingsSectionHeader(L10n.tr("Управление данными"))
                    settingsCard(strokeColor: Color(red: 0.72, green: 0.56, blue: 0.60).opacity(0.72)) {
                        Button(role: .destructive) {
                            showDeleteConfirm = true
                        } label: {
                            settingsRow(icon: "trash.fill", title: L10n.tr("Удалить все данные")) {
                                Text(L10n.tr("Очистить"))
                                    .foregroundStyle(Color.red.opacity(0.86))
                            }
                        }
                        settingsDivider()
                        Button {
                            exportCSV()
                        } label: {
                            settingsRow(icon: "square.and.arrow.up", title: L10n.tr("Экспорт CSV"))
                        }
                        if let csvExportURL {
                            ShareLink(item: csvExportURL) {
                                settingsRow(icon: "paperplane", title: L10n.tr("Поделиться CSV"))
                            }
                        }
                        settingsDivider()
                        Button {
                            exportJSON()
                        } label: {
                            settingsRow(icon: "externaldrive", title: L10n.tr("Экспорт JSON-резерва"))
                        }
                        if let jsonExportURL {
                            ShareLink(item: jsonExportURL) {
                                settingsRow(icon: "paperplane", title: L10n.tr("Поделиться JSON-резервом"))
                            }
                        }
                    }

                    if !statusMessage.isEmpty {
                        settingsCard {
                            Text(statusMessage)
                                .font(.footnote)
                                .foregroundStyle(Color.white.opacity(0.62))
                        }
                    }
                }
                .padding(.horizontal, AppDesign.Spacing.lg - 4)
                .padding(.top, AppDesign.Spacing.md + 2)
                .padding(.bottom, AppDesign.Spacing.xl + 2)
            }
            .appDarkScreenBackground()
            .tint(AppDesign.Colors.primary)
            .navigationTitle(L10n.tr("Настройки"))
            .navigationBarTitleDisplayMode(.large)
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .task {
                await loadInitialStateIfNeeded()
                await purchase.restore()
            }
            .onChange(of: weight) { _, _ in
                if isApplyingUnitConversion {
                    isApplyingUnitConversion = false
                    return
                }
                saveProfileAndRecompute()
            }
            .onChange(of: unitSystem) { oldValue, newValue in
                guard isInitialized, oldValue != newValue else { return }
                isApplyingUnitConversion = true
                let converted = oldValue.convertWeight(weight, to: newValue)
                weight = newValue.normalizeWeight(converted).rounded()
                saveProfileAndRecompute()
            }
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

    private func settingsDivider() -> some View {
        Divider()
            .overlay(Color.white.opacity(0.08))
            .padding(.vertical, 2)
    }

    private func settingsInlineLabel(icon: String, title: String, trailing: String? = nil) -> some View {
        HStack(spacing: 10) {
            AppIconBadge(
                icon: icon,
                size: 28,
                iconFont: AppDesign.Typography.iconBadge
            )
            Text(title)
                .foregroundStyle(Color.white.opacity(0.88))
            Spacer()
            if let trailing {
                Text(trailing)
                    .foregroundStyle(Color.white.opacity(0.6))
            }
        }
    }

    private func settingsRow<Trailing: View>(
        icon: String,
        title: String,
        subtitle: String? = nil,
        @ViewBuilder trailing: () -> Trailing
    ) -> some View {
        HStack(spacing: 12) {
            AppIconBadge(
                icon: icon,
                size: 40,
                iconFont: AppDesign.Typography.rowIcon
            )
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(AppDesign.Typography.rowTitle)
                    .foregroundStyle(Color.white.opacity(0.88))
                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(Color.white.opacity(0.52))
                }
            }
            Spacer()
            trailing()
        }
    }

    private func settingsRow(icon: String, title: String, subtitle: String? = nil) -> some View {
        settingsRow(icon: icon, title: title, subtitle: subtitle) {
            EmptyView()
        }
    }

    private func settingsCard<Content: View>(
        strokeColor: Color = Color.white.opacity(0.08),
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            content()
        }
        .appElevatedCard(stroke: strokeColor)
    }

    @MainActor
    private func loadInitialStateIfNeeded() async {
        guard !isInitialized else { return }
        defer { isInitialized = true }

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
        for run in riskModelRuns {
            context.delete(run)
        }
        for run in personalPatternRuns {
            context.delete(run)
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
