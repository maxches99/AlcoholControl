import Foundation
import HealthKit

/// Bridges HealthKit aggregates into our daily snapshot model.
@MainActor
final class HealthSnapshotBuilder {
    private let healthService = HealthKitService.shared

    /// Fetch and upsert a snapshot for the given day.
    func makeSnapshot(for day: Date) async -> HealthDailySnapshot? {
        let calendar = Calendar.current
        let dayStart = calendar.startOfDay(for: day)

        async let steps = healthService.fetchStepCount(on: dayStart)
        async let resting = healthService.fetchRestingHeartRate(on: dayStart)
        async let hrv = healthService.fetchHrvSdnn(on: dayStart)
        async let sleep = healthService.fetchSleepSegments(for: dayStart)

        let (stepsValue, restingValue, hrvValue, sleepSegments) = await (steps, resting, hrv, sleep)

        let sleepSummary = sleepSegments.map { summarizeSleep($0) }

        return HealthDailySnapshot(
            day: dayStart,
            steps: stepsValue,
            restingHeartRate: restingValue,
            hrvSdnn: hrvValue,
            sleepMinutes: sleepSummary?.totalMinutes,
            sleepDeepMinutes: sleepSummary?.deepMinutes,
            sleepRemMinutes: sleepSummary?.remMinutes,
            sleepAwakeMinutes: sleepSummary?.awakeMinutes,
            sleepEfficiency: sleepSummary?.efficiency
        )
    }

    private func summarizeSleep(_ segments: [SleepSegment]) -> SleepSummary {
        var total = segments.reduce(into: SleepSummary()) { summary, segment in
            let minutes = segment.duration / 60.0
            switch segment.stage {
            case .asleepDeep: summary.deepMinutes += minutes; summary.totalMinutes += minutes
            case .asleepRem: summary.remMinutes += minutes; summary.totalMinutes += minutes
            case .asleepCore: summary.coreMinutes += minutes; summary.totalMinutes += minutes
            case .asleepUnspecified, .inBed: summary.totalMinutes += minutes
            case .awake: summary.awakeMinutes += minutes
            }
        }
        if total.totalMinutes > 0 {
            let inBed = total.totalMinutes + total.awakeMinutes
            total.efficiency = total.totalMinutes / max(1, inBed)
        }
        return total
    }
}

struct SleepSummary {
    var totalMinutes: Double = 0
    var deepMinutes: Double = 0
    var remMinutes: Double = 0
    var coreMinutes: Double = 0
    var awakeMinutes: Double = 0
    var efficiency: Double? = nil
}
