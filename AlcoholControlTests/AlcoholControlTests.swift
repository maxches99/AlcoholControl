//
//  AlcoholControlTests.swift
//  AlcoholControlTests
//
//  Created by Maxim Chesnikov on 11.02.2026.
//

import Foundation
import SwiftData
import Testing
@testable import AlcoholControl

private struct StubShadowPredictor: ShadowRiskPredicting {
    let morning: Double?
    let memory: Double?

    func delta(outputName: String, features: [String : Double]) -> Double? {
        switch outputName {
        case "morningDelta":
            return morning
        case "memoryDelta":
            return memory
        default:
            return nil
        }
    }
}

private struct StubPersonalTrendPredictor: PersonalTrendPredicting {
    let headache: Double?
    let fatigue: Double?
    let heavyMorning: Double?

    func probability(outputName: String, features: [String : Double]) -> Double? {
        switch outputName {
        case "headacheProbability":
            return headache
        case "fatigueProbability":
            return fatigue
        case "heavyMorningProbability":
            return heavyMorning
        default:
            return nil
        }
    }
}

struct AlcoholControlTests {

    @Test @MainActor func openTodayResetsPendingRoutes() async throws {
        let state = AppState()
        state.pendingMorningCheckInSessionID = UUID()
        state.pendingOpenLatestMorningCheckIn = true
        state.pendingForecastSessionID = UUID()
        state.selectedTab = .settings

        state.openToday()

        #expect(state.selectedTab == .today)
        #expect(state.pendingMorningCheckInSessionID == nil)
        #expect(state.pendingOpenLatestMorningCheckIn == false)
        #expect(state.pendingForecastSessionID == nil)
    }

    @Test @MainActor func openMorningCheckInWithSessionKeepsSpecificRoute() async throws {
        let state = AppState()
        let id = UUID()

        state.openMorningCheckIn(sessionID: id)

        #expect(state.selectedTab == .today)
        #expect(state.pendingMorningCheckInSessionID == id)
        #expect(state.pendingOpenLatestMorningCheckIn == false)
    }

    @Test @MainActor func openMorningCheckInWithoutSessionRequestsLatest() async throws {
        let state = AppState()

        state.openMorningCheckIn(sessionID: nil)

        #expect(state.selectedTab == .today)
        #expect(state.pendingMorningCheckInSessionID == nil)
        #expect(state.pendingOpenLatestMorningCheckIn == true)
    }

    @Test @MainActor func openForecastClearsCheckInRoutes() async throws {
        let state = AppState()
        let forecastID = UUID()
        state.pendingMorningCheckInSessionID = UUID()
        state.pendingOpenLatestMorningCheckIn = true

        state.openForecast(sessionID: forecastID)

        #expect(state.selectedTab == .today)
        #expect(state.pendingMorningCheckInSessionID == nil)
        #expect(state.pendingOpenLatestMorningCheckIn == false)
        #expect(state.pendingForecastSessionID == forecastID)
    }

    @Test @MainActor func addDrinkRecomputesBACWhenProfileArgumentIsNil() throws {
        let container = try ModelContainer(
            for: UserProfile.self,
            Session.self,
            DrinkEntry.self,
            WaterEntry.self,
            MealEntry.self,
            MorningCheckIn.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = ModelContext(container)
        let service = SessionService()

        let storedProfile = UserProfile(weight: 80, sex: .male, unitSystem: .metric)
        context.insert(storedProfile)

        let session = Session()
        context.insert(session)

        service.addDrink(
            to: session,
            context: context,
            profile: nil,
            createdAt: .now,
            volumeMl: 500,
            abvPercent: 5,
            title: "Beer",
            category: .beer
        )

        #expect(session.cachedPeakBAC > 0)
        #expect(session.cachedEstimatedSoberAt != nil)
    }

    @Test func morningCheckInOverridesModelMorningRisk() {
        let service = SessionInsightService()
        let now = Date.now
        let session = Session(
            startAt: now.addingTimeInterval(-6 * 3600),
            endAt: now.addingTimeInterval(-2 * 3600),
            isActive: false,
            cachedPeakBAC: 0.19,
            cachedEstimatedSoberAt: now.addingTimeInterval(4 * 3600)
        )
        let checkIn = MorningCheckIn(wellbeingScore: 4, session: session)
        session.morningCheckIn = checkIn

        let assessment = service.assess(session: session, profile: nil, at: now)

        #expect(assessment.morningRisk == .low)
        #expect(assessment.morningProbabilityPercent == 25)
        #expect(assessment.morningReasons.first == "Самочувствие: 4/5")
    }

    @Test func assessLearnsFromHistoryCalibration() {
        let service = SessionInsightService()
        let now = Date.now

        let current = Session(
            startAt: now.addingTimeInterval(-3 * 3600),
            endAt: now.addingTimeInterval(-1 * 3600),
            isActive: true,
            cachedPeakBAC: 0.09,
            cachedEstimatedSoberAt: now.addingTimeInterval(2 * 3600)
        )

        var history: [Session] = []
        for offset in 1...6 {
            let start = now.addingTimeInterval(-Double(offset + 1) * 24 * 3600)
            let session = Session(
                startAt: start,
                endAt: start.addingTimeInterval(90 * 60),
                isActive: false,
                cachedPeakBAC: 0.08,
                cachedEstimatedSoberAt: start.addingTimeInterval(3 * 3600)
            )
            let water = WaterEntry(volumeMl: 300, session: session)
            let meal = MealEntry(title: "Meal", size: .regular, session: session)
            session.waters = [water]
            session.meals = [meal]
            let checkIn = MorningCheckIn(wellbeingScore: 1, session: session)
            session.morningCheckIn = checkIn
            history.append(session)
        }

        let base = service.assess(session: current, profile: nil, at: now)
        let learned = service.assess(session: current, profile: nil, at: now, history: history)

        #expect(learned.morningProbabilityPercent >= base.morningProbabilityPercent + 10)
        #expect(learned.morningReasons.contains(L10n.tr("Индивидуальный ориентир риска, рассчитанный по вашим предыдущим сессиям.")))
    }

    @Test func shadowAssessmentRequiresEnoughHistory() {
        let service = SessionInsightService()
        let now = Date.now
        let session = Session(
            startAt: now.addingTimeInterval(-2 * 3600),
            endAt: now.addingTimeInterval(-30 * 60),
            isActive: true,
            cachedPeakBAC: 0.10,
            cachedEstimatedSoberAt: now.addingTimeInterval(2 * 3600)
        )
        let baseline = service.assess(session: session, profile: nil, at: now, history: [])

        let shadow = service.assessShadow(
            session: session,
            profile: nil,
            at: now,
            health: nil,
            history: [],
            baseline: baseline
        )

        switch shadow.status {
        case .insufficientData:
            #expect(true)
        case .ready:
            #expect(Bool(false), "Shadow assessment should require more history")
        }
        #expect(shadow.morningProbabilityPercent == nil)
        #expect(shadow.memoryProbabilityPercent == nil)
    }

    @Test func shadowAssessmentUsesInjectedPredictorWhenAvailable() {
        let now = Date.now
        let current = Session(
            startAt: now.addingTimeInterval(-3 * 3600),
            endAt: now.addingTimeInterval(-20 * 60),
            isActive: true,
            cachedPeakBAC: 0.14,
            cachedEstimatedSoberAt: now.addingTimeInterval(2 * 3600)
        )
        current.meals = [MealEntry(title: "Meal", size: .regular, session: current)]
        current.waters = [WaterEntry(volumeMl: 250, session: current)]

        var history: [Session] = []
        for day in 1...6 {
            let start = now.addingTimeInterval(-Double(day) * 24 * 3600)
            let session = Session(
                startAt: start,
                endAt: start.addingTimeInterval(2 * 3600),
                isActive: false,
                cachedPeakBAC: 0.11,
                cachedEstimatedSoberAt: start.addingTimeInterval(3 * 3600)
            )
            session.waters = [WaterEntry(volumeMl: 300, session: session)]
            history.append(session)
        }

        let baseService = SessionInsightService()
        let baseline = baseService.assess(session: current, profile: nil, at: now, history: history)
        let service = SessionInsightService(shadowPredictor: StubShadowPredictor(morning: 0.90, memory: 0.80))

        let shadow = service.assessShadow(
            session: current,
            profile: nil,
            at: now,
            health: nil,
            history: history,
            baseline: baseline
        )

        switch shadow.status {
        case .ready:
            #expect(true)
        case .insufficientData:
            #expect(Bool(false), "Expected ready status with enough history")
        }
        #expect(shadow.note == L10n.tr("CoreML shadow-прогноз: на основе ваших данных, отдельно от основного расчета."))

        let expectedMorning = min(99, max(0, Int((Double(baseline.morningProbabilityPercent) * 0.65 + 0.90 * 35).rounded())))
        let expectedMemory = min(99, max(0, Int((Double(baseline.memoryProbabilityPercent) * 0.65 + 0.80 * 35).rounded())))
        #expect(shadow.morningProbabilityPercent == expectedMorning)
        #expect(shadow.memoryProbabilityPercent == expectedMemory)
    }

    @Test func shadowAssessmentFallsBackWhenPredictorUnavailable() {
        let now = Date.now
        let current = Session(
            startAt: now.addingTimeInterval(-4 * 3600),
            endAt: now.addingTimeInterval(-30 * 60),
            isActive: true,
            cachedPeakBAC: 0.16,
            cachedEstimatedSoberAt: now.addingTimeInterval(3 * 3600)
        )
        current.waters = [WaterEntry(volumeMl: 200, session: current)]

        var history: [Session] = []
        for day in 1...6 {
            let start = now.addingTimeInterval(-Double(day) * 24 * 3600)
            let session = Session(
                startAt: start,
                endAt: start.addingTimeInterval(150 * 60),
                isActive: false,
                cachedPeakBAC: 0.12,
                cachedEstimatedSoberAt: start.addingTimeInterval(4 * 3600)
            )
            history.append(session)
        }

        let baseline = SessionInsightService().assess(session: current, profile: nil, at: now, history: history)
        let unavailable = SessionInsightService(shadowPredictor: StubShadowPredictor(morning: nil, memory: nil))
        let available = SessionInsightService(shadowPredictor: StubShadowPredictor(morning: 0.98, memory: 0.97))

        let fallbackShadow = unavailable.assessShadow(
            session: current,
            profile: nil,
            at: now,
            health: nil,
            history: history,
            baseline: baseline
        )
        let modelShadow = available.assessShadow(
            session: current,
            profile: nil,
            at: now,
            health: nil,
            history: history,
            baseline: baseline
        )

        #expect(fallbackShadow.note == L10n.tr("Прогноз в shadow-режиме: на основе ваших данных, отдельно от основного расчета."))
        #expect(modelShadow.note == L10n.tr("CoreML shadow-прогноз: на основе ваших данных, отдельно от основного расчета."))
        #expect(fallbackShadow.morningProbabilityPercent != modelShadow.morningProbabilityPercent)
    }

    @Test func personalTrendsDetectObservedAssociations() {
        let service = SessionInsightService()
        let now = Date.now
        var history: [Session] = []

        for index in 0..<10 {
            let start = now.addingTimeInterval(-Double(index + 1) * 24 * 3600)
            let session = Session(
                startAt: start,
                endAt: start.addingTimeInterval(2 * 3600),
                isActive: false,
                cachedPeakBAC: 0.11,
                cachedEstimatedSoberAt: start.addingTimeInterval(5 * 3600)
            )
            let isSpirits = index < 6
            session.drinks = [
                DrinkEntry(
                    createdAt: start.addingTimeInterval(20 * 60),
                    volumeMl: 80,
                    abvPercent: isSpirits ? 40 : 5,
                    title: isSpirits ? "Whiskey" : "Beer",
                    category: isSpirits ? .spirits : .beer,
                    session: session
                )
            ]
            session.waters = [WaterEntry(volumeMl: 300, session: session)]
            session.meals = [MealEntry(title: "Meal", size: .regular, session: session)]
            session.morningCheckIn = MorningCheckIn(
                wellbeingScore: isSpirits ? 2 : 4,
                symptoms: isSpirits ? [.headache] : [.none],
                sleepHours: 7,
                hadWater: true,
                session: session
            )
            history.append(session)
        }

        let summary = service.personalTrends(sessions: history, profile: nil, minHistoryCount: 8)

        switch summary.status {
        case .ready:
            #expect(true)
        case .insufficientData:
            #expect(Bool(false), "Expected ready status for trends")
        }
        #expect(!summary.findings.isEmpty)
        #expect(summary.findings.contains(where: { $0.outcome == L10n.tr("утренняя головная боль") }))
    }

    @Test func personalTrendsUseCoreMLPredictorWhenAvailable() {
        let now = Date.now
        var history: [Session] = []

        for index in 0..<10 {
            let start = now.addingTimeInterval(-Double(index + 1) * 24 * 3600)
            let session = Session(
                startAt: start,
                endAt: start.addingTimeInterval(2 * 3600),
                isActive: false,
                cachedPeakBAC: 0.13,
                cachedEstimatedSoberAt: start.addingTimeInterval(4 * 3600)
            )
            let isSpirits = index < 6
            session.drinks = [
                DrinkEntry(
                    createdAt: start.addingTimeInterval(10 * 60),
                    volumeMl: 120,
                    abvPercent: isSpirits ? 40 : 5,
                    title: isSpirits ? "Whiskey" : "Beer",
                    category: isSpirits ? .spirits : .beer,
                    session: session
                )
            ]
            session.waters = [WaterEntry(volumeMl: 200, session: session)]
            session.morningCheckIn = MorningCheckIn(
                wellbeingScore: isSpirits ? 2 : 4,
                symptoms: isSpirits ? [.headache] : [.none],
                sleepHours: 6,
                hadWater: true,
                session: session
            )
            history.append(session)
        }

        let baselineService = SessionInsightService(
            shadowPredictor: StubShadowPredictor(morning: nil, memory: nil),
            personalTrendPredictor: StubPersonalTrendPredictor(headache: nil, fatigue: nil, heavyMorning: nil)
        )
        let modelService = SessionInsightService(
            shadowPredictor: StubShadowPredictor(morning: nil, memory: nil),
            personalTrendPredictor: StubPersonalTrendPredictor(headache: 0.90, fatigue: 0.75, heavyMorning: 0.80)
        )

        let baseline = baselineService.personalTrends(sessions: history, profile: nil, minHistoryCount: 8)
        let model = modelService.personalTrends(sessions: history, profile: nil, minHistoryCount: 8)
        let modelDisabled = modelService.personalTrends(
            sessions: history,
            profile: nil,
            minHistoryCount: 8,
            useCoreML: false
        )

        #expect(baseline.note == L10n.tr("Это наблюдательные паттерны по вашим данным, а не причинно-следственный вывод."))
        #expect(model.note == L10n.tr("Это наблюдательные паттерны по вашим данным, уточненные CoreML, а не причинно-следственный вывод."))
        #expect(modelDisabled.note == L10n.tr("Это наблюдательные паттерны по вашим данным, а не причинно-следственный вывод."))
        #expect(!model.findings.isEmpty)
    }

}
