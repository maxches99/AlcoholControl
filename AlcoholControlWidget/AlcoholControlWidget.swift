import WidgetKit
import SwiftUI
#if canImport(ActivityKit)
import ActivityKit
#endif

private func widgetTr(_ key: String) -> String {
    NSLocalizedString(key, comment: "")
}

private func widgetFmt(_ key: String, _ args: CVarArg...) -> String {
    String(format: widgetTr(key), locale: .autoupdatingCurrent, arguments: args)
}

private enum WidgetKeys {
    static let appGroupID = "group.maxches.AlcoholControl"
    static let isActive = "widget.isActive"
    static let bac = "widget.currentBAC"
    static let soberAt = "widget.soberAt"
    static let waterConsumed = "widget.waterConsumedMl"
    static let waterTarget = "widget.waterTargetMl"
    static let risk = "widget.morningRisk"
    static let recoveryScore = "widget.recoveryScore"
    static let recoveryLevel = "widget.recoveryLevel"
    static let updatedAt = "widget.updatedAt"
}

struct AlcoholWidgetEntry: TimelineEntry {
    let date: Date
    let isActive: Bool
    let currentBAC: Double
    let soberAt: Date?
    let waterConsumedMl: Int
    let waterTargetMl: Int
    let riskTitle: String
    let recoveryScore: Int
    let recoveryLevel: String
}

struct AlcoholWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> AlcoholWidgetEntry {
        AlcoholWidgetEntry(
            date: .now,
            isActive: true,
            currentBAC: 0.072,
            soberAt: .now.addingTimeInterval(2 * 3600),
            waterConsumedMl: 500,
            waterTargetMl: 1100,
            riskTitle: "medium",
            recoveryScore: 78,
            recoveryLevel: "medium"
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (AlcoholWidgetEntry) -> Void) {
        completion(readEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<AlcoholWidgetEntry>) -> Void) {
        let entry = readEntry()
        let refresh = Calendar.current.date(byAdding: .minute, value: 15, to: .now) ?? .now.addingTimeInterval(900)
        completion(Timeline(entries: [entry], policy: .after(refresh)))
    }

    private func readEntry() -> AlcoholWidgetEntry {
        guard let defaults = UserDefaults(suiteName: WidgetKeys.appGroupID) else {
            return AlcoholWidgetEntry(
                date: .now,
                isActive: false,
                currentBAC: 0,
                soberAt: nil,
                waterConsumedMl: 0,
                waterTargetMl: 1000,
                riskTitle: "low",
                recoveryScore: 80,
                recoveryLevel: "low"
            )
        }

        let timestamp = defaults.double(forKey: WidgetKeys.updatedAt)
        let updatedAt = timestamp > 0 ? Date(timeIntervalSince1970: timestamp) : .now
        let soberTimestamp = defaults.double(forKey: WidgetKeys.soberAt)
        let soberAt = soberTimestamp > 0 ? Date(timeIntervalSince1970: soberTimestamp) : nil

        return AlcoholWidgetEntry(
            date: updatedAt,
            isActive: defaults.bool(forKey: WidgetKeys.isActive),
            currentBAC: defaults.double(forKey: WidgetKeys.bac),
            soberAt: soberAt,
            waterConsumedMl: defaults.integer(forKey: WidgetKeys.waterConsumed),
            waterTargetMl: max(1, defaults.integer(forKey: WidgetKeys.waterTarget)),
            riskTitle: defaults.string(forKey: WidgetKeys.risk) ?? "low",
            recoveryScore: defaults.integer(forKey: WidgetKeys.recoveryScore),
            recoveryLevel: defaults.string(forKey: WidgetKeys.recoveryLevel) ?? "low"
        )
    }
}

struct AlcoholControlWidget: Widget {
    let kind: String = "AlcoholControlWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: AlcoholWidgetProvider()) { entry in
            AlcoholControlWidgetEntryView(entry: entry)
        }
        .configurationDisplayName(widgetTr("Alcohol Control"))
        .description("Текущий статус сессии, BAC и водный баланс")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular, .accessoryCircular, .accessoryInline])
    }
}

#if canImport(ActivityKit)
struct EveningSessionAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var currentBAC: Double
        var targetSoberAt: Date?
        var updatedAt: Date
    }

    var sessionID: String
}

@available(iOSApplicationExtension 16.2, *)
struct AlcoholControlLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: EveningSessionAttributes.self) { context in
            VStack(alignment: .leading, spacing: 8) {
                Text(widgetTr("Alcohol Control"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(widgetFmt("BAC ~%.3f", context.state.currentBAC))
                    .font(.title3.bold())
                Text(soberText(context.state.targetSoberAt))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding(12)
            .activityBackgroundTint(Color.blue.opacity(0.15))
            .activitySystemActionForegroundColor(.primary)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Text("BAC")
                        .font(.caption2)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(String(format: "%.3f", context.state.currentBAC))
                        .font(.caption.bold())
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Text(soberText(context.state.targetSoberAt))
                        .font(.caption2)
                }
            } compactLeading: {
                Text("BAC")
                    .font(.caption2)
            } compactTrailing: {
                Text(String(format: "%.2f", context.state.currentBAC))
                    .font(.caption2)
            } minimal: {
                Text(String(format: "%.2f", context.state.currentBAC))
                    .font(.caption2)
            }
        }
    }

    private func soberText(_ target: Date?) -> String {
        guard let target else { return widgetTr("0.00 сейчас") }
        let interval = target.timeIntervalSince(.now)
        if interval <= 0 { return widgetTr("0.00 сейчас") }
        let minutes = Int(interval / 60)
        let hours = minutes / 60
        let rest = minutes % 60
        if hours > 0 {
            return widgetFmt("До 0.00 ~%dч %dм", hours, rest)
        }
        return widgetFmt("До 0.00 ~%dм", rest)
    }
}
#endif

private struct AlcoholControlWidgetEntryView: View {
    let entry: AlcoholWidgetEntry

    var body: some View {
        switch family {
        case .accessoryCircular:
            accessoryCircularView
        case .accessoryInline:
            accessoryInlineView
        case .accessoryRectangular:
            accessoryRectangularView
        default:
            regularView
        }
    }

    @Environment(\.widgetFamily) private var family

    private var regularView: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(widgetTr("Alcohol Control"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Circle()
                    .fill(entry.isActive ? Color.green : Color.gray)
                    .frame(width: 8, height: 8)
            }

            if entry.isActive {
                Text(widgetFmt("BAC ~%.3f", entry.currentBAC))
                    .font(.title3.bold())

                Text(soberText)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 4) {
                    ProgressView(value: waterProgress)
                    Text("Вода: \(entry.waterConsumedMl)/\(entry.waterTargetMl) мл")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Text("Утренний риск: \(entry.riskTitle)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                HStack {
                    Text(widgetFmt("Recovery %d", entry.recoveryScore))
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(recoveryColor)
                    Spacer()
                    Text(entry.recoveryLevel.capitalized)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 8) {
                    quickActionLink(title: "Вода", url: "alcoholcontrol://quick/water")
                    quickActionLink(title: "Пиво", url: "alcoholcontrol://quick/beer")
                    quickActionLink(title: "Коктейль", url: "alcoholcontrol://quick/cocktail")
                    quickActionLink(title: "Пауза", url: "alcoholcontrol://quick/pause")
                }
                HStack(spacing: 8) {
                    quickActionLink(title: "Стоп", url: "alcoholcontrol://quick/stop")
                    quickActionLink(title: "Чек-ин", url: "alcoholcontrol://quick/checkin")
                }
            } else {
                Text("Нет активной сессии")
                    .font(.headline)
                Text("Откройте приложение, чтобы начать вечер.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack(spacing: 8) {
                    quickActionLink(title: "Старт", url: "alcoholcontrol://quick/start")
                    quickActionLink(title: "Чек-ин", url: "alcoholcontrol://quick/checkin")
                }
            }
        }
        .padding(12)
        .containerBackground(.fill.tertiary, for: .widget)
    }

    private var accessoryRectangularView: some View {
        VStack(alignment: .leading, spacing: 2) {
            if entry.isActive {
                Text(widgetFmt("BAC %.3f", entry.currentBAC))
                    .font(.caption.bold())
                Text(soberText)
                    .font(.caption2)
                Text(widgetFmt("H2O %d%%", Int((waterProgress * 100).rounded())))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(widgetFmt("Rec %d", entry.recoveryScore))
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(recoveryColor)
            } else {
                Text("Сессия не активна")
                    .font(.caption)
            }
        }
    }

    private var accessoryCircularView: some View {
        ZStack {
            AccessoryWidgetBackground()
            VStack(spacing: 1) {
                if entry.isActive {
                    Text(String(format: "%.2f", entry.currentBAC))
                        .font(.caption2.monospacedDigit())
                    Text("\(Int((waterProgress * 100).rounded()))%")
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                    Text(widgetFmt("R%d", entry.recoveryScore))
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .foregroundStyle(recoveryColor)
                } else {
                    Text(widgetTr("Выкл"))
                        .font(.caption2)
                }
            }
        }
    }

    private var accessoryInlineView: some View {
        if entry.isActive {
            Text(widgetFmt("BAC %.2f • %@ • Rec %d", entry.currentBAC, soberInlineText, entry.recoveryScore))
        } else {
            Text(widgetTr("Сессия не активна"))
        }
    }

    private var waterProgress: Double {
        min(1, Double(entry.waterConsumedMl) / Double(max(1, entry.waterTargetMl)))
    }

    private var recoveryColor: Color {
        switch entry.recoveryLevel {
        case "high":
            return .red
        case "medium":
            return .orange
        default:
            return .green
        }
    }

    private var soberText: String {
        guard let soberAt else { return "0.00 сейчас" }
        let seconds = soberAt.timeIntervalSince(.now)
        if seconds <= 0 { return "0.00 сейчас" }
        let minutes = Int(seconds / 60)
        let hours = minutes / 60
        let rest = minutes % 60
        if hours > 0 {
            return widgetFmt("До 0.00 ~%dч %dм", hours, rest)
        }
        return widgetFmt("До 0.00 ~%dм", rest)
    }

    private var soberInlineText: String {
        guard let soberAt else { return widgetTr("0.00 сейчас") }
        let seconds = soberAt.timeIntervalSince(.now)
        if seconds <= 0 { return widgetTr("0.00 сейчас") }
        let minutes = Int(seconds / 60)
        let hours = minutes / 60
        let rest = minutes % 60
        if hours > 0 {
            return widgetFmt("%dч %dм", hours, rest)
        }
        return widgetFmt("%dм", rest)
    }

    private var soberAt: Date? {
        entry.soberAt
    }

    @ViewBuilder
    private func quickActionLink(title: String, url: String) -> some View {
        if let destination = URL(string: url) {
            Link(destination: destination) {
                Text(title)
                    .font(.caption2.weight(.semibold))
                    .padding(.vertical, 4)
                    .padding(.horizontal, 6)
                    .background(.thinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
    }
}
