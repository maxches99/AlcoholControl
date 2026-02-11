import Foundation
import Combine

enum AppTab: Hashable {
    case today
    case history
    case analytics
    case settings
}

@MainActor
final class AppState: ObservableObject {
    @Published var selectedTab: AppTab = .today
    @Published var pendingMorningCheckInSessionID: UUID?
    @Published var pendingOpenLatestMorningCheckIn = false
    @Published var pendingForecastSessionID: UUID?

    func openToday() {
        selectedTab = .today
        pendingMorningCheckInSessionID = nil
        pendingOpenLatestMorningCheckIn = false
        pendingForecastSessionID = nil
    }

    func openMorningCheckIn(sessionID: UUID?) {
        openToday()
        if let sessionID {
            pendingMorningCheckInSessionID = sessionID
        } else {
            pendingOpenLatestMorningCheckIn = true
        }
    }

    func openForecast(sessionID: UUID) {
        openToday()
        pendingForecastSessionID = sessionID
    }
}
