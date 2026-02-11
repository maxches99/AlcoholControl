import Foundation
import HealthKit

@MainActor
final class HealthKitService {
    static let shared = HealthKitService()

    private let store = HKHealthStore()
    private let sleepType = HKObjectType.categoryType(forIdentifier: .sleepAnalysis)
    private let stepType = HKObjectType.quantityType(forIdentifier: .stepCount)
    private let restingHeartRateType = HKObjectType.quantityType(forIdentifier: .restingHeartRate)
    private let hrvType = HKObjectType.quantityType(forIdentifier: .heartRateVariabilitySDNN)
    private let stepsCachePrefix = "health.steps."
    private let restingHRCachePrefix = "health.restingHR."
    private let hrvCachePrefix = "health.hrv."
    private let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    private init() {}

    var isAvailable: Bool {
        HKHealthStore.isHealthDataAvailable() && sleepType != nil
    }

    func requestSleepAuthorization() async -> Bool {
        guard isAvailable, let sleepType else { return false }
        do {
            var readTypes: Set<HKObjectType> = [sleepType]
            if let stepType {
                readTypes.insert(stepType)
            }
            if let restingHeartRateType {
                readTypes.insert(restingHeartRateType)
            }
            if let hrvType { readTypes.insert(hrvType) }

            try await store.requestAuthorization(toShare: [], read: readTypes)
            return true
        } catch {
            return false
        }
    }

    func fetchLastNightSleepHours() async -> Double? {
        guard isAvailable, let sleepType else { return nil }

        let calendar = Calendar.current
        let now = Date()
        let today = calendar.startOfDay(for: now)
        let start = calendar.date(byAdding: .hour, value: -18, to: today) ?? today.addingTimeInterval(-18 * 3600)
        let predicate = HKQuery.predicateForSamples(withStart: start, end: now, options: .strictStartDate)
        let sort = [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)]

        let total: TimeInterval = await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: sleepType,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: sort
            ) { _, samples, _ in
                let categorySamples = (samples as? [HKCategorySample]) ?? []
                let value = categorySamples.reduce(0.0) { partial, sample in
                    guard sample.value != HKCategoryValueSleepAnalysis.awake.rawValue else { return partial }
                    return partial + sample.endDate.timeIntervalSince(sample.startDate)
                }
                continuation.resume(returning: value)
            }
            store.execute(query)
        }

        guard total > 0 else { return nil }
        return (total / 3600.0).rounded(toPlaces: 1)
    }

    func fetchTodayStepCount() async -> Int? {
        await fetchStepCount(on: .now)
    }

    func fetchStepCount(on day: Date) async -> Int? {
        guard isAvailable, let stepType else { return nil }
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: day)
        let end = calendar.date(byAdding: .day, value: 1, to: start) ?? start.addingTimeInterval(24 * 3600)
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)

        let count: Double = await withCheckedContinuation { continuation in
            let query = HKStatisticsQuery(
                quantityType: stepType,
                quantitySamplePredicate: predicate,
                options: .cumulativeSum
            ) { _, result, _ in
                let value = result?.sumQuantity()?.doubleValue(for: HKUnit.count()) ?? 0
                continuation.resume(returning: value)
            }
            store.execute(query)
        }

        let steps = Int(count.rounded())
        saveStepCount(steps, on: day)
        return steps
    }

    func fetchLatestRestingHeartRate() async -> Int? {
        await fetchRestingHeartRate(on: .now)
    }

    func fetchRestingHeartRate(on day: Date) async -> Int? {
        guard isAvailable, let restingHeartRateType else { return nil }
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: day)
        let end = calendar.date(byAdding: .day, value: 1, to: start) ?? start.addingTimeInterval(24 * 3600)
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
        let sort = [NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)]

        let bpm: Double = await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: restingHeartRateType,
                predicate: predicate,
                limit: 1,
                sortDescriptors: sort
            ) { _, samples, _ in
                let quantity = (samples as? [HKQuantitySample])?.first?.quantity
                let unit = HKUnit.count().unitDivided(by: .minute())
                let value = quantity?.doubleValue(for: unit) ?? 0
                continuation.resume(returning: value)
            }
            store.execute(query)
        }

        guard bpm > 0 else { return nil }
        let resting = Int(bpm.rounded())
        saveRestingHeartRate(resting, on: day)
        return resting
    }

    func cachedRestingHeartRate(on day: Date) -> Int? {
        let key = restingHRCacheKey(for: day)
        guard UserDefaults.standard.object(forKey: key) != nil else { return nil }
        return UserDefaults.standard.integer(forKey: key)
    }

    func cachedHrvSdnn(on day: Date) -> Double? {
        let key = hrvCacheKey(for: day)
        guard UserDefaults.standard.object(forKey: key) != nil else { return nil }
        return UserDefaults.standard.double(forKey: key)
    }

    func cachedStepCount(on day: Date) -> Int? {
        let key = stepsCacheKey(for: day)
        guard UserDefaults.standard.object(forKey: key) != nil else { return nil }
        return UserDefaults.standard.integer(forKey: key)
    }

    func syncRecentStepCounts(days: Int = 14) async -> Int {
        guard isAvailable else { return 0 }
        var syncedDays = 0
        let calendar = Calendar.current

        for offset in 0..<max(1, days) {
            guard let day = calendar.date(byAdding: .day, value: -offset, to: .now) else { continue }
            if await fetchStepCount(on: day) != nil {
                syncedDays += 1
            }
        }

        return syncedDays
    }

    func syncRecentRestingHeartRates(days: Int = 14) async -> Int {
        guard isAvailable else { return 0 }
        var syncedDays = 0
        let calendar = Calendar.current

        for offset in 0..<max(1, days) {
            guard let day = calendar.date(byAdding: .day, value: -offset, to: .now) else { continue }
            if await fetchRestingHeartRate(on: day) != nil {
                syncedDays += 1
            }
        }

        return syncedDays
    }

    private func saveStepCount(_ steps: Int, on day: Date) {
        UserDefaults.standard.set(steps, forKey: stepsCacheKey(for: day))
    }

    private func saveRestingHeartRate(_ bpm: Int, on day: Date) {
        UserDefaults.standard.set(bpm, forKey: restingHRCacheKey(for: day))
    }

    private func saveHrvSdnn(_ value: Double, on day: Date) {
        UserDefaults.standard.set(value, forKey: hrvCacheKey(for: day))
    }

    func fetchHrvSdnn(on day: Date) async -> Double? {
        guard isAvailable, let hrvType else { return nil }
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: day)
        let end = calendar.date(byAdding: .day, value: 1, to: start) ?? start.addingTimeInterval(24 * 3600)
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
        let sort = [NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)]

        let sdnn: Double = await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: hrvType,
                predicate: predicate,
                limit: 1,
                sortDescriptors: sort
            ) { _, samples, _ in
                let quantity = (samples as? [HKQuantitySample])?.first?.quantity
                let value = quantity?.doubleValue(for: HKUnit.secondUnit(with: .milli)) ?? 0
                continuation.resume(returning: value)
            }
            store.execute(query)
        }

        guard sdnn > 0 else { return nil }
        saveHrvSdnn(sdnn, on: day)
        return sdnn
    }

    func fetchSleepSegments(for day: Date) async -> [SleepSegment]? {
        guard isAvailable, let sleepType else { return nil }

        let calendar = Calendar.current
        let start = calendar.startOfDay(for: day)
        let end = calendar.date(byAdding: .day, value: 1, to: start) ?? start.addingTimeInterval(24 * 3600)
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
        let sort = [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)]

        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: sleepType,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: sort
            ) { _, samples, _ in
                let categorySamples = (samples as? [HKCategorySample]) ?? []
                let segments = categorySamples.map { sample in
                    SleepSegment(
                        start: sample.startDate,
                        end: sample.endDate,
                        stage: SleepStage(rawValue: sample.value) ?? .awake
                    )
                }
                continuation.resume(returning: segments)
            }
            store.execute(query)
        }
    }

    private func stepsCacheKey(for day: Date) -> String {
        "\(stepsCachePrefix)\(dayFormatter.string(from: day))"
    }

    private func restingHRCacheKey(for day: Date) -> String {
        "\(restingHRCachePrefix)\(dayFormatter.string(from: day))"
    }

    private func hrvCacheKey(for day: Date) -> String {
        "\(hrvCachePrefix)\(dayFormatter.string(from: day))"
    }
}

struct SleepSegment {
    let start: Date
    let end: Date
    let stage: SleepStage
    var duration: Double { end.timeIntervalSince(start) }
}

enum SleepStage: Int {
    /// In-bed or unspecified asleep map to the same bucket for totals.
    case inBed = 0
    case asleepUnspecified = 1
    case awake = 2
    case asleepCore = 3
    case asleepDeep = 4
    case asleepRem = 5
}

private extension Double {
    func rounded(toPlaces places: Int) -> Double {
        let scale = pow(10.0, Double(places))
        return (self * scale).rounded() / scale
    }
}
