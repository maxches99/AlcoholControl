import Foundation

enum ExportKind: String {
    case csv = "csv"
    case json = "json"
}

@MainActor
struct DataExportService {
    func exportCSV(sessions: [Session]) throws -> URL {
        let fileName = "alcohol-control-\(timestamp()).csv"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)

        var lines: [String] = []
        lines.append("session_id,start_at,end_at,is_active,peak_bac,estimated_sober_at,drink_count,water_count,meal_count,wellbeing_score,sleep_hours,had_water")

        for session in sessions.sorted(by: { $0.startAt > $1.startAt }) {
            let checkIn = session.morningCheckIn
            lines.append([
                session.id.uuidString,
                iso(session.startAt),
                isoOptional(session.endAt),
                session.isActive.description,
                String(format: "%.3f", session.cachedPeakBAC),
                isoOptional(session.cachedEstimatedSoberAt),
                "\(session.drinks.count)",
                "\(session.waters.count)",
                "\(session.meals.count)",
                checkIn.map { "\($0.wellbeingScore)" } ?? "",
                checkIn?.sleepHours.map { String(format: "%.1f", $0) } ?? "",
                checkIn?.hadWater.map { $0.description } ?? ""
            ].joined(separator: ","))
        }

        try lines.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    func exportJSON(sessions: [Session], profile: UserProfile?) throws -> URL {
        let fileName = "alcohol-control-backup-\(timestamp()).json"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)

        let payload = BackupPayload(
            exportedAt: .now,
            profile: profile.map { BackupProfile(profile: $0) },
            sessions: sessions.sorted(by: { $0.startAt > $1.startAt }).map(BackupSession.init)
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .withoutEscapingSlashes, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(payload)
        try data.write(to: url, options: .atomic)
        return url
    }

    private func iso(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        return formatter.string(from: date)
    }

    private func isoOptional(_ date: Date?) -> String {
        guard let date else { return "" }
        return iso(date)
    }

    private func timestamp() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter.string(from: .now)
    }
}

private struct BackupPayload: Codable {
    let exportedAt: Date
    let profile: BackupProfile?
    let sessions: [BackupSession]
}

private struct BackupProfile: Codable {
    let weight: Double
    let sex: String
    let unitSystem: String
    let notificationsEnabled: Bool
    let waterReminderIntervalMinutes: Int
    let quietHoursEnabled: Bool

    @MainActor
    init(profile: UserProfile) {
        weight = profile.weight
        sex = profile.sex.rawValue
        unitSystem = profile.unitSystem.rawValue
        notificationsEnabled = profile.notificationsEnabled
        waterReminderIntervalMinutes = profile.waterReminderIntervalMinutes
        quietHoursEnabled = profile.quietHoursEnabled
    }
}

private struct BackupSession: Codable {
    let id: UUID
    let startAt: Date
    let endAt: Date?
    let isActive: Bool
    let peakBAC: Double
    let estimatedSoberAt: Date?
    let drinks: [BackupDrink]
    let waters: [BackupWater]
    let meals: [BackupMeal]
    let morningCheckIn: BackupCheckIn?

    @MainActor
    init(session: Session) {
        id = session.id
        startAt = session.startAt
        endAt = session.endAt
        isActive = session.isActive
        peakBAC = session.cachedPeakBAC
        estimatedSoberAt = session.cachedEstimatedSoberAt
        drinks = session.drinks.map(BackupDrink.init)
        waters = session.waters.map(BackupWater.init)
        meals = session.meals.map(BackupMeal.init)
        morningCheckIn = session.morningCheckIn.map(BackupCheckIn.init)
    }
}

private struct BackupDrink: Codable {
    let createdAt: Date
    let volumeMl: Double
    let abvPercent: Double
    let title: String?
    let category: String

    @MainActor
    init(drink: DrinkEntry) {
        createdAt = drink.createdAt
        volumeMl = drink.volumeMl
        abvPercent = drink.abvPercent
        title = drink.title
        category = drink.category.rawValue
    }
}

private struct BackupWater: Codable {
    let createdAt: Date
    let volumeMl: Double?

    @MainActor
    init(water: WaterEntry) {
        createdAt = water.createdAt
        volumeMl = water.volumeMl
    }
}

private struct BackupMeal: Codable {
    let createdAt: Date
    let title: String?
    let size: String

    @MainActor
    init(meal: MealEntry) {
        createdAt = meal.createdAt
        title = meal.title
        size = meal.size.rawValue
    }
}

private struct BackupCheckIn: Codable {
    let createdAt: Date
    let wellbeingScore: Int
    let symptoms: [String]
    let sleepHours: Double?
    let hadWater: Bool?

    @MainActor
    init(checkIn: MorningCheckIn) {
        createdAt = checkIn.createdAt
        wellbeingScore = checkIn.wellbeingScore
        symptoms = checkIn.symptoms.map(\.rawValue)
        sleepHours = checkIn.sleepHours
        hadWater = checkIn.hadWater
    }
}
