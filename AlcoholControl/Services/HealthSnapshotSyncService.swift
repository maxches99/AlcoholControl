import Foundation
import SwiftData

@MainActor
final class HealthSnapshotSyncService {
    static let shared = HealthSnapshotSyncService()

    private let builder = HealthSnapshotBuilder()

    /// Sync recent days into storage. Returns count of upserts.
    func syncRecentDays(
        days: Int = 28,
        modelContext: ModelContext
    ) async -> Int {
        let calendar = Calendar.current
        let now = calendar.startOfDay(for: .now)
        var upserts = 0

        for offset in 0..<max(1, days) {
            guard let day = calendar.date(byAdding: .day, value: -offset, to: now) else { continue }
            guard let snapshot = await builder.makeSnapshot(for: day) else { continue }

            if let existing = try? modelContext.fetch(HealthDailySnapshot.fetchDescriptor(for: day)).first {
                existing.steps = snapshot.steps ?? existing.steps
                existing.restingHeartRate = snapshot.restingHeartRate ?? existing.restingHeartRate
                existing.hrvSdnn = snapshot.hrvSdnn ?? existing.hrvSdnn
                existing.sleepMinutes = snapshot.sleepMinutes ?? existing.sleepMinutes
                existing.sleepDeepMinutes = snapshot.sleepDeepMinutes ?? existing.sleepDeepMinutes
                existing.sleepRemMinutes = snapshot.sleepRemMinutes ?? existing.sleepRemMinutes
                existing.sleepAwakeMinutes = snapshot.sleepAwakeMinutes ?? existing.sleepAwakeMinutes
                existing.sleepEfficiency = snapshot.sleepEfficiency ?? existing.sleepEfficiency
                existing.updateTimestamps()
            } else {
                modelContext.insert(snapshot)
            }
            upserts += 1
        }

        try? modelContext.save()
        return upserts
    }
}

extension HealthDailySnapshot {
    static func fetchDescriptor(for day: Date) -> FetchDescriptor<HealthDailySnapshot> {
        let calendar = Calendar.current
        let dayStart = calendar.startOfDay(for: day)
        let nextDay = calendar.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart.addingTimeInterval(24 * 3600)
        let predicate = #Predicate<HealthDailySnapshot> { snapshot in
            snapshot.day >= dayStart && snapshot.day < nextDay
        }
        return FetchDescriptor(predicate: predicate)
    }
}
