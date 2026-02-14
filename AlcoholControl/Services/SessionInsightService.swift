import Foundation

enum InsightLevel: String {
    case low
    case medium
    case high

    var title: String {
        switch self {
        case .low: return L10n.tr("низкий")
        case .medium: return L10n.tr("средний")
        case .high: return L10n.tr("высокий")
        }
    }
}

enum TrendDirection {
    case improving
    case worsening
    case stable

    var title: String {
        switch self {
        case .improving: return L10n.tr("улучшается")
        case .worsening: return L10n.tr("ухудшается")
        case .stable: return L10n.tr("стабильно")
        }
    }
}

enum WaterBalanceStatus {
    case balanced
    case mildDeficit
    case highDeficit

    var title: String {
        switch self {
        case .balanced: return L10n.tr("норма")
        case .mildDeficit: return L10n.tr("дефицит")
        case .highDeficit: return L10n.tr("высокий дефицит")
        }
    }
}

struct WaterBalanceSnapshot {
    let consumedMl: Int
    let targetMl: Int
    let deficitMl: Int
    let status: WaterBalanceStatus
    let unknownMarksCount: Int
    let suggestedTopUpMl: Int

    var progress: Double {
        guard targetMl > 0 else { return 1 }
        return min(1, Double(consumedMl) / Double(targetMl))
    }
}

struct EveningInsightAssessment {
    let morningRisk: InsightLevel
    let memoryRisk: InsightLevel
    let morningProbabilityPercent: Int
    let memoryProbabilityPercent: Int
    let confidence: InsightConfidence
    let morningReasons: [String]
    let memoryReasons: [String]
    let riskEvents: [RiskEvent]
    let mealImpact: String
    let waterBalance: WaterBalanceSnapshot
    let actionsNow: [String]
}

struct SessionHealthContext {
    let sleepHours: Double?
    let stepCount: Int?
    let restingHeartRate: Int?
    let hrvSdnn: Double?
    let sleepEfficiency: Double?
}

struct RecoveryIndexSnapshot {
    let score: Int
    let level: InsightLevel
    let headline: String
    let reasons: [String]
}

struct InsightConfidence {
    let level: InsightLevel
    let scorePercent: Int
    let reasons: [String]
}

struct RiskEvent: Identifiable {
    let id: String
    let date: Date
    let severity: InsightLevel
    let title: String
    let detail: String
}

struct WeeklyInsightSnapshot {
    let sessionsCount: Int
    let heavyMorningCount: Int
    let highMemoryRiskCount: Int
    let hydrationHitRatePercent: Int
    let mealCoveragePercent: Int
    let averagePeakBAC: Double
    let averageWellbeingScore: Double?
    let headline: String
}

struct TriggerPatternHit: Identifiable {
    let id: String
    let title: String
    let value: String
    let impact: String
}

struct TriggerPatternsSummary {
    let weekdayHotspot: String?
    let startHourHotspot: String?
    let drinkCategoryHotspot: String?
    let hits: [TriggerPatternHit]
}

struct PersonalizedPatternAssessment {
    let peakRiskThreshold: Double
    let memoryRiskThreshold: Double
    let paceRiskThreshold: Double
    let hydrationGoalProgress: Double
    let peakTrend: TrendDirection
    let hydrationTrend: TrendDirection
    let wellbeingTrend: TrendDirection?
    let waterStreak: Int
    let mealStreak: Int
    let notes: [String]
    let actions: [String]
}

struct EveningScenario: Identifiable {
    let id: String
    let title: String
    let subtitle: String
    let impactText: String
    let recommendation: String
}

struct MemoryProjection: Identifiable {
    let id: String
    let horizonMinutes: Int
    let memoryProbabilityPercent: Int
    let comment: String
}

private struct PersonalLearningSnapshot {
    let scoreDelta: Int
    let probabilityBias: Int
}

private struct LearningFeatures {
    let highPeak: Bool
    let fastPace: Bool
    let lowHydration: Bool
    let longSession: Bool
    let noWater: Bool
    let noMeal: Bool
}

struct SessionInsightService {
    private let calculator = BACCalculator()

    func assess(
        session: Session,
        profile: UserProfile? = nil,
        at date: Date = .now,
        health: SessionHealthContext? = nil,
        history: [Session]? = nil,
        useObservedCheckIn: Bool = true
    ) -> EveningInsightAssessment {
        let durationHours = max(0, (session.endAt ?? date).timeIntervalSince(session.startAt) / 3600)
        let standardDrinksTotal = session.drinks.reduce(0.0) { partial, drink in
            partial + standardDrinks(from: drink)
        }
        let drinksPerHour = durationHours > 0.5 ? (standardDrinksTotal / durationHours) : standardDrinksTotal
        let waterCount = session.waters.count
        let mealMitigation = mealMitigationScore(session: session, at: date)

        let peakBAC: Double
        let currentBAC: Double?
        let estimatedSoberAt: Date?

        if let profile {
            let timeline = calculator.compute(for: session, profile: profile, at: date)
            peakBAC = max(timeline.peakBAC, session.cachedPeakBAC)
            currentBAC = timeline.currentBAC
            estimatedSoberAt = timeline.estimatedSoberAt
        } else {
            peakBAC = session.cachedPeakBAC
            currentBAC = nil
            estimatedSoberAt = session.cachedEstimatedSoberAt
        }

        let waterBalance = makeWaterBalance(
            session: session,
            profile: profile,
            durationHours: durationHours,
            standardDrinksTotal: standardDrinksTotal
        )
        let confidence = makeConfidence(
            session: session,
            profile: profile,
            waterBalance: waterBalance,
            durationHours: durationHours
        )

        var morningScore = 0
        var morningReasons: [String] = []

        if peakBAC >= 0.10 {
            morningScore += 2
            morningReasons.append(L10n.tr("peak BAC выше 0.10 часто связан с тяжелым утром"))
        }
        if peakBAC >= 0.16 {
            morningScore += 2
            morningReasons.append(L10n.tr("peak BAC выше 0.16 повышает риск выраженного недомогания"))
        }
        if let currentBAC, currentBAC >= 0.08 {
            morningScore += 1
            morningReasons.append(L10n.tr("текущий BAC все еще высокий"))
        }
        if durationHours >= 4 {
            morningScore += 1
            morningReasons.append(L10n.tr("длительная сессия может ухудшить самочувствие утром"))
        }
        if waterCount == 0 {
            morningScore += 1
            morningReasons.append(L10n.tr("в сессии пока не отмечена вода"))
        }
        if waterBalance.status == .highDeficit {
            morningScore += 1
            morningReasons.append(L10n.tr("водный баланс в выраженном дефиците"))
        }
        if drinksPerHour >= 1.5 {
            morningScore += 1
            morningReasons.append(L10n.tr("высокий темп употребления повышает нагрузку"))
        }
        if let estimatedSoberAt, estimatedSoberAt.timeIntervalSince(date) > 6 * 3600 {
            morningScore += 1
            morningReasons.append(L10n.tr("до 0.00 осталось более 6 часов"))
        }

        if let sleepHours = health?.sleepHours {
            if sleepHours < 5 {
                morningScore += 2
                morningReasons.append(L10n.tr("сон ниже 5ч заметно повышает утренний риск"))
            } else if sleepHours < 6 {
                morningScore += 1
                morningReasons.append(L10n.tr("сон ниже 6ч повышает риск тяжелого утра"))
            } else if sleepHours >= 7.5 {
                morningScore = max(0, morningScore - 1)
                morningReasons.append(L10n.tr("хороший сон частично снижает риск тяжелого утра"))
            }
        }
        if let stepCount = health?.stepCount {
            if stepCount >= 12_000 {
                morningScore += 1
                morningReasons.append(L10n.tr("высокая активность сегодня может усилить усталость и дефицит воды"))
            } else if (5_000...9_000).contains(stepCount) {
                morningScore = max(0, morningScore - 1)
                morningReasons.append(L10n.tr("умеренная активность обычно помогает восстановлению"))
            }
        }
        if let restingHeartRate = health?.restingHeartRate {
            if restingHeartRate >= 80 {
                morningScore += 2
                morningReasons.append(L10n.tr("пульс в покое заметно выше обычного, восстановление может быть тяжелее"))
            } else if restingHeartRate >= 75 {
                morningScore += 1
                morningReasons.append(L10n.tr("пульс в покое выше обычного"))
            }
        }
        morningScore = max(0, morningScore - mealMitigation.scoreReduction)
        if let text = mealMitigation.reason {
            morningReasons.append(text)
        }
        let personalLearning = useObservedCheckIn
            ? personalLearningSnapshot(
                current: session,
                history: history ?? [],
                profile: profile,
                at: date
            )
            : nil
        if useObservedCheckIn,
           session.morningCheckIn == nil,
           let learning = personalLearning,
           learning.scoreDelta != 0 {
            morningScore = max(0, morningScore + learning.scoreDelta)
            morningReasons.append(L10n.tr("Индивидуальный ориентир риска, рассчитанный по вашим предыдущим сессиям."))
        }

        var memoryScore = 0
        var memoryReasons: [String] = []

        if peakBAC >= 0.14 {
            memoryScore += 1
            memoryReasons.append(L10n.tr("при таком peak BAC риск провалов памяти растет"))
        }
        if peakBAC >= 0.18 {
            memoryScore += 2
            memoryReasons.append(L10n.tr("peak BAC выше 0.18 связан с заметным риском амнезии эпизодов"))
        }
        if peakBAC >= 0.24 {
            memoryScore += 2
            memoryReasons.append(L10n.tr("очень высокий peak BAC сильно повышает риск провалов"))
        }
        if let currentBAC, currentBAC >= 0.12 {
            memoryScore += 1
            memoryReasons.append(L10n.tr("текущий BAC остается высоким"))
        }
        if standardDrinksTotal >= 5 {
            memoryScore += 1
            memoryReasons.append(L10n.tr("большой суммарный объем алкоголя"))
        }
        if standardDrinksTotal >= 8 {
            memoryScore += 1
            memoryReasons.append(L10n.tr("очень большой суммарный объем алкоголя"))
        }
        if drinksPerHour >= 2 {
            memoryScore += 1
            memoryReasons.append(L10n.tr("быстрый темп повышает риск провалов памяти"))
        }
        if strongestABV(in: session) >= 35 {
            memoryScore += 1
            memoryReasons.append(L10n.tr("преобладание крепких напитков"))
        }
        if let sleepHours = health?.sleepHours, sleepHours < 5 {
            memoryScore += 1
            memoryReasons.append(L10n.tr("дефицит сна повышает риск фрагментов памяти"))
        }
        if let restingHeartRate = health?.restingHeartRate, restingHeartRate >= 80 {
            memoryScore += 1
            memoryReasons.append(L10n.tr("повышенный пульс в покое указывает на высокую нагрузку"))
        }
        memoryScore = max(0, memoryScore - mealMitigation.scoreReduction)
        if mealMitigation.scoreReduction == 0 {
            memoryReasons.append(L10n.tr("прием пищи не отмечен или был давно"))
        }

        if morningReasons.isEmpty {
            morningReasons = [L10n.tr("по текущим данным риск тяжелого утра пока умеренный")]
        }
        if memoryReasons.isEmpty {
            memoryReasons = [L10n.tr("по текущим данным риск провалов памяти невысокий")]
        }

        let modelMorningRisk = level(forMorningScore: morningScore)
        var morningRisk = modelMorningRisk
        var morningProbabilityPercent = riskPercent(score: morningScore, maxScore: 11)
        var resolvedMorningReasons = morningReasons
        if useObservedCheckIn,
           session.morningCheckIn == nil,
           let learning = personalLearning,
           learning.probabilityBias != 0 {
            let adjusted = morningProbabilityPercent + learning.probabilityBias
            morningProbabilityPercent = Int(clamp(Double(adjusted), min: 1, max: 99).rounded())
            morningRisk = level(forCalibratedMorningProbability: morningProbabilityPercent)
            if !resolvedMorningReasons.contains(L10n.tr("Индивидуальный ориентир риска, рассчитанный по вашим предыдущим сессиям.")) {
                resolvedMorningReasons.append(L10n.tr("Индивидуальный ориентир риска, рассчитанный по вашим предыдущим сессиям."))
            }
        }
        if useObservedCheckIn, let checkIn = session.morningCheckIn {
            let clampedScore = max(0, min(5, checkIn.wellbeingScore))
            morningRisk = observedMorningRisk(for: clampedScore)
            morningProbabilityPercent = observedMorningProbability(for: clampedScore)
            resolvedMorningReasons.insert(L10n.format("Самочувствие: %d/5", clampedScore), at: 0)
        }

        let memoryRisk = level(forMemoryScore: memoryScore)
        let riskEvents = makeRiskEvents(
            session: session,
            waterBalance: waterBalance,
            drinksPerHour: drinksPerHour,
            morningRisk: morningRisk,
            memoryRisk: memoryRisk
        )

        return EveningInsightAssessment(
            morningRisk: morningRisk,
            memoryRisk: memoryRisk,
            morningProbabilityPercent: morningProbabilityPercent,
            memoryProbabilityPercent: riskPercent(score: memoryScore, maxScore: 10),
            confidence: confidence,
            morningReasons: resolvedMorningReasons,
            memoryReasons: memoryReasons,
            riskEvents: riskEvents,
            mealImpact: mealMitigation.summary,
            waterBalance: waterBalance,
            actionsNow: makeActionsNow(
                morningRisk: morningRisk,
                memoryRisk: memoryRisk,
                waterBalance: waterBalance,
                currentBAC: currentBAC,
                drinksPerHour: drinksPerHour,
                mealMitigation: mealMitigation
            )
        )
    }

    func recoveryIndex(
        session: Session,
        assessment: EveningInsightAssessment,
        health: SessionHealthContext? = nil,
        baselines: HealthBaselineSet? = nil
    ) -> RecoveryIndexSnapshot {
        var score = 100
        var reasons: [String] = []

        score -= Int((Double(assessment.morningProbabilityPercent) * 0.45).rounded())
        score -= Int((Double(assessment.memoryProbabilityPercent) * 0.30).rounded())

        if assessment.waterBalance.deficitMl > 0 {
            let waterPenalty = min(18, Int((Double(assessment.waterBalance.deficitMl) / 80).rounded()))
            score -= waterPenalty
            reasons.append(L10n.format("дефицит воды ~%d мл снижает индекс восстановления", assessment.waterBalance.deficitMl))
        } else {
            score += 4
            reasons.append(L10n.tr("водный баланс в норме поддерживает восстановление"))
        }

        if session.meals.isEmpty {
            score -= 6
            reasons.append(L10n.tr("отсутствие приема пищи снижает скорость восстановления"))
        } else {
            score += 2
            reasons.append(L10n.tr("прием пищи улучшает потенциал восстановления"))
        }

        if let sleepHours = health?.sleepHours {
            if let baseline = baselines?.sleep {
                if sleepHours * 60 < baseline.p25 {
                    score -= 12
                    reasons.append(L10n.tr("сон ниже личного диапазона снижает восстановление"))
                } else if sleepHours * 60 < baseline.median {
                    score -= 6
                    reasons.append(L10n.tr("сон немного ниже обычного"))
                } else if sleepHours * 60 >= baseline.median {
                    score += 4
                    reasons.append(L10n.tr("сон на уровне или выше личной нормы"))
                }
            } else {
                if sleepHours < 5 {
                    score -= 14
                    reasons.append(L10n.tr("сон < 5ч сильно ухудшает восстановление"))
                } else if sleepHours < 6 {
                    score -= 8
                    reasons.append(L10n.tr("сон < 6ч ухудшает восстановление"))
                } else if sleepHours >= 7 {
                    score += 4
                    reasons.append(L10n.tr("сон >= 7ч улучшает восстановление"))
                }
            }
        }

        if let stepCount = health?.stepCount {
            if let baseline = baselines?.steps {
                if Double(stepCount) > baseline.p75 {
                    score -= 6
                    reasons.append(L10n.tr("активность выше обычной повышает нагрузку на восстановление"))
                } else if Double(stepCount) >= baseline.p25 && Double(stepCount) <= baseline.p75 {
                    score += 3
                    reasons.append(L10n.tr("движение в вашем привычном диапазоне поддерживает восстановление"))
                } else if Double(stepCount) < baseline.p25 {
                    score -= 2
                    reasons.append(L10n.tr("очень низкая активность снижает циркуляцию и восстановление"))
                }
            } else {
                if stepCount >= 12_000 {
                    score -= 7
                    reasons.append(L10n.tr("высокая активность + алкоголь повышают нагрузку на восстановление"))
                } else if (5_000...9_000).contains(stepCount) {
                    score += 3
                    reasons.append(L10n.tr("умеренная активность поддерживает восстановление"))
                }
            }
        }

        if let restingHeartRate = health?.restingHeartRate {
            if let baseline = baselines?.restingHeartRate {
                if Double(restingHeartRate) > baseline.p75 {
                    score -= 9
                    reasons.append(L10n.tr("пульс выше вашего привычного уровня — возможный стресс восстановления"))
                } else if Double(restingHeartRate) > baseline.median {
                    score -= 4
                    reasons.append(L10n.tr("пульс немного выше нормы"))
                } else if Double(restingHeartRate) < baseline.p25 {
                    score += 3
                    reasons.append(L10n.tr("пульс ниже обычного — восстановление идет легче"))
                }
            } else {
                if restingHeartRate >= 80 {
                    score -= 9
                    reasons.append(L10n.tr("пульс в покое >= 80 может означать высокий стресс восстановления"))
                } else if restingHeartRate >= 75 {
                    score -= 5
                    reasons.append(L10n.tr("пульс в покое выше нормы немного снижает индекс"))
                } else if restingHeartRate <= 62 {
                    score += 2
                    reasons.append(L10n.tr("низкий пульс в покое обычно связан с более мягким восстановлением"))
                }
            }
        }

        if let hrv = health?.hrvSdnn, let baseline = baselines?.hrv {
            if hrv < baseline.p25 {
                score -= 8
                reasons.append(L10n.tr("HRV ниже обычного — восстановление замедлено"))
            } else if hrv > baseline.p75 {
                score += 5
                reasons.append(L10n.tr("HRV выше нормы поддерживает восстановление"))
            }
        }

        let clampedScore = Int(clamp(Double(score), min: 0, max: 100).rounded())
        let level: InsightLevel
        let headline: String
        switch clampedScore {
        case 75...:
            level = .low
            headline = L10n.tr("потенциал восстановления высокий")
        case 50...74:
            level = .medium
            headline = L10n.tr("потенциал восстановления средний")
        default:
            level = .high
            headline = L10n.tr("нужен щадящий режим восстановления")
        }

        return RecoveryIndexSnapshot(
            score: clampedScore,
            level: level,
            headline: headline,
            reasons: Array(reasons.prefix(3))
        )
    }

    func personalizedPatterns(
        current session: Session,
        history: [Session],
        profile: UserProfile? = nil
    ) -> PersonalizedPatternAssessment {
        let recent = history
            .filter { !$0.isActive && $0.id != session.id }
            .sorted(by: { $0.startAt > $1.startAt })
        let window = Array(recent.prefix(10))

        let peakValues = window.map(\.cachedPeakBAC).filter { $0 > 0 }
        let peakAverage = peakValues.isEmpty ? 0.12 : peakValues.reduce(0, +) / Double(peakValues.count)

        let paceValues = window.compactMap { averagePace(for: $0) }
        let paceAverage = paceValues.isEmpty ? 1.4 : paceValues.reduce(0, +) / Double(paceValues.count)

        let hydrationValues = window.map { hydrationProgress(for: $0, profile: profile) }
        let hydrationAverage = hydrationValues.isEmpty ? 0.75 : hydrationValues.reduce(0, +) / Double(hydrationValues.count)

        let wellbeingValues = window.compactMap { $0.morningCheckIn?.wellbeingScore }
        let wellbeingAverage: Double? = wellbeingValues.isEmpty ? nil : Double(wellbeingValues.reduce(0, +)) / Double(wellbeingValues.count)

        let goodSessions = window.filter { ($0.morningCheckIn?.wellbeingScore ?? 0) >= 4 }
        let goodHydrationValues = goodSessions.map { hydrationProgress(for: $0, profile: profile) }
        let hydrationGoalProgress = clamp(
            goodHydrationValues.isEmpty
                ? max(0.75, hydrationAverage)
                : (goodHydrationValues.reduce(0, +) / Double(goodHydrationValues.count)),
            min: 0.65,
            max: 1.0
        )

        let peakRiskThreshold = clamp(peakAverage * 0.95, min: 0.10, max: 0.16)
        let memoryRiskThreshold = clamp(peakAverage * 1.20, min: 0.14, max: 0.22)
        let paceRiskThreshold = clamp(paceAverage * 1.15, min: 1.2, max: 2.2)

        let peakTrend = trendDirection(values: peakValues, lowerIsBetter: true)
        let hydrationTrend = trendDirection(values: hydrationValues, lowerIsBetter: false)
        let wellbeingTrend = wellbeingValues.isEmpty ? nil : trendDirection(values: wellbeingValues.map(Double.init), lowerIsBetter: false)

        let timeline = [session] + window
        let waterStreak = streakCount(in: timeline) { hydrationProgress(for: $0, profile: profile) >= hydrationGoalProgress }
        let mealStreak = streakCount(in: timeline) { !$0.meals.isEmpty }

        let currentPace = averagePace(for: session) ?? paceRiskThreshold
        let currentHydration = hydrationProgress(for: session, profile: profile)

        var notes: [String] = []
        if session.cachedPeakBAC >= peakRiskThreshold {
            notes.append(L10n.format("Ваш персональный порог по peak BAC (~%.3f) уже достигнут.", peakRiskThreshold))
        }
        if currentPace >= paceRiskThreshold {
            notes.append(L10n.format("Темп выше вашего обычного риск-порога (%.1f ст.др./ч).", paceRiskThreshold))
        }
        if currentHydration < hydrationGoalProgress {
            notes.append(L10n.format("Гидратация ниже вашего персонального ориентира (%d%%).", Int((hydrationGoalProgress * 100).rounded())))
        }
        if let wellbeingAverage, wellbeingAverage < 3 {
            notes.append(L10n.tr("По истории ваше среднее самочувствие утром ниже 3/5."))
        }
        if notes.isEmpty {
            notes.append(L10n.tr("Текущая сессия пока в пределах ваших обычных паттернов."))
        }

        var actions: [String] = []
        if currentHydration < hydrationGoalProgress {
            actions.append(L10n.format("Закройте разницу до вашего личного водного ориентира: +%d мл постепенно.", Int(((hydrationGoalProgress - currentHydration) * 1000).rounded())))
        }
        if currentPace >= paceRiskThreshold {
            actions.append(L10n.tr("Снизьте темп до пауз 25-30 минут между алкогольными напитками."))
        }
        if session.cachedPeakBAC >= memoryRiskThreshold {
            actions.append(L10n.tr("Риск провалов памяти выше вашей нормы: лучше завершить алкоголь на сегодня."))
        }
        if waterStreak < 2 {
            actions.append(L10n.tr("Сформируйте streak воды хотя бы на 2 сессии подряд."))
        }
        if mealStreak < 2 {
            actions.append(L10n.tr("Добавляйте прием пищи в начале сессии для более стабильного состояния."))
        }
        if actions.isEmpty {
            actions.append(L10n.tr("Сохраняйте текущую стратегию: темп и вода лучше ваших последних сессий."))
        }

        return PersonalizedPatternAssessment(
            peakRiskThreshold: peakRiskThreshold,
            memoryRiskThreshold: memoryRiskThreshold,
            paceRiskThreshold: paceRiskThreshold,
            hydrationGoalProgress: hydrationGoalProgress,
            peakTrend: peakTrend,
            hydrationTrend: hydrationTrend,
            wellbeingTrend: wellbeingTrend,
            waterStreak: waterStreak,
            mealStreak: mealStreak,
            notes: Array(notes.prefix(4)),
            actions: Array(actions.prefix(4))
        )
    }

    func eveningScenarios(
        for session: Session,
        profile: UserProfile? = nil,
        history: [Session]
    ) -> [EveningScenario] {
        let baseline = assess(session: session, profile: profile, history: history)
        let patterns = personalizedPatterns(current: session, history: history, profile: profile)
        let currentPace = averagePace(for: session) ?? patterns.paceRiskThreshold
        let hydration = hydrationProgress(for: session, profile: profile)

        var continueMorning = baseline.morningProbabilityPercent
        var continueMemory = baseline.memoryProbabilityPercent
        continueMorning += currentPace >= patterns.paceRiskThreshold ? 12 : 6
        continueMemory += currentPace >= patterns.paceRiskThreshold ? 10 : 5
        if hydration < patterns.hydrationGoalProgress {
            continueMorning += 8
        }
        if session.cachedPeakBAC >= patterns.peakRiskThreshold {
            continueMorning += 6
        }

        var pauseMorning = baseline.morningProbabilityPercent
        var pauseMemory = baseline.memoryProbabilityPercent
        pauseMorning -= hydration < patterns.hydrationGoalProgress ? 14 : 8
        pauseMemory -= 6
        if session.meals.isEmpty {
            pauseMorning -= 4
        }

        let cocktailMorning = baseline.morningProbabilityPercent + 10
        var cocktailMemory = baseline.memoryProbabilityPercent + 18
        if session.cachedPeakBAC >= patterns.memoryRiskThreshold {
            cocktailMemory += 8
        }

        return [
            EveningScenario(
                id: "continue-pace",
                title: L10n.tr("Если продолжать в том же темпе"),
                subtitle: L10n.tr("Еще ~1 час без снижения темпа"),
                impactText: L10n.format("Риск утра ~%d%%, риск провалов ~%d%%", cappedPercent(continueMorning), cappedPercent(continueMemory)),
                recommendation: L10n.tr("Снизьте темп и добавьте воду, чтобы не заходить в вашу зону повышенного риска.")
            ),
            EveningScenario(
                id: "pause-water",
                title: L10n.tr("Если сделать паузу и воду"),
                subtitle: L10n.tr("Пауза 45-60 минут + вода"),
                impactText: L10n.format("Риск утра ~%d%%, риск провалов ~%d%%", cappedPercent(pauseMorning), cappedPercent(pauseMemory)),
                recommendation: L10n.tr("Это обычно лучший сценарий для более мягкого утра по вашей истории.")
            ),
            EveningScenario(
                id: "strong-cocktail",
                title: L10n.tr("Если добавить крепкий коктейль сейчас"),
                subtitle: L10n.tr("Дополнительный крепкий напиток"),
                impactText: L10n.format("Риск утра ~%d%%, риск провалов ~%d%%", cappedPercent(cocktailMorning), cappedPercent(cocktailMemory)),
                recommendation: L10n.tr("При таком сценарии разумнее завершать алкоголь и перейти на воду/еду.")
            )
        ]
    }

    func memoryProjections(
        for session: Session,
        profile: UserProfile? = nil,
        history: [Session],
        horizons: [Int] = [30, 60]
    ) -> [MemoryProjection] {
        let baseline = assess(session: session, profile: profile, history: history)
        let patterns = personalizedPatterns(current: session, history: history, profile: profile)
        let currentPace = averagePace(for: session) ?? patterns.paceRiskThreshold
        let hydration = hydrationProgress(for: session, profile: profile)

        return horizons.map { horizon in
            let paceFactor = currentPace >= patterns.paceRiskThreshold ? 10 : 5
            let longHorizonFactor = horizon >= 60 ? 8 : 4
            let hydrationFactor = hydration < patterns.hydrationGoalProgress ? 6 : 2
            let peakFactor = session.cachedPeakBAC >= patterns.memoryRiskThreshold ? 8 : 3
            let projected = cappedPercent(
                baseline.memoryProbabilityPercent + paceFactor + longHorizonFactor + hydrationFactor + peakFactor
            )

            let comment: String
            if projected >= 70 {
                comment = L10n.tr("Лучше остановиться на воде и еде.")
            } else if projected >= 45 {
                comment = L10n.tr("Снижайте темп и сделайте паузу.")
            } else {
                comment = L10n.tr("Риск пока умеренный, поддерживайте осторожный темп.")
            }

            return MemoryProjection(
                id: "memory-\(horizon)",
                horizonMinutes: horizon,
                memoryProbabilityPercent: projected,
                comment: comment
            )
        }
    }

    func weeklySnapshot(
        sessions history: [Session],
        profile: UserProfile? = nil
    ) -> WeeklyInsightSnapshot {
        let completed = history
            .filter { !$0.isActive }
            .sorted(by: { $0.startAt > $1.startAt })
        let weekStart = Calendar.current.date(byAdding: .day, value: -7, to: .now) ?? .now
        let weekSessions = completed.filter { $0.startAt >= weekStart }
        let window = weekSessions.isEmpty ? Array(completed.prefix(7)) : weekSessions

        let assessments = window.map { assess(session: $0, profile: profile, at: $0.endAt ?? .now, history: window) }
        let heavyMorningCount = assessments.filter { $0.morningRisk == .high }.count
        let highMemoryRiskCount = assessments.filter { $0.memoryRisk == .high }.count
        let hydrationHitCount = assessments.filter { $0.waterBalance.progress >= 0.85 }.count
        let mealHitCount = window.filter { !$0.meals.isEmpty }.count
        let peakValues = window.map(\.cachedPeakBAC).filter { $0 > 0 }
        let wellbeingValues = window.compactMap { $0.morningCheckIn?.wellbeingScore }

        let sessionsCount = max(1, window.count)
        let hydrationHitRatePercent = Int((Double(hydrationHitCount) / Double(sessionsCount) * 100).rounded())
        let mealCoveragePercent = Int((Double(mealHitCount) / Double(sessionsCount) * 100).rounded())
        let averagePeakBAC = peakValues.isEmpty ? 0 : (peakValues.reduce(0, +) / Double(peakValues.count))
        let averageWellbeingScore = wellbeingValues.isEmpty ? nil : (Double(wellbeingValues.reduce(0, +)) / Double(wellbeingValues.count))

        let headline: String
        if highMemoryRiskCount >= 3 {
            headline = L10n.tr("Неделя с повышенным риском памяти: стоит снизить темп и крепость.")
        } else if heavyMorningCount >= 3 {
            headline = L10n.tr("На этой неделе было много тяжелых утр — поможет более ранний стоп.")
        } else if hydrationHitRatePercent >= 70 {
            headline = L10n.tr("Гидратация стабильная: это снижает риск тяжелого утра.")
        } else {
            headline = L10n.tr("Есть пространство улучшить вечерний процесс: вода, паузы и еда дадут эффект.")
        }

        return WeeklyInsightSnapshot(
            sessionsCount: window.count,
            heavyMorningCount: heavyMorningCount,
            highMemoryRiskCount: highMemoryRiskCount,
            hydrationHitRatePercent: hydrationHitRatePercent,
            mealCoveragePercent: mealCoveragePercent,
            averagePeakBAC: averagePeakBAC,
            averageWellbeingScore: averageWellbeingScore,
            headline: headline
        )
    }

    func triggerPatterns(
        sessions history: [Session],
        profile: UserProfile? = nil
    ) -> TriggerPatternsSummary {
        let completed = history
            .filter { !$0.isActive }
            .sorted(by: { $0.startAt > $1.startAt })
        let sample = Array(completed.prefix(20))
        guard !sample.isEmpty else {
            return TriggerPatternsSummary(
                weekdayHotspot: nil,
                startHourHotspot: nil,
                drinkCategoryHotspot: nil,
                hits: []
            )
        }

        let calendar = Calendar.current
        var weekdayCounts: [Int: Int] = [:]
        var startHourCounts: [Int: Int] = [:]
        var categoryCounts: [DrinkEntry.Category: Int] = [:]
        var riskSessions = 0

        for session in sample {
            let assessment = assess(session: session, profile: profile, at: session.endAt ?? .now, history: sample)
            let checkInLow = (session.morningCheckIn?.wellbeingScore ?? 5) <= 2
            let isRisky = assessment.morningRisk == .high || assessment.memoryRisk == .high || checkInLow
            guard isRisky else { continue }
            riskSessions += 1

            let weekday = calendar.component(.weekday, from: session.startAt)
            weekdayCounts[weekday, default: 0] += 1

            let hour = calendar.component(.hour, from: session.startAt)
            startHourCounts[hour, default: 0] += 1

            if let dominant = dominantCategory(in: session) {
                categoryCounts[dominant, default: 0] += 1
            }
        }

        let weekdayHotspot = weekdayCounts.max(by: { $0.value < $1.value }).map { weekdayLabel($0.key) }
        let startHourHotspot = startHourCounts.max(by: { $0.value < $1.value }).map { startHourLabel($0.key) }
        let drinkCategoryHotspot = categoryCounts.max(by: { $0.value < $1.value }).map { $0.key.label }

        var hits: [TriggerPatternHit] = []
        if let day = weekdayHotspot, let count = weekdayCounts.max(by: { $0.value < $1.value })?.value {
            hits.append(
                TriggerPatternHit(
                    id: "weekday",
                    title: L10n.tr("День недели"),
                    value: day,
                    impact: L10n.format("В %d risk-сессиях из %d.", count, max(1, riskSessions))
                )
            )
        }
        if let hourLabel = startHourHotspot, let count = startHourCounts.max(by: { $0.value < $1.value })?.value {
            hits.append(
                TriggerPatternHit(
                    id: "hour",
                    title: L10n.tr("Время старта"),
                    value: hourLabel,
                    impact: L10n.format("Чаще дает тяжелое утро/риск памяти (%d раз).", count)
                )
            )
        }
        if let category = drinkCategoryHotspot, let count = categoryCounts.max(by: { $0.value < $1.value })?.value {
            hits.append(
                TriggerPatternHit(
                    id: "category",
                    title: L10n.tr("Тип напитков"),
                    value: category,
                    impact: L10n.format("Чаще встречается в risky-сессиях (%d раз).", count)
                )
            )
        }

        return TriggerPatternsSummary(
            weekdayHotspot: weekdayHotspot,
            startHourHotspot: startHourHotspot,
            drinkCategoryHotspot: drinkCategoryHotspot,
            hits: hits
        )
    }

    private func makeWaterBalance(
        session: Session,
        profile: UserProfile?,
        durationHours: Double,
        standardDrinksTotal: Double
    ) -> WaterBalanceSnapshot {
        let consumedMl = Int(session.waters.compactMap(\.volumeMl).reduce(0, +))
        let unknownMarksCount = session.waters.filter { $0.volumeMl == nil }.count

        let weightFactor = Int(weightInKg(profile) * 8.0)
        let dynamicTarget = (standardDrinksTotal * 250) + max(0, durationHours - 1) * 120
        let targetMl = roundTo50(max(600, weightFactor + Int(dynamicTarget)))
        let deficitMl = max(0, targetMl - consumedMl)
        let suggestedTopUpMl = deficitMl > 0 ? min(350, max(150, roundTo50(deficitMl / 2))) : 0

        let status: WaterBalanceStatus
        switch deficitMl {
        case ..<150:
            status = .balanced
        case 150..<450:
            status = .mildDeficit
        default:
            status = .highDeficit
        }

        return WaterBalanceSnapshot(
            consumedMl: consumedMl,
            targetMl: targetMl,
            deficitMl: deficitMl,
            status: status,
            unknownMarksCount: unknownMarksCount,
            suggestedTopUpMl: suggestedTopUpMl
        )
    }

    private func makeActionsNow(
        morningRisk: InsightLevel,
        memoryRisk: InsightLevel,
        waterBalance: WaterBalanceSnapshot,
        currentBAC: Double?,
        drinksPerHour: Double,
        mealMitigation: MealMitigation
    ) -> [String] {
        var actions: [String] = []

        if waterBalance.deficitMl > 0 {
            actions.append(L10n.format("Выпейте сейчас ~%d мл воды", waterBalance.suggestedTopUpMl))
        }

        if drinksPerHour >= 1.5 {
            actions.append(L10n.tr("Сделайте паузу 20-30 минут без алкоголя"))
        }

        if let currentBAC, currentBAC >= 0.10 {
            actions.append(L10n.tr("Переключитесь на воду и еду, темп сейчас высокий"))
        }
        if mealMitigation.scoreReduction == 0 {
            actions.append(L10n.tr("Добавьте прием пищи, это может смягчить состояние"))
        }

        if memoryRisk == .high {
            actions.append(L10n.tr("Старайтесь быть рядом с надежным человеком"))
        }

        if morningRisk == .high {
            actions.append(L10n.tr("Планируйте щадящее утро и дополнительное время на восстановление"))
        }

        if actions.isEmpty {
            actions.append(L10n.tr("Сохраняйте текущий умеренный темп"))
        }

        return Array(actions.prefix(3))
    }

    private func makeConfidence(
        session: Session,
        profile: UserProfile?,
        waterBalance: WaterBalanceSnapshot,
        durationHours: Double
    ) -> InsightConfidence {
        var score = 100
        var reasons: [String] = []

        if profile == nil {
            score -= 35
            reasons.append(L10n.tr("Профиль не заполнен полностью, оценка менее точная"))
        } else if profile?.sex == .unspecified {
            score -= 10
            reasons.append(L10n.tr("Пол не указан, используется усредненный коэффициент"))
        }

        if session.drinks.count < 2 {
            score -= 10
            reasons.append(L10n.tr("Слишком мало данных в текущей сессии"))
        }

        if waterBalance.unknownMarksCount > 0 {
            score -= min(20, waterBalance.unknownMarksCount * 6)
            reasons.append(L10n.tr("Есть отметки воды без объема"))
        }

        if session.meals.isEmpty {
            score -= 8
            reasons.append(L10n.tr("Приемы пищи не отмечены"))
        }

        if durationHours >= 8 {
            score -= 6
            reasons.append(L10n.tr("Длинная сессия снижает точность простой модели"))
        }

        let percent = Int(clamp(Double(score), min: 15, max: 98))
        let level: InsightLevel
        switch percent {
        case 75...:
            level = .low
        case 45...74:
            level = .medium
        default:
            level = .high
        }

        if reasons.isEmpty {
            reasons.append(L10n.tr("Данных достаточно, точность оценки выше средней"))
        }

        return InsightConfidence(
            level: level,
            scorePercent: percent,
            reasons: Array(reasons.prefix(3))
        )
    }

    private func makeRiskEvents(
        session: Session,
        waterBalance: WaterBalanceSnapshot,
        drinksPerHour: Double,
        morningRisk: InsightLevel,
        memoryRisk: InsightLevel
    ) -> [RiskEvent] {
        var result: [RiskEvent] = []
        let orderedDrinks = session.drinks.sorted(by: { $0.createdAt < $1.createdAt })
        let orderedWaters = session.waters.sorted(by: { $0.createdAt < $1.createdAt })

        if drinksPerHour >= 1.7 {
            result.append(
                RiskEvent(
                    id: "pace-high",
                    date: orderedDrinks.last?.createdAt ?? .now,
                    severity: .high,
                    title: L10n.tr("Высокий темп"),
                    detail: L10n.format("Темп около %.1f ст.др./ч, это повышает утренний и memory-риск.", drinksPerHour)
                )
            )
        } else if drinksPerHour >= 1.2 {
            result.append(
                RiskEvent(
                    id: "pace-medium",
                    date: orderedDrinks.last?.createdAt ?? .now,
                    severity: .medium,
                    title: L10n.tr("Темп выше умеренного"),
                    detail: L10n.tr("Ускорение темпа повышает нагрузку, лучше добавить паузу.")
                )
            )
        }

        for (index, drink) in orderedDrinks.enumerated() where drink.abvPercent >= 30 {
            result.append(
                RiskEvent(
                    id: "strong-\(index)",
                    date: drink.createdAt,
                    severity: drink.abvPercent >= 40 ? .high : .medium,
                    title: L10n.tr("Крепкий напиток"),
                    detail: L10n.format("%@, %d%% ABV", (drink.title ?? drink.category.label).localized, Int(drink.abvPercent))
                )
            )
        }

        for (lhs, rhs) in zip(orderedDrinks, orderedDrinks.dropFirst()) {
            let minutes = rhs.createdAt.timeIntervalSince(lhs.createdAt) / 60
            if minutes <= 20 {
                result.append(
                    RiskEvent(
                        id: "burst-\(rhs.id.uuidString)",
                        date: rhs.createdAt,
                        severity: .high,
                        title: L10n.tr("Серия без паузы"),
                        detail: L10n.tr("Два алкогольных напитка подряд с коротким интервалом.")
                    )
                )
            }
        }

        if let firstDrink = orderedDrinks.first {
            let firstWater = orderedWaters.first?.createdAt
            if firstWater == nil || (firstWater!.timeIntervalSince(firstDrink.createdAt) / 60) > 90 {
                result.append(
                    RiskEvent(
                        id: "late-water",
                        date: firstWater ?? .now,
                        severity: .medium,
                        title: L10n.tr("Поздний старт воды"),
                        detail: L10n.tr("Вода началась заметно позже первого алкогольного напитка.")
                    )
                )
            }
        }

        if waterBalance.status == .highDeficit {
            result.append(
                RiskEvent(
                    id: "water-deficit",
                    date: .now,
                    severity: .high,
                    title: L10n.tr("Высокий дефицит воды"),
                    detail: L10n.format("До ориентира осталось около %d мл.", waterBalance.deficitMl)
                )
            )
        }

        if session.meals.isEmpty, orderedDrinks.count >= 3 {
            result.append(
                RiskEvent(
                    id: "no-meal",
                    date: orderedDrinks.last?.createdAt ?? .now,
                    severity: .medium,
                    title: L10n.tr("Без приема пищи"),
                    detail: L10n.tr("При отсутствии еды нагрузка обычно ощущается сильнее.")
                )
            )
        }

        if memoryRisk == .high {
            result.append(
                RiskEvent(
                    id: "memory-high",
                    date: .now,
                    severity: .high,
                    title: L10n.tr("Высокий риск фрагментов памяти"),
                    detail: L10n.tr("Лучше завершить алкоголь и перейти на воду/восстановление.")
                )
            )
        }

        if morningRisk == .high {
            result.append(
                RiskEvent(
                    id: "morning-high",
                    date: .now,
                    severity: .medium,
                    title: L10n.tr("Высокий риск тяжелого утра"),
                    detail: L10n.tr("Дополнительный алкоголь сейчас заметно ухудшит восстановление.")
                )
            )
        }

        return Array(
            result
                .sorted(by: { $0.date > $1.date })
                .prefix(7)
        )
    }

    private func mealMitigationScore(session: Session, at date: Date) -> MealMitigation {
        guard !session.meals.isEmpty else {
            return MealMitigation(scoreReduction: 0, reason: L10n.tr("прием пищи не отмечен"), summary: L10n.tr("Еда не отмечена"))
        }

        let firstDrinkAt = session.drinks.map(\.createdAt).min()
        let relevant = session.meals.filter { meal in
            abs(meal.createdAt.timeIntervalSince(date)) <= 6 * 3600
        }

        guard !relevant.isEmpty else {
            return MealMitigation(scoreReduction: 0, reason: L10n.tr("последний прием пищи был давно"), summary: L10n.tr("Последний прием пищи был давно"))
        }

        let baseMitigationPoints = relevant.reduce(0.0) { partial, meal in
            partial + meal.size.mitigationWeight
        }
        // Meal timing relative to first drink usually has the strongest real-world effect.
        let timingBonus = firstDrinkAt.map { firstDrink in
            relevant.contains { meal in
                let deltaMinutes = meal.createdAt.timeIntervalSince(firstDrink) / 60
                return (-90...30).contains(deltaMinutes)
            }
        } ?? false
        let mitigationPoints = baseMitigationPoints + (timingBonus ? 0.7 : 0)
        let reduction: Int
        switch mitigationPoints {
        case ..<1:
            reduction = 0
        case 1..<2.5:
            reduction = 1
        default:
            reduction = 2
        }

        let summary: String
        if reduction > 0, timingBonus {
            summary = L10n.tr("Еда принята в удачное время и снижает риск")
        } else if reduction > 0 {
            summary = L10n.tr("Прием пищи частично снижает риск")
        } else {
            summary = L10n.tr("Эффект еды минимальный")
        }

        return MealMitigation(
            scoreReduction: reduction,
            reason: reduction > 0
                ? (timingBonus ? L10n.tr("прием пищи был вовремя и может смягчить состояние") : L10n.tr("прием пищи может смягчить состояние"))
                : L10n.tr("прием пищи пока слабо влияет на риски"),
            summary: summary
        )
    }

    private func standardDrinks(from drink: DrinkEntry) -> Double {
        let grams = drink.volumeMl * (drink.abvPercent / 100) * 0.789
        return grams / 14
    }

    private func strongestABV(in session: Session) -> Double {
        session.drinks.map(\.abvPercent).max() ?? 0
    }

    private func dominantCategory(in session: Session) -> DrinkEntry.Category? {
        guard !session.drinks.isEmpty else { return nil }
        var counts: [DrinkEntry.Category: Int] = [:]
        for drink in session.drinks {
            counts[drink.category, default: 0] += 1
        }
        return counts.max(by: { $0.value < $1.value })?.key
    }

    private func weekdayLabel(_ weekday: Int) -> String {
        let symbols = Calendar.current.weekdaySymbols
        guard weekday >= 1, weekday <= symbols.count else { return L10n.tr("Неизвестно") }
        return symbols[weekday - 1]
    }

    private func startHourLabel(_ hour: Int) -> String {
        let end = (hour + 2) % 24
        return L10n.format("%02d:00-%02d:00", hour, end)
    }

    private func averagePace(for session: Session) -> Double? {
        let durationHours = max(0.1, (session.endAt ?? .now).timeIntervalSince(session.startAt) / 3600)
        let total = session.drinks.reduce(0.0) { partial, drink in
            partial + standardDrinks(from: drink)
        }
        guard total > 0 else { return nil }
        return total / durationHours
    }

    private func hydrationProgress(for session: Session, profile: UserProfile?) -> Double {
        let durationHours = max(0, (session.endAt ?? .now).timeIntervalSince(session.startAt) / 3600)
        let standardDrinksTotal = session.drinks.reduce(0.0) { partial, drink in
            partial + standardDrinks(from: drink)
        }
        let water = makeWaterBalance(
            session: session,
            profile: profile,
            durationHours: durationHours,
            standardDrinksTotal: standardDrinksTotal
        )
        return water.progress
    }

    private func trendDirection(values: [Double], lowerIsBetter: Bool) -> TrendDirection {
        guard values.count >= 4 else { return .stable }
        let firstHalf = Array(values.prefix(values.count / 2))
        let secondHalf = Array(values.suffix(values.count - firstHalf.count))
        guard !firstHalf.isEmpty, !secondHalf.isEmpty else { return .stable }
        let firstMean = firstHalf.reduce(0, +) / Double(firstHalf.count)
        let secondMean = secondHalf.reduce(0, +) / Double(secondHalf.count)
        let delta = secondMean - firstMean
        if abs(delta) < 0.05 {
            return .stable
        }
        if lowerIsBetter {
            return delta < 0 ? .improving : .worsening
        }
        return delta > 0 ? .improving : .worsening
    }

    private func streakCount(in sessions: [Session], condition: (Session) -> Bool) -> Int {
        var count = 0
        for session in sessions {
            if condition(session) {
                count += 1
            } else {
                break
            }
        }
        return count
    }

    private func personalLearningSnapshot(
        current session: Session,
        history: [Session],
        profile: UserProfile?,
        at date: Date
    ) -> PersonalLearningSnapshot? {
        let training = history
            .filter { !$0.isActive && $0.id != session.id && $0.morningCheckIn != nil }
            .sorted(by: { $0.startAt > $1.startAt })
        let window = Array(training.prefix(14))
        guard window.count >= 4 else { return nil }

        let currentFeatures = learningFeatures(for: session, profile: profile, at: date)
        let roughFlags = window.map { (($0.morningCheckIn?.wellbeingScore ?? 5) <= 2) ? 1.0 : 0.0 }
        let overallRoughRate = roughFlags.reduce(0, +) / Double(window.count)

        var deltas: [Int] = []
        func appendDelta(
            _ isEnabled: Bool,
            by keyPath: KeyPath<LearningFeatures, Bool>
        ) {
            guard isEnabled else { return }
            let matching = window.filter {
                learningFeatures(for: $0, profile: profile, at: $0.endAt ?? date)[keyPath: keyPath]
            }
            guard matching.count >= 3 else { return }
            let roughCount = matching.filter { ($0.morningCheckIn?.wellbeingScore ?? 5) <= 2 }.count
            let roughRate = Double(roughCount) / Double(matching.count)
            let diff = roughRate - overallRoughRate
            if diff >= 0.15 {
                deltas.append(1)
            } else if diff <= -0.15 {
                deltas.append(-1)
            }
        }

        appendDelta(currentFeatures.highPeak, by: \.highPeak)
        appendDelta(currentFeatures.fastPace, by: \.fastPace)
        appendDelta(currentFeatures.lowHydration, by: \.lowHydration)
        appendDelta(currentFeatures.longSession, by: \.longSession)
        appendDelta(currentFeatures.noWater, by: \.noWater)
        appendDelta(currentFeatures.noMeal, by: \.noMeal)

        let scoreDelta = max(-2, min(2, deltas.reduce(0, +)))

        let modelObservedPairs = window.map { past -> (Int, Int) in
            let model = assess(
                session: past,
                profile: profile,
                at: past.endAt ?? date,
                history: nil,
                useObservedCheckIn: false
            ).morningProbabilityPercent
            let observed = observedMorningProbability(
                for: max(0, min(5, past.morningCheckIn?.wellbeingScore ?? 5))
            )
            return (model, observed)
        }
        let avgDiff = modelObservedPairs.reduce(0.0) { partial, pair in
            partial + Double(pair.1 - pair.0)
        } / Double(modelObservedPairs.count)
        let probabilityBias = max(-20, min(20, Int(avgDiff.rounded())))

        if scoreDelta == 0 && probabilityBias == 0 {
            return nil
        }
        return PersonalLearningSnapshot(scoreDelta: scoreDelta, probabilityBias: probabilityBias)
    }

    private func learningFeatures(
        for session: Session,
        profile: UserProfile?,
        at date: Date
    ) -> LearningFeatures {
        let durationHours = max(0, (session.endAt ?? date).timeIntervalSince(session.startAt) / 3600)
        let pace = averagePace(for: session) ?? 0
        let hydration = hydrationProgress(for: session, profile: profile)
        return LearningFeatures(
            highPeak: session.cachedPeakBAC >= 0.16,
            fastPace: pace >= 1.5,
            lowHydration: hydration < 0.75,
            longSession: durationHours >= 4,
            noWater: session.waters.isEmpty,
            noMeal: session.meals.isEmpty
        )
    }

    private func level(forMorningScore score: Int) -> InsightLevel {
        switch score {
        case ..<2: return .low
        case 2...4: return .medium
        default: return .high
        }
    }

    private func level(forCalibratedMorningProbability probability: Int) -> InsightLevel {
        switch probability {
        case ..<30:
            return .low
        case 30...64:
            return .medium
        default:
            return .high
        }
    }

    private func observedMorningRisk(for wellbeingScore: Int) -> InsightLevel {
        switch wellbeingScore {
        case 0...2:
            return .high
        case 3:
            return .medium
        default:
            return .low
        }
    }

    private func observedMorningProbability(for wellbeingScore: Int) -> Int {
        switch wellbeingScore {
        case 5:
            return 10
        case 4:
            return 25
        case 3:
            return 50
        case 2:
            return 70
        case 1:
            return 85
        default:
            return 95
        }
    }

    private func level(forMemoryScore score: Int) -> InsightLevel {
        switch score {
        case ..<2: return .low
        case 2...4: return .medium
        default: return .high
        }
    }

    private func roundTo50(_ value: Int) -> Int {
        let rounded = Int((Double(value) / 50.0).rounded()) * 50
        return max(0, rounded)
    }

    private func riskPercent(score: Int, maxScore: Int) -> Int {
        guard maxScore > 0 else { return 0 }
        let value = Double(score) / Double(maxScore)
        return Int((clamp(value, min: 0, max: 1) * 100).rounded())
    }

    private func cappedPercent(_ value: Int) -> Int {
        Int(clamp(Double(value), min: 0, max: 99))
    }

    private func clamp(_ value: Double, min minValue: Double, max maxValue: Double) -> Double {
        Swift.max(minValue, Swift.min(maxValue, value))
    }

    private func weightInKg(_ profile: UserProfile?) -> Double {
        guard let profile else { return 70 }
        switch profile.unitSystem {
        case .metric:
            return max(40, profile.weight)
        case .imperial:
            return max(40, profile.weight * 0.453592)
        }
    }
}

private struct MealMitigation {
    let scoreReduction: Int
    let reason: String?
    let summary: String
}
