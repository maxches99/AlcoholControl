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

    func openMorningCheckIn(sessionID: UUID?) {
        selectedTab = .today
        if let sessionID {
            pendingMorningCheckInSessionID = sessionID
            pendingOpenLatestMorningCheckIn = false
        } else {
            pendingMorningCheckInSessionID = nil
            pendingOpenLatestMorningCheckIn = true
        }
    }

    func openForecast(sessionID: UUID) {
        selectedTab = .today
        pendingForecastSessionID = sessionID
    }
}
