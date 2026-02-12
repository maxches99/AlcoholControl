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

}
