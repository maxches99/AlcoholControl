import Foundation
import SwiftUI

enum AppLanguage: String, CaseIterable, Identifiable {
    case system
    case english = "en"
    case spanish = "es"
    case chinese = "zh-Hans"
    case russian = "ru"

    var id: String { rawValue }

    var locale: Locale {
        switch self {
        case .system:
            return .autoupdatingCurrent
        case .english:
            return Locale(identifier: "en")
        case .spanish:
            return Locale(identifier: "es")
        case .chinese:
            return Locale(identifier: "zh-Hans")
        case .russian:
            return Locale(identifier: "ru")
        }
    }

    var title: String {
        switch self {
        case .system: return L10n.tr("Системный")
        case .english: return "English"
        case .spanish: return "Español"
        case .chinese: return "中文"
        case .russian: return "Русский"
        }
    }
}

enum L10n {
    static func tr(_ key: String) -> String {
        NSLocalizedString(key, comment: "")
    }

    static func format(_ key: String, _ args: CVarArg...) -> String {
        String(format: tr(key), locale: .autoupdatingCurrent, arguments: args)
    }
}

extension String {
    var localized: String { L10n.tr(self) }
}
