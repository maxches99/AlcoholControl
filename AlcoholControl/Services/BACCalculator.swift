import Foundation

struct BACTimeline {
    let currentBAC: Double
    let peakBAC: Double
    let estimatedSoberAt: Date?
}

struct BACCalculator {
    private let eliminationRatePerHour: Double = 0.015 // BAC units per hour
    private let alcoholDensity: Double = 0.789 // g/ml

    func compute(for session: Session, profile: UserProfile, at date: Date = .now) -> BACTimeline {
        let weightGrams = weightInGrams(profile)
        guard weightGrams > 0 else {
            return BACTimeline(currentBAC: 0, peakBAC: 0, estimatedSoberAt: date)
        }

        let drinks = session.drinks.sorted { $0.createdAt < $1.createdAt }
        let distribution = profile.sex.distributionRatio
        var current: Double = 0
        for drink in drinks {
            current += adjustedContribution(for: drink, at: date, weightGrams: weightGrams, distribution: distribution)
        }

        var peak: Double = 0
        for drink in drinks {
            let bacAtDrink = currentBAC(at: drink.createdAt, drinks: drinks, weightGrams: weightGrams, distribution: distribution)
            peak = max(peak, bacAtDrink)
        }

        let estimatedSoberAt: Date?
        if current <= 0.0001 {
            current = 0
            estimatedSoberAt = date
        } else {
            let hoursToSober = current / eliminationRatePerHour
            estimatedSoberAt = date.addingTimeInterval(hoursToSober * 3600)
        }

        return BACTimeline(currentBAC: current, peakBAC: peak, estimatedSoberAt: estimatedSoberAt)
    }

    private func weightInGrams(_ profile: UserProfile) -> Double {
        switch profile.unitSystem {
        case .metric:
            return profile.weight * 1000
        case .imperial:
            // pounds to grams
            return profile.weight * 453.592
        }
    }

    private func bacContribution(for drink: DrinkEntry, weightGrams: Double, distribution: Double) -> Double {
        let alcoholMl = drink.volumeMl * (drink.abvPercent / 100)
        let alcoholGrams = alcoholMl * alcoholDensity
        let bac = (alcoholGrams / (weightGrams * distribution)) * 100
        return bac
    }

    private func currentBAC(at date: Date, drinks: [DrinkEntry], weightGrams: Double, distribution: Double) -> Double {
        var total: Double = 0
        for drink in drinks {
            total += adjustedContribution(for: drink, at: date, weightGrams: weightGrams, distribution: distribution)
        }
        return total
    }

    private func adjustedContribution(for drink: DrinkEntry, at date: Date, weightGrams: Double, distribution: Double) -> Double {
        let contribution = bacContribution(for: drink, weightGrams: weightGrams, distribution: distribution)
        let hours = max(0, date.timeIntervalSince(drink.createdAt) / 3600)
        return max(0, contribution - eliminationRatePerHour * hours)
    }
}
