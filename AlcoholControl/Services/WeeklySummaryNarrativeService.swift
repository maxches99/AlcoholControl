import Foundation

struct WeeklySummaryNarrativeInput: Sendable {
    let heavyMorningCount: Int
    let highMemoryRiskCount: Int
    let hydrationHitRatePercent: Int
    let processQualityScore: Int
    let recoveryLoadScore: Int
    let weeklyFocusText: String
}

struct WeeklySummaryNarrativeService {
    func supportsFoundationModels() -> Bool {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            return true
        }
        #endif
        return false
    }

    func fallbackSummary(for input: WeeklySummaryNarrativeInput) -> String {
        L10n.format(
            "Weekly summary: heavy mornings %d, high memory-risk %d, hydration %d%%, process quality %d/100, recovery load %d/100.",
            input.heavyMorningCount,
            input.highMemoryRiskCount,
            input.hydrationHitRatePercent,
            input.processQualityScore,
            input.recoveryLoadScore
        )
    }

    func makeSummary(for input: WeeklySummaryNarrativeInput) async -> String {
        let fallback = fallbackSummary(for: input)
        guard supportsFoundationModels() else { return fallback }
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            if let generated = await FoundationModelWeeklySummaryGenerator.generate(for: input) {
                return generated
            }
        }
        #endif
        return fallback
    }
}

#if canImport(FoundationModels)
import FoundationModels

@available(iOS 26.0, *)
private enum FoundationModelWeeklySummaryGenerator {
    static func generate(for input: WeeklySummaryNarrativeInput) async -> String? {
        let model = SystemLanguageModel.default
        guard model.isAvailable else { return nil }

        let session = LanguageModelSession(model: model) {
            """
            You write short, supportive harm-reduction summaries for weekly alcohol-related check-ins.
            Keep it to 2-3 short sentences, practical and non-judgmental.
            Do not provide medical diagnosis, treatment advice, legal advice, or driving instructions.
            Use only provided metrics. Do not invent numbers.
            """
        }

        let prompt = """
        Reply in \(languageHint()).
        Last 7 days metrics:
        - Heavy mornings: \(input.heavyMorningCount)
        - High memory-risk sessions: \(input.highMemoryRiskCount)
        - Hydration hit rate: \(input.hydrationHitRatePercent)%
        - Process quality: \(input.processQualityScore)/100
        - Recovery load: \(input.recoveryLoadScore)/100
        Weekly focus: \(input.weeklyFocusText)
        """

        do {
            let options = GenerationOptions(
                temperature: 0.25,
                maximumResponseTokens: 120
            )
            let response = try await session.respond(to: prompt, options: options)
            let text = response.content.trimmingCharacters(in: .whitespacesAndNewlines)
            return text.isEmpty ? nil : text
        } catch {
            return nil
        }
    }

    private static func languageHint() -> String {
        let raw = UserDefaults.standard.string(forKey: "selectedAppLanguage") ?? AppLanguage.system.rawValue
        let selected = AppLanguage(rawValue: raw) ?? .system
        switch selected {
        case .english:
            return "English"
        case .spanish:
            return "Spanish"
        case .chinese:
            return "Simplified Chinese"
        case .russian:
            return "Russian"
        case .system:
            let languageCode = Locale.autoupdatingCurrent.language.languageCode?.identifier ?? "en"
            switch languageCode {
            case "es":
                return "Spanish"
            case "zh", "zh-Hans":
                return "Simplified Chinese"
            case "ru":
                return "Russian"
            default:
                return "English"
            }
        }
    }
}
#endif
