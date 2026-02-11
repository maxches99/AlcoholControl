import Foundation
import SwiftData

/// Logs which risk model variant был применён и с какой уверенностью.
@Model
final class RiskModelRun {
    @Attribute(.unique) var id: UUID
    /// Start of day for which прогноз/оценка была сделана.
    var day: Date
    var variant: String
    var confidencePercent: Int
    var morningProbability: Int
    var memoryProbability: Int
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        day: Date,
        variant: String,
        confidencePercent: Int,
        morningProbability: Int,
        memoryProbability: Int,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.day = Calendar.current.startOfDay(for: day)
        self.variant = variant
        self.confidencePercent = confidencePercent
        self.morningProbability = morningProbability
        self.memoryProbability = memoryProbability
        self.updatedAt = updatedAt
    }
}
