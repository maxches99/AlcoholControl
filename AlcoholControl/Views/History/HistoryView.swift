import SwiftUI
import SwiftData

struct HistoryView: View {
    @Query(sort: [SortDescriptor<Session>(\.startAt, order: .reverse)]) private var sessions: [Session]

    init() {
        _sessions = Query(sort: [SortDescriptor<Session>(\.startAt, order: .reverse)])
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 12) {
                    if sessions.isEmpty {
                        VStack(spacing: 12) {
                            Image(systemName: "clock.badge.questionmark")
                                .font(.title3)
                                .foregroundStyle(Color.white.opacity(0.5))
                            Text(L10n.tr("История пока пуста"))
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(Color.white.opacity(0.7))
                        }
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(20)
                        .background(
                            RoundedRectangle(cornerRadius: 20, style: .continuous)
                                .fill(Color.white.opacity(0.08))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                                )
                        )
                    } else {
                        ForEach(sessions) { session in
                            NavigationLink {
                                SessionDetailView(session: session)
                            } label: {
                                SessionRowCard(session: session)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 28)
            }
            .background(
                LinearGradient(
                    colors: [
                        Color(red: 0.06, green: 0.08, blue: 0.08),
                        Color(red: 0.07, green: 0.10, blue: 0.09),
                        Color(red: 0.08, green: 0.10, blue: 0.09)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()
            )
            .navigationTitle(L10n.tr("История"))
        }
    }
}

private struct SessionRowCard: View {
    let session: Session

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(session.startAt, format: .dateTime.day().month().year())
                    .font(.system(.headline, design: .rounded).weight(.bold))
                    .foregroundStyle(Color.white.opacity(0.9))
                Spacer()
                Text(session.isActive ? L10n.tr("В процессе") : L10n.tr("Завершена"))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.white.opacity(0.82))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(
                        Capsule(style: .continuous)
                            .fill((session.isActive ? Color.orange : Color.white).opacity(0.16))
                    )
            }

            HStack(spacing: 8) {
                badge(
                    title: L10n.tr("Пик BAC"),
                    value: session.cachedPeakBAC > 0 ? String(format: "%.3f", session.cachedPeakBAC) : L10n.tr("Нет")
                )
                badge(
                    title: L10n.tr("Чек-ин"),
                    value: session.morningCheckIn.map { "\($0.wellbeingScore)/5" } ?? L10n.tr("Нет")
                )
                badge(
                    title: L10n.tr("Вода"),
                    value: "\(session.waters.count)"
                )
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color.white.opacity(0.07))
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )
        )
    }

    private func badge(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(Color.white.opacity(0.55))
            Text(value)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.white.opacity(0.9))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(Color.white.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

private enum SessionDetailSheet: Identifiable {
    case editSession
    case share

    var id: String {
        switch self {
        case .editSession: return "edit-session"
        case .share: return "share"
        }
    }
}

struct SessionDetailView: View {
    let session: Session

    @State private var exportURL: URL?
    @State private var showingExportShare = false
    @State private var statusMessage: String?
    @State private var activeSheet: SessionDetailSheet?
    @Query private var profiles: [UserProfile]

    private let exportService = DataExportService()

    private var profile: UserProfile? { profiles.first }

    private var sessionEndAt: Date {
        if let endAt = session.endAt { return endAt }
        let latestEvent = (session.drinks.map(\.createdAt) + session.waters.map(\.createdAt) + session.meals.map(\.createdAt))
            .max() ?? session.startAt
        return max(latestEvent, session.startAt.addingTimeInterval(60 * 60))
    }

    private var durationMinutes: Int {
        max(1, Int(sessionEndAt.timeIntervalSince(session.startAt) / 60))
    }

    private var durationText: String {
        if durationMinutes >= 60 {
            return L10n.format("%.1f ч", Double(durationMinutes) / 60.0)
        }
        return L10n.format("%d мин", durationMinutes)
    }

    private var paceLabel: String {
        if session.cachedPeakBAC < 0.04 && session.drinks.count <= 2 {
            return L10n.tr("Легкий темп")
        }
        if session.cachedPeakBAC < 0.09 && session.drinks.count <= 5 {
            return L10n.tr("Умеренный темп")
        }
        return L10n.tr("Высокий темп")
    }

    private var chartPoints: [SessionCurvePoint] {
        let endAt = sessionEndAt
        let totalSeconds = max(1, endAt.timeIntervalSince(session.startAt))
        let drinks = session.drinks.sorted(by: { $0.createdAt < $1.createdAt })

        if drinks.isEmpty {
            return [
                SessionCurvePoint(position: 0, value: 0),
                SessionCurvePoint(position: 0.35, value: 0.35),
                SessionCurvePoint(position: 0.75, value: 0.18),
                SessionCurvePoint(position: 1, value: 0)
            ]
        }

        var points: [SessionCurvePoint] = [SessionCurvePoint(position: 0, value: 0)]
        var level = 0.0
        var previous = session.startAt

        for drink in drinks {
            let elapsedHours = max(0, drink.createdAt.timeIntervalSince(previous) / 3600)
            level = max(0, level - elapsedHours * 0.015)

            let units = (drink.volumeMl * (drink.abvPercent / 100.0) * 0.789) / 10.0
            level = min(0.22, level + units * 0.016)

            let position = max(0, min(1, drink.createdAt.timeIntervalSince(session.startAt) / totalSeconds))
            points.append(SessionCurvePoint(position: position, value: level))
            previous = drink.createdAt
        }

        points.append(SessionCurvePoint(position: 1, value: 0))
        return points
    }

    private var hourMarkers: [String] {
        let markerCount = 8
        guard markerCount > 1 else { return [] }
        return (0..<markerCount).map { index in
            let progress = Double(index) / Double(markerCount - 1)
            let date = session.startAt.addingTimeInterval(sessionEndAt.timeIntervalSince(session.startAt) * progress)
            return date.formatted(.dateTime.hour())
        }
    }

    private var morningSummaryLines: [String] {
        guard let checkIn = session.morningCheckIn else {
            return [L10n.tr("Нет утреннего чек-ина")]
        }

        var lines: [String] = [L10n.format("Самочувствие: %d/5", checkIn.wellbeingScore)]

        if let sleep = checkIn.sleepHours {
            lines.append(L10n.format("Сон: %.1f ч", sleep))
        }
        if let hadWater = checkIn.hadWater {
            lines.append(hadWater ? L10n.tr("Пил(а) воду") : L10n.tr("Без воды"))
        }
        if !checkIn.symptoms.isEmpty {
            lines.append(L10n.format("Симптомы: %@", checkIn.symptoms.map(\.label).joined(separator: ", ")))
        }
        return lines
    }

    private var timelineEntries: [SessionTimelineEntry] {
        var entries: [SessionTimelineEntry] = [
            SessionTimelineEntry(
                id: "start-\(session.id.uuidString)",
                date: session.startAt,
                markerColor: Color(red: 0.76, green: 0.82, blue: 0.74),
                title: L10n.tr("Сессия началась"),
                subtitle: nil,
                trailing: nil
            )
        ]

        entries += session.drinks.map { drink in
            SessionTimelineEntry(
                id: "drink-\(drink.id.uuidString)",
                date: drink.createdAt,
                markerColor: Color(red: 0.86, green: 0.67, blue: 0.69),
                title: (drink.title ?? drink.category.label).localized,
                subtitle: nil,
                trailing: L10n.format("%d мл · %.1f%%", Int(drink.volumeMl), drink.abvPercent)
            )
        }

        entries += session.waters.map { water in
            SessionTimelineEntry(
                id: "water-\(water.id.uuidString)",
                date: water.createdAt,
                markerColor: Color(red: 0.74, green: 0.82, blue: 0.74),
                title: L10n.tr("Вода"),
                subtitle: L10n.tr("Гидратация"),
                trailing: water.volumeMl.map { L10n.format("%d мл", Int($0)) } ?? L10n.tr("Отметка")
            )
        }

        entries += session.meals.map { meal in
            SessionTimelineEntry(
                id: "meal-\(meal.id.uuidString)",
                date: meal.createdAt,
                markerColor: Color(red: 0.74, green: 0.82, blue: 0.74),
                title: (meal.title ?? L10n.tr("Прием пищи")).localized,
                subtitle: nil,
                trailing: meal.size.label
            )
        }

        if !session.isActive {
            entries.append(
                SessionTimelineEntry(
                    id: "end-\(session.id.uuidString)",
                    date: sessionEndAt,
                    markerColor: Color(red: 0.74, green: 0.82, blue: 0.74),
                    title: L10n.tr("Сессия завершена"),
                    subtitle: nil,
                    trailing: nil
                )
            )
        }

        return entries.sorted(by: { $0.date < $1.date })
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .center, spacing: 4) {
                    Text(session.startAt.formatted(.dateTime.weekday(.wide)))
                        .font(.system(.largeTitle, design: .rounded).weight(.bold))
                        .foregroundStyle(Color.white.opacity(0.92))
                    Text(session.startAt.formatted(.dateTime.month(.abbreviated).day().year().hour().minute()))
                        .font(.headline)
                        .foregroundStyle(Color.white.opacity(0.62))
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.top, 8)

                VStack(alignment: .leading, spacing: 14) {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(L10n.tr("Интенсивность сессии"))
                                .font(.callout.weight(.semibold))
                                .foregroundStyle(Color.white.opacity(0.56))
                            Text(paceLabel)
                                .font(.title3.weight(.bold))
                                .foregroundStyle(Color.white.opacity(0.92))
                        }
                        Spacer()
                        Text(L10n.tr("Более безопасное завершение"))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Color(red: 0.93, green: 0.91, blue: 0.84))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(
                                Capsule(style: .continuous)
                                    .fill(Color(red: 0.76, green: 0.72, blue: 0.60).opacity(0.46))
                            )
                    }

                    SessionCurveCard(points: chartPoints, hourMarkers: hourMarkers)
                        .frame(height: 180)

                    HStack(spacing: 10) {
                        SessionMetricCard(
                            icon: "wineglass.fill",
                            value: "\(session.drinks.count)",
                            caption: L10n.tr("Напитки"),
                            tint: Color(red: 0.86, green: 0.67, blue: 0.69)
                        )
                        SessionMetricCard(
                            icon: "drop.fill",
                            value: "\(session.waters.count)",
                            caption: L10n.tr("Вода"),
                            tint: Color(red: 0.72, green: 0.79, blue: 0.70)
                        )
                        SessionMetricCard(
                            icon: "clock",
                            value: durationText,
                            caption: L10n.tr("Продолжительность"),
                            tint: Color(red: 0.80, green: 0.84, blue: 0.78)
                        )
                    }
                }
                .sessionCardStyle()

                VStack(alignment: .leading, spacing: 10) {
                    Text(L10n.tr("Итог утра"))
                        .font(.system(.title3, design: .rounded).weight(.bold))
                        .foregroundStyle(Color.white.opacity(0.92))

                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(morningSummaryLines, id: \.self) { line in
                            Text(line)
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(Color.white.opacity(0.72))
                        }
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .fill(Color.white.opacity(0.08))
                            .overlay(
                                RoundedRectangle(cornerRadius: 22, style: .continuous)
                                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
                            )
                    )
                }
                .padding(.top, 4)

                VStack(alignment: .leading, spacing: 10) {
                    Text(L10n.tr("Лента событий"))
                        .font(.system(.title3, design: .rounded).weight(.bold))
                        .foregroundStyle(Color.white.opacity(0.92))

                    VStack(spacing: 0) {
                        if timelineEntries.isEmpty {
                            Text(L10n.tr("Записей пока нет"))
                                .font(.callout)
                                .foregroundStyle(Color.white.opacity(0.64))
                                .padding(.vertical, 18)
                        } else {
                            ForEach(timelineEntries) { entry in
                                SessionTimelineRow(entry: entry)
                            }
                        }
                    }
                    .sessionCardStyle()
                }

                VStack(spacing: 10) {
                    HStack(spacing: 12) {
                        Button {
                            exportJSON()
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "square.and.arrow.up")
                                Text(L10n.tr("Экспорт данных"))
                                    .lineLimit(1)
                            }
                            .font(.headline.weight(.semibold))
                            .foregroundStyle(Color.white.opacity(0.9))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(
                                Capsule(style: .continuous)
                                    .fill(Color.clear)
                                    .overlay(
                                        Capsule(style: .continuous)
                                            .stroke(Color.white.opacity(0.45), lineWidth: 1)
                                    )
                            )
                        }
                        .buttonStyle(.plain)

                        Button {
                            activeSheet = .editSession
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "pencil")
                                Text(L10n.tr("Редактировать сессию"))
                                    .lineLimit(1)
                            }
                            .font(.headline.weight(.semibold))
                            .foregroundStyle(Color(red: 0.95, green: 0.96, blue: 0.92))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(
                                Capsule(style: .continuous)
                                    .fill(Color(red: 0.62, green: 0.68, blue: 0.60))
                            )
                        }
                        .buttonStyle(.plain)
                    }

                    if let statusMessage {
                        Text(statusMessage)
                            .font(.footnote)
                            .foregroundStyle(Color.white.opacity(0.6))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 26)
        }
        .background(
            LinearGradient(
                colors: [
                    Color(red: 0.06, green: 0.08, blue: 0.08),
                    Color(red: 0.07, green: 0.10, blue: 0.09),
                    Color(red: 0.08, green: 0.10, blue: 0.09)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
        )
        .tint(AppDesign.Colors.primary)
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    activeSheet = .share
                } label: {
                    Image(systemName: "square.and.arrow.up")
                }
                .accessibilityLabel("Поделиться карточкой")
            }
        }
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .editSession:
                SessionEditorSheet(session: session)
            case .share:
                ShareCardView(session: session)
            }
        }
        .sheet(isPresented: $showingExportShare) {
            if let exportURL {
                ActivityView(activityItems: [exportURL])
            }
        }
    }

    @MainActor
    private func exportJSON() {
        do {
            let url = try exportService.exportJSON(sessions: [session], profile: profile)
            exportURL = url
            statusMessage = L10n.tr("JSON-резерв подготовлен")
            showingExportShare = true
        } catch {
            statusMessage = L10n.tr("Не удалось экспортировать JSON-резерв")
        }
    }
}

private struct SessionCurvePoint {
    let position: Double
    let value: Double
}

private struct SessionCurveCard: View {
    let points: [SessionCurvePoint]
    let hourMarkers: [String]

    private var maxValue: Double {
        max(0.001, points.map(\.value).max() ?? 0.001)
    }

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let height = proxy.size.height

            ZStack(alignment: .bottomLeading) {
                Path { path in
                    guard let first = points.first else { return }
                    let firstPoint = point(first, in: CGSize(width: width, height: height))
                    path.move(to: CGPoint(x: firstPoint.x, y: height))
                    path.addLine(to: firstPoint)
                    for item in points.dropFirst() {
                        path.addLine(to: point(item, in: CGSize(width: width, height: height)))
                    }
                    if let last = points.last {
                        path.addLine(to: CGPoint(x: point(last, in: CGSize(width: width, height: height)).x, y: height))
                    }
                    path.closeSubpath()
                }
                .fill(Color.white.opacity(0.14))

                Path { path in
                    guard let first = points.first else { return }
                    path.move(to: point(first, in: CGSize(width: width, height: height)))
                    for item in points.dropFirst() {
                        path.addLine(to: point(item, in: CGSize(width: width, height: height)))
                    }
                }
                .stroke(Color(red: 0.79, green: 0.84, blue: 0.77), style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
            }
        }
        .overlay(alignment: .bottom) {
            HStack {
                ForEach(hourMarkers, id: \.self) { marker in
                    Text(marker)
                        .font(.caption2)
                        .foregroundStyle(Color.white.opacity(0.52))
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(.top, 8)
            .padding(.horizontal, 4)
            .offset(y: 20)
        }
        .padding(.bottom, 20)
    }

    private func point(_ item: SessionCurvePoint, in size: CGSize) -> CGPoint {
        let x = size.width * item.position
        let normalized = item.value / maxValue
        let y = size.height - (size.height * CGFloat(normalized))
        return CGPoint(x: x, y: y)
    }
}

private struct SessionMetricCard: View {
    let icon: String
    let value: String
    let caption: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(tint.opacity(0.9))
            Text(value)
                .font(.system(.title3, design: .rounded).weight(.bold))
                .foregroundStyle(Color.white.opacity(0.9))
            Text(caption)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.white.opacity(0.62))
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.white.opacity(0.04))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )
        )
    }
}

private struct SessionTimelineEntry: Identifiable {
    let id: String
    let date: Date
    let markerColor: Color
    let title: String
    let subtitle: String?
    let trailing: String?
}

private struct SessionTimelineRow: View {
    let entry: SessionTimelineEntry

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(spacing: 8) {
                Circle()
                    .fill(entry.markerColor)
                    .frame(width: 9, height: 9)
                Rectangle()
                    .fill(Color.white.opacity(0.08))
                    .frame(width: 1)
            }
            .padding(.top, 4)

            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Text(entry.date, format: .dateTime.hour().minute())
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.white.opacity(0.62))
                    Spacer()
                    if let trailing = entry.trailing {
                        Text(trailing)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Color.white.opacity(0.56))
                    }
                }

                Text(entry.title)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(Color.white.opacity(0.9))

                if let subtitle = entry.subtitle {
                    Text(subtitle)
                        .font(.callout.weight(.medium))
                        .foregroundStyle(Color.white.opacity(0.58))
                }
            }
            .padding(.bottom, 14)
        }
        .padding(.horizontal, 14)
        .padding(.top, 10)
    }
}

private struct SessionCardStyleModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 30, style: .continuous)
                    .fill(Color.white.opacity(0.06))
                    .overlay(
                        RoundedRectangle(cornerRadius: 30, style: .continuous)
                            .stroke(Color.white.opacity(0.08), lineWidth: 1)
                    )
            )
    }
}

private extension View {
    func sessionCardStyle() -> some View {
        modifier(SessionCardStyleModifier())
    }
}

private struct SessionEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query private var profiles: [UserProfile]

    let session: Session

    @State private var editingDrinkID: DrinkSelection?
    private let service = SessionService()

    private var profile: UserProfile? { profiles.first }

    private var sortedDrinks: [DrinkEntry] {
        session.drinks.sorted(by: { $0.createdAt > $1.createdAt })
    }

    private var sortedWaters: [WaterEntry] {
        session.waters.sorted(by: { $0.createdAt > $1.createdAt })
    }

    private var sortedMeals: [MealEntry] {
        session.meals.sorted(by: { $0.createdAt > $1.createdAt })
    }

    var body: some View {
        NavigationStack {
            List {
                Section(L10n.tr("Показатели")) {
                    Text(L10n.format("Пик BAC (примерно): %.3f", session.cachedPeakBAC))
                    Text(
                        session.cachedEstimatedSoberAt.map { L10n.format("До ~0.00: %@", $0.formatted(.dateTime.hour().minute())) }
                            ?? L10n.tr("До ~0.00: 0.00 сейчас")
                    )
                }

                Section(L10n.tr("Напитки")) {
                    if sortedDrinks.isEmpty {
                        Text(L10n.tr("Нет записей"))
                            .foregroundStyle(.secondary)
                    }
                    ForEach(sortedDrinks) { drink in
                        Button {
                            editingDrinkID = DrinkSelection(id: drink.id)
                        } label: {
                            HStack {
                                VStack(alignment: .leading) {
                                    Text((drink.title ?? drink.category.label).localized)
                                    Text(drink.createdAt, style: .time)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text(L10n.format("%d мл @ %d%%", Int(drink.volumeMl), Int(drink.abvPercent)))
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .buttonStyle(.plain)
                        .swipeActions {
                            Button(role: .destructive) {
                                service.delete(entry: drink, from: session, context: context, profile: profile)
                            } label: {
                                Label(L10n.tr("Удалить"), systemImage: "trash")
                            }
                        }
                    }
                }

                Section(L10n.tr("Вода")) {
                    if sortedWaters.isEmpty {
                        Text(L10n.tr("Нет записей"))
                            .foregroundStyle(.secondary)
                    }
                    ForEach(sortedWaters) { water in
                        HStack {
                            Text(water.createdAt, style: .time)
                            Spacer()
                            Text(water.volumeMl.map { L10n.format("%d мл", Int($0)) } ?? L10n.tr("Отметка"))
                        }
                        .swipeActions {
                            Button(role: .destructive) {
                                service.delete(entry: water, from: session, context: context, profile: profile)
                            } label: {
                                Label(L10n.tr("Удалить"), systemImage: "trash")
                            }
                        }
                    }
                }

                Section(L10n.tr("Приемы пищи")) {
                    if sortedMeals.isEmpty {
                        Text(L10n.tr("Нет записей"))
                            .foregroundStyle(.secondary)
                    }
                    ForEach(sortedMeals) { meal in
                        HStack {
                            VStack(alignment: .leading) {
                                Text((meal.title ?? L10n.tr("Прием пищи")).localized)
                                Text(meal.createdAt, style: .time)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(meal.size.label)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                        .swipeActions {
                            Button(role: .destructive) {
                                service.delete(entry: meal, from: session, context: context, profile: profile)
                            } label: {
                                Label(L10n.tr("Удалить"), systemImage: "trash")
                            }
                        }
                    }
                }
            }
            .navigationTitle(L10n.tr("Редактировать сессию"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.tr("Готово")) {
                        dismiss()
                    }
                }
            }
            .sheet(item: $editingDrinkID) { id in
                if let drink = session.drinks.first(where: { $0.id == id.id }) {
                    DrinkEditorSheet(drink: drink, session: session, profile: profile)
                }
            }
        }
    }
}

private struct DrinkSelection: Identifiable {
    let id: UUID
}

private struct DrinkEditorSheet: View {
    @Environment(\.dismiss) private var dismiss

    let drink: DrinkEntry
    let session: Session
    let profile: UserProfile?

    @State private var title: String
    @State private var volume: Double
    @State private var abv: Double
    @State private var date: Date
    @State private var category: DrinkEntry.Category

    private let service = SessionService()

    init(drink: DrinkEntry, session: Session, profile: UserProfile?) {
        self.drink = drink
        self.session = session
        self.profile = profile
        _title = State(initialValue: drink.title ?? "")
        _volume = State(initialValue: drink.volumeMl)
        _abv = State(initialValue: drink.abvPercent)
        _date = State(initialValue: drink.createdAt)
        _category = State(initialValue: drink.category)
    }

    var body: some View {
        NavigationStack {
            Form {
                TextField("Название", text: $title)
                Picker("Категория", selection: $category) {
                    ForEach(DrinkEntry.Category.allCases) { category in
                        Text(category.label).tag(category)
                    }
                }
                Stepper(value: $volume, in: 10...2000, step: 10) {
                    HStack {
                        Text("Объем")
                        Spacer()
                        Text("\(Int(volume)) мл")
                    }
                }
                Stepper(value: $abv, in: 0.5...96, step: 0.5) {
                    HStack {
                        Text("Крепость")
                        Spacer()
                        Text(String(format: "%.1f%%", abv))
                    }
                }
                DatePicker("Время", selection: $date, displayedComponents: [.date, .hourAndMinute])

                Button("Сохранить") {
                    service.updateDrink(
                        drink,
                        in: session,
                        profile: profile,
                        createdAt: date,
                        volumeMl: volume,
                        abvPercent: abv,
                        title: title.isEmpty ? nil : title,
                        category: category
                    )
                    dismiss()
                }
                .disabled(volume <= 0 || abv <= 0)
            }
            .navigationTitle("Редактировать")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { dismiss() }
                }
            }
        }
    }
}
