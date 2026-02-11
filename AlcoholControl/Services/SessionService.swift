import Foundation
import SwiftData

@MainActor
struct SessionService {
    private let calculator = BACCalculator()

    func activeSession(context: ModelContext) throws -> Session? {
        let descriptor = FetchDescriptor<Session>(
            predicate: #Predicate { $0.isActive == true },
            sortBy: [SortDescriptor<Session>(\.startAt, order: .reverse)]
        )
        return try context.fetch(descriptor).first
    }

    func startSession(context: ModelContext) throws -> Session {
        if let existing = try activeSession(context: context) {
            return existing
        }
        let session = Session()
        context.insert(session)
        return session
    }

    func endSession(_ session: Session, context: ModelContext, profile: UserProfile?) {
        session.endAt = .now
        session.isActive = false
        recompute(session, profile: profile)
    }

    func deleteEmptySessionIfNeeded(_ session: Session, context: ModelContext) {
        if session.drinks.isEmpty && session.waters.isEmpty && session.meals.isEmpty {
            context.delete(session)
        }
    }

    func addDrink(
        to session: Session,
        context: ModelContext,
        profile: UserProfile?,
        createdAt: Date = .now,
        volumeMl: Double,
        abvPercent: Double,
        title: String? = nil,
        category: DrinkEntry.Category = .beer
    ) {
        let drink = DrinkEntry(createdAt: createdAt, volumeMl: volumeMl, abvPercent: abvPercent, title: title, category: category)
        drink.session = session
        session.drinks.append(drink)
        recompute(session, profile: profile)
    }

    func updateDrink(
        _ drink: DrinkEntry,
        in session: Session,
        profile: UserProfile?,
        createdAt: Date,
        volumeMl: Double,
        abvPercent: Double,
        title: String?,
        category: DrinkEntry.Category
    ) {
        drink.createdAt = createdAt
        drink.volumeMl = volumeMl
        drink.abvPercent = abvPercent
        drink.title = title
        drink.category = category
        recompute(session, profile: profile)
    }

    func addWater(
        to session: Session,
        context: ModelContext,
        profile: UserProfile?,
        createdAt: Date = .now,
        volumeMl: Double? = nil
    ) {
        let water = WaterEntry(createdAt: createdAt, volumeMl: volumeMl)
        water.session = session
        session.waters.append(water)
        recompute(session, profile: profile)
    }

    func addMeal(
        to session: Session,
        context: ModelContext,
        profile: UserProfile?,
        createdAt: Date = .now,
        title: String? = nil,
        size: MealEntry.MealSize = .regular
    ) {
        let meal = MealEntry(createdAt: createdAt, title: title, size: size)
        meal.session = session
        session.meals.append(meal)
        recompute(session, profile: profile)
    }

    func delete(entry: DrinkEntry, from session: Session, context: ModelContext, profile: UserProfile?) {
        session.drinks.removeAll { $0.id == entry.id }
        context.delete(entry)
        recompute(session, profile: profile)
    }

    func delete(entry: WaterEntry, from session: Session, context: ModelContext, profile: UserProfile?) {
        session.waters.removeAll { $0.id == entry.id }
        context.delete(entry)
        recompute(session, profile: profile)
    }

    func delete(entry: MealEntry, from session: Session, context: ModelContext, profile: UserProfile?) {
        session.meals.removeAll { $0.id == entry.id }
        context.delete(entry)
        recompute(session, profile: profile)
    }

    func upsertProfile(context: ModelContext, weight: Double, unitSystem: UserProfile.UnitSystem, sex: UserProfile.BiologicalSex) throws -> UserProfile {
        if let existing = try context.fetch(FetchDescriptor<UserProfile>()).first {
            existing.weight = weight
            existing.unitSystem = unitSystem
            existing.sex = sex
            existing.updatedAt = .now
            return existing
        }
        let profile = UserProfile(weight: weight, sex: sex, unitSystem: unitSystem)
        context.insert(profile)
        return profile
    }

    func fetchOrCreateProfile(context: ModelContext) throws -> UserProfile {
        if let existing = try context.fetch(FetchDescriptor<UserProfile>()).first {
            return existing
        }
        let profile = UserProfile()
        context.insert(profile)
        return profile
    }

    func recomputeAllSessions(context: ModelContext, profile: UserProfile?) throws {
        guard let profile else { return }
        let sessions = try context.fetch(FetchDescriptor<Session>())
        for session in sessions {
            recompute(session, profile: profile)
        }
    }

    func recompute(_ session: Session, profile: UserProfile?) {
        guard let profile else { return }
        let timeline = calculator.compute(for: session, profile: profile)
        session.cachedPeakBAC = timeline.peakBAC
        session.cachedEstimatedSoberAt = timeline.estimatedSoberAt
    }
}
