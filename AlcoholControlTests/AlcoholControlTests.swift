//
//  AlcoholControlTests.swift
//  AlcoholControlTests
//
//  Created by Maxim Chesnikov on 11.02.2026.
//

import Foundation
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

}
