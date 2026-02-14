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

}
