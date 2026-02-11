import Foundation
import SwiftData

@Model
final class UserProfile {
    enum BiologicalSex: String, Codable, CaseIterable, Identifiable {
        case male, female, unspecified
        var id: String { rawValue }
        var distributionRatio: Double {
            switch self {
            case .male: return 0.68
            case .female: return 0.55
            case .unspecified: return 0.615
            }
        }
        var label: String {
            switch self {
            case .male: return L10n.tr("Мужской")
            case .female: return L10n.tr("Женский")
            case .unspecified: return L10n.tr("Не указан")
            }
        }
    }

    enum UnitSystem: String, Codable, CaseIterable, Identifiable {
        case metric
        case imperial
        var id: String { rawValue }
        var weightPlaceholder: String { self == .metric ? "кг" : "lbs" }
    }

    @Attribute(.unique) var id: UUID
    var weight: Double
    var sex: BiologicalSex
    var unitSystem: UnitSystem
    var notificationsEnabled: Bool
    var waterReminderIntervalMinutes: Int
    var quietHoursEnabled: Bool
    var quietHoursStartMinutes: Int?
    var quietHoursEndMinutes: Int?
    var hideBACInSharing: Bool
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        weight: Double = 70,
        sex: BiologicalSex = .unspecified,
        unitSystem: UnitSystem = .metric,
        notificationsEnabled: Bool = false,
        waterReminderIntervalMinutes: Int = 45,
        quietHoursEnabled: Bool = false,
        quietHoursStartMinutes: Int? = nil,
        quietHoursEndMinutes: Int? = nil,
        hideBACInSharing: Bool = true,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.weight = weight
        self.sex = sex
        self.unitSystem = unitSystem
        self.notificationsEnabled = notificationsEnabled
        self.waterReminderIntervalMinutes = waterReminderIntervalMinutes
        self.quietHoursEnabled = quietHoursEnabled
        self.quietHoursStartMinutes = quietHoursStartMinutes
        self.quietHoursEndMinutes = quietHoursEndMinutes
        self.hideBACInSharing = hideBACInSharing
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

@Model
final class Session {
    @Attribute(.unique) var id: UUID
    var startAt: Date
    var endAt: Date?
    var isActive: Bool
    var cachedPeakBAC: Double
    var cachedEstimatedSoberAt: Date?

    var drinks: [DrinkEntry]

    var waters: [WaterEntry]
    var meals: [MealEntry]

    var morningCheckIn: MorningCheckIn?

    init(
        id: UUID = UUID(),
        startAt: Date = .now,
        endAt: Date? = nil,
        isActive: Bool = true,
        cachedPeakBAC: Double = 0,
        cachedEstimatedSoberAt: Date? = nil,
        drinks: [DrinkEntry] = [],
        waters: [WaterEntry] = [],
        meals: [MealEntry] = [],
        morningCheckIn: MorningCheckIn? = nil
    ) {
        self.id = id
        self.startAt = startAt
        self.endAt = endAt
        self.isActive = isActive
        self.cachedPeakBAC = cachedPeakBAC
        self.cachedEstimatedSoberAt = cachedEstimatedSoberAt
        self.drinks = drinks
        self.waters = waters
        self.meals = meals
        self.morningCheckIn = morningCheckIn
    }
}

@Model
final class DrinkEntry {
    enum Category: String, Codable, CaseIterable, Identifiable {
        case beer
        case wine
        case spirits
        case cocktail
        case cider
        case seltzer
        case liqueur
        case other
        var id: String { rawValue }
        var label: String {
            switch self {
            case .beer: return L10n.tr("Пиво")
            case .wine: return L10n.tr("Вино")
            case .spirits: return L10n.tr("Крепкий")
            case .cocktail: return L10n.tr("Коктейль")
            case .cider: return L10n.tr("Сидр")
            case .seltzer: return L10n.tr("Сельтцер")
            case .liqueur: return L10n.tr("Ликер")
            case .other: return L10n.tr("Другое")
            }
        }
    }

    @Attribute(.unique) var id: UUID
    var createdAt: Date
    var volumeMl: Double
    var abvPercent: Double
    var title: String?
    var category: Category

    var session: Session?

    init(
        id: UUID = UUID(),
        createdAt: Date = .now,
        volumeMl: Double,
        abvPercent: Double,
        title: String? = nil,
        category: Category = .beer,
        session: Session? = nil
    ) {
        self.id = id
        self.createdAt = createdAt
        self.volumeMl = volumeMl
        self.abvPercent = abvPercent
        self.title = title
        self.category = category
        self.session = session
    }
}

@Model
final class WaterEntry {
    @Attribute(.unique) var id: UUID
    var createdAt: Date
    var volumeMl: Double?

    var session: Session?

    init(
        id: UUID = UUID(),
        createdAt: Date = .now,
        volumeMl: Double? = nil,
        session: Session? = nil
    ) {
        self.id = id
        self.createdAt = createdAt
        self.volumeMl = volumeMl
        self.session = session
    }
}

@Model
final class MealEntry {
    enum MealSize: String, Codable, CaseIterable, Identifiable {
        case snack
        case regular
        case heavy

        var id: String { rawValue }

        var label: String {
            switch self {
            case .snack: return L10n.tr("Перекус")
            case .regular: return L10n.tr("Обычный прием пищи")
            case .heavy: return L10n.tr("Плотный прием пищи")
            }
        }

        var mitigationWeight: Double {
            switch self {
            case .snack: return 0.5
            case .regular: return 1.0
            case .heavy: return 1.5
            }
        }
    }

    @Attribute(.unique) var id: UUID
    var createdAt: Date
    var title: String?
    var size: MealSize
    var session: Session?

    init(
        id: UUID = UUID(),
        createdAt: Date = .now,
        title: String? = nil,
        size: MealSize = .regular,
        session: Session? = nil
    ) {
        self.id = id
        self.createdAt = createdAt
        self.title = title
        self.size = size
        self.session = session
    }
}

@Model
final class MorningCheckIn {
    enum Symptom: String, Codable, CaseIterable, Identifiable {
        case headache, nausea, fatigue, thirst, anxiety, none
        var id: String { rawValue }
        var label: String {
            switch self {
            case .headache: return L10n.tr("Головная боль")
            case .nausea: return L10n.tr("Тошнота")
            case .fatigue: return L10n.tr("Усталость")
            case .thirst: return L10n.tr("Жажда")
            case .anxiety: return L10n.tr("Тревожность")
            case .none: return L10n.tr("Ничего")
            }
        }
    }

    @Attribute(.unique) var id: UUID
    var createdAt: Date
    var wellbeingScore: Int
    var symptoms: [Symptom]
    var sleepHours: Double?
    var hadWater: Bool?

    var session: Session?

    init(
        id: UUID = UUID(),
        createdAt: Date = .now,
        wellbeingScore: Int,
        symptoms: [Symptom] = [],
        sleepHours: Double? = nil,
        hadWater: Bool? = nil,
        session: Session? = nil
    ) {
        self.id = id
        self.createdAt = createdAt
        self.wellbeingScore = wellbeingScore
        self.symptoms = symptoms
        self.sleepHours = sleepHours
        self.hadWater = hadWater
        self.session = session
    }
}
