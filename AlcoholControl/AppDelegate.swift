import Foundation
import UserNotifications
import UIKit

final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    @MainActor var appState: AppState?

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        defer { completionHandler() }

        let identifier = response.notification.request.identifier
        guard identifier == NotificationService.Identifier.morningCheckIn else { return }

        let rawID = response.notification.request.content.userInfo[NotificationService.Payload.sessionID] as? String
        let sessionID = rawID.flatMap(UUID.init(uuidString:))
        Task { @MainActor in
            appState?.openMorningCheckIn(sessionID: sessionID)
        }
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }

    func application(_ app: UIApplication, open url: URL, options: [UIApplication.OpenURLOptionsKey : Any] = [:]) -> Bool {
        guard url.scheme == "alcoholcontrol" else { return false }
        if url.host == "quick" {
            let action = url.lastPathComponent
            switch action {
            case "water":
                WidgetSnapshotStore.enqueuePendingWater(volumeMl: 250)
            case "meal":
                WidgetSnapshotStore.enqueuePendingMeal(size: .snack)
            case "pause":
                WidgetSnapshotStore.enqueuePauseRequest(minutes: 25)
            default:
                break
            }
            Task { @MainActor in
                appState?.openMorningCheckIn(sessionID: nil)
            }
            return true
        }
        return false
    }
}
