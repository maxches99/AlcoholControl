import Foundation
import SwiftData

@Model
final class PersonalPatternRun {
    @Attribute(.unique) var id: UUID
    var day: Date
    var patternKey: String
    var trigger: String
    var outcome: String
    var supportSessions: Int
    var sampleSessions: Int
    var triggerRatePercent: Int
    var baseRatePercent: Int
    var liftPercent: Int
    var confidencePercent: Int
    var note: String
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        day: Date,
        patternKey: String,
        trigger: String,
        outcome: String,
        supportSessions: Int,
        sampleSessions: Int,
        triggerRatePercent: Int,
        baseRatePercent: Int,
        liftPercent: Int,
        confidencePercent: Int,
        note: String,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.day = Calendar.current.startOfDay(for: day)
        self.patternKey = patternKey
        self.trigger = trigger
        self.outcome = outcome
        self.supportSessions = supportSessions
        self.sampleSessions = sampleSessions
        self.triggerRatePercent = triggerRatePercent
        self.baseRatePercent = baseRatePercent
        self.liftPercent = liftPercent
        self.confidencePercent = confidencePercent
        self.note = note
        self.updatedAt = updatedAt
    }
}
