import Foundation

/// Computes robust baselines (median/IQR) on sliding windows of daily snapshots.
struct BaselineCalculator {
    /// Inclusive window of past days (including the given anchor day).
    func stats(
        for metric: HealthMetricKind,
        snapshots: [HealthDailySnapshot],
        anchorDay: Date = .now,
        windowDays: Int = 28
    ) -> BaselineStats? {
        guard windowDays > 0 else { return nil }
        let calendar = Calendar.current
        let start = calendar.date(byAdding: .day, value: -(windowDays - 1), to: calendar.startOfDay(for: anchorDay)) ?? anchorDay

        let values: [Double] = snapshots.compactMap { snapshot in
            guard snapshot.day >= start && snapshot.day <= anchorDay else { return nil }
            return value(for: metric, in: snapshot)
        }

        guard values.count >= 3 else { return nil }
        let sorted = values.sorted()
        let median = percentile(sorted, 50)
        let p25 = percentile(sorted, 25)
        let p75 = percentile(sorted, 75)
        let iqr = p75 - p25

        let trendSlope = linearTrendSlope(values: sorted)

        return BaselineStats(
            median: median,
            p25: p25,
            p75: p75,
            iqr: iqr,
            trendSlope: trendSlope,
            sampleCount: values.count
        )
    }

    private func value(for metric: HealthMetricKind, in snapshot: HealthDailySnapshot) -> Double? {
        switch metric {
        case .steps: return snapshot.steps.map(Double.init)
        case .restingHeartRate: return snapshot.restingHeartRate.map(Double.init)
        case .heartRateVariability: return snapshot.hrvSdnn
        case .sleepDuration: return snapshot.sleepMinutes
        case .sleepDeep: return snapshot.sleepDeepMinutes
        case .sleepRem: return snapshot.sleepRemMinutes
        case .sleepAwake: return snapshot.sleepAwakeMinutes
        }
    }

    private func percentile(_ sorted: [Double], _ p: Double) -> Double {
        guard !sorted.isEmpty else { return 0 }
        let rank = (p / 100.0) * Double(sorted.count - 1)
        let lower = Int(floor(rank))
        let upper = Int(ceil(rank))
        if lower == upper { return sorted[lower] }
        let fraction = rank - Double(lower)
        return sorted[lower] + fraction * (sorted[upper] - sorted[lower])
    }

    /// Simple least-squares slope (per sample index ~ per day after filtering window).
    private func linearTrendSlope(values: [Double]) -> Double {
        let n = Double(values.count)
        guard n >= 2 else { return 0 }
        let x: [Double] = (0..<values.count).map(Double.init)
        let meanX = x.reduce(0, +) / n
        let meanY = values.reduce(0, +) / n
        var num = 0.0
        var den = 0.0
        for i in 0..<values.count {
            let dx = x[i] - meanX
            num += dx * (values[i] - meanY)
            den += dx * dx
        }
        return den == 0 ? 0 : num / den
    }
}
