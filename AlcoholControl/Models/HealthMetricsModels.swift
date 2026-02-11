import Foundation
import SwiftData

enum HealthMetricKind: String, Codable, CaseIterable, Identifiable {
    case steps
    case restingHeartRate
    case heartRateVariability
    case sleepDuration
    case sleepDeep
    case sleepRem
    case sleepAwake

    var id: String { rawValue }
}

/// Daily aggregated health metrics used for recovery/baseline calculations.
@Model
final class HealthDailySnapshot {
    @Attribute(.unique) var id: UUID
    /// Start of day in the current calendar.
    var day: Date

    var steps: Int?
    var restingHeartRate: Int?
    /// SDNN in milliseconds.
    var hrvSdnn: Double?

    /// Total sleep minutes (asleep only).
    var sleepMinutes: Double?
    var sleepDeepMinutes: Double?
    var sleepRemMinutes: Double?
    var sleepAwakeMinutes: Double?
    /// Ratio of asleep time to in-bed time, 0–1.
    var sleepEfficiency: Double?

    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        day: Date,
        steps: Int? = nil,
        restingHeartRate: Int? = nil,
        hrvSdnn: Double? = nil,
        sleepMinutes: Double? = nil,
        sleepDeepMinutes: Double? = nil,
        sleepRemMinutes: Double? = nil,
        sleepAwakeMinutes: Double? = nil,
        sleepEfficiency: Double? = nil,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.day = Calendar.current.startOfDay(for: day)
        self.steps = steps
        self.restingHeartRate = restingHeartRate
        self.hrvSdnn = hrvSdnn
        self.sleepMinutes = sleepMinutes
        self.sleepDeepMinutes = sleepDeepMinutes
        self.sleepRemMinutes = sleepRemMinutes
        self.sleepAwakeMinutes = sleepAwakeMinutes
        self.sleepEfficiency = sleepEfficiency
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    func updateTimestamps() {
        updatedAt = .now
    }
}

struct BaselineStats: Sendable {
    let median: Double
    let p25: Double
    let p75: Double
    let iqr: Double
    /// Simple linear trend slope (per day) over the window.
    let trendSlope: Double
    let sampleCount: Int
}

struct HealthBaselineSet: Sendable {
    var steps: BaselineStats?
    var restingHeartRate: BaselineStats?
    var hrv: BaselineStats?
    var sleep: BaselineStats?
}
