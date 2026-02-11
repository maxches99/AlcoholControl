import Foundation

#if canImport(ActivityKit)
import ActivityKit

struct EveningSessionAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var currentBAC: Double
        var targetSoberAt: Date?
        var updatedAt: Date
    }

    var sessionID: String
}
#endif

enum LiveActivityActionResult {
    case started
    case updated
    case ended
    case unavailable(String)
    case failed(String)

    var userMessage: String {
        switch self {
        case .started:
            return L10n.tr("Live Activity запущена")
        case .updated:
            return L10n.tr("Live Activity обновлена")
        case .ended:
            return L10n.tr("Live Activity завершена")
        case .unavailable(let reason):
            return reason
        case .failed(let reason):
            return L10n.format("Live Activity error: %@", reason)
        }
    }
}

@MainActor
final class LiveSessionActivityService {
    static let shared = LiveSessionActivityService()

    private init() {}

    var isAvailable: Bool {
        #if canImport(ActivityKit)
        guard #available(iOS 16.2, *) else { return false }
        return ActivityAuthorizationInfo().areActivitiesEnabled
        #else
        return false
        #endif
    }

    func upsert(sessionID: UUID, currentBAC: Double, soberAt: Date?) async -> LiveActivityActionResult {
        #if canImport(ActivityKit)
        guard #available(iOS 16.2, *) else {
            return .unavailable(L10n.tr("Live Activity доступна на iOS 16.2+"))
        }
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            return .unavailable(L10n.tr("Live Activity отключена в системных настройках"))
        }

        let identifier = sessionID.uuidString
        let state = EveningSessionAttributes.ContentState(
            currentBAC: max(0, currentBAC),
            targetSoberAt: soberAt,
            updatedAt: .now
        )

        if let existing = Activity<EveningSessionAttributes>.activities.first(where: { $0.attributes.sessionID == identifier }) {
            await existing.update(ActivityContent(state: state, staleDate: nil))
            return .updated
        }

        let attributes = EveningSessionAttributes(sessionID: identifier)
        do {
            _ = try Activity<EveningSessionAttributes>.request(
                attributes: attributes,
                content: ActivityContent(state: state, staleDate: nil),
                pushType: nil
            )
            return .started
        } catch {
            return .failed(error.localizedDescription)
        }
        #else
        return .unavailable(L10n.tr("Live Activity недоступна на этом устройстве"))
        #endif
    }

    func end(sessionID: UUID) async -> LiveActivityActionResult {
        #if canImport(ActivityKit)
        guard #available(iOS 16.2, *) else {
            return .unavailable(L10n.tr("Live Activity доступна на iOS 16.2+"))
        }
        let identifier = sessionID.uuidString
        var endedAny = false
        for activity in Activity<EveningSessionAttributes>.activities where activity.attributes.sessionID == identifier {
            await activity.end(nil, dismissalPolicy: .immediate)
            endedAny = true
        }
        return endedAny ? .ended : .updated
        #else
        return .unavailable(L10n.tr("Live Activity недоступна на этом устройстве"))
        #endif
    }

    func endAll() async {
        #if canImport(ActivityKit)
        guard #available(iOS 16.2, *) else { return }
        for activity in Activity<EveningSessionAttributes>.activities {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
        #endif
    }
}
