import SwiftUI
import SwiftData

struct HistoryView: View {
    @Query(sort: [SortDescriptor<Session>(\.startAt, order: .reverse)]) private var sessions: [Session]

    init() {
        _sessions = Query(sort: [SortDescriptor<Session>(\.startAt, order: .reverse)])
    }

    var body: some View {
        NavigationStack {
            List {
                if sessions.isEmpty {
                    Section {
                        Text("История пока пуста")
                            .foregroundStyle(.secondary)
                    }
                }

                ForEach(sessions) { session in
                    NavigationLink {
                        SessionDetailView(session: session)
                    } label: {
                        SessionRowCard(session: session)
                    }
                    .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle("История")
        }
    }
}

private struct SessionRowCard: View {
    let session: Session

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(session.startAt, format: .dateTime.day().month().year())
                    .font(.headline)
                Spacer()
                Text(session.isActive ? "В процессе" : "Завершена")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(session.isActive ? .orange : .secondary)
            }

            HStack(spacing: 8) {
                badge(
                    title: "Пик BAC",
                    value: session.cachedPeakBAC > 0 ? String(format: "%.3f", session.cachedPeakBAC) : "Нет"
                )
                badge(
                    title: "Чек-ин",
                    value: session.morningCheckIn.map { "\($0.wellbeingScore)/5" } ?? "Нет"
                )
                badge(
                    title: "Вода",
                    value: "\(session.waters.count)"
                )
            }
        }
        .padding()
        .background(.thinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private func badge(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.subheadline.weight(.semibold))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

private enum SessionDetailSheet: Identifiable {
    case editDrink(UUID)
    case share

    var id: String {
        switch self {
        case .editDrink(let id): return "edit-drink-\(id.uuidString)"
        case .share: return "share"
        }
    }
}

struct SessionDetailView: View {
    @Environment(\.modelContext) private var context
    @Query private var profiles: [UserProfile]

    let session: Session

    @State private var activeSheet: SessionDetailSheet?
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
        List {
            Section("Показатели") {
                Text("Пик BAC (примерно): \(String(format: "%.3f", session.cachedPeakBAC))")
                Text(session.cachedEstimatedSoberAt.map { "До ~0.00: \($0, format: .dateTime.hour().minute())" } ?? "До ~0.00: 0.00 сейчас")
            }

            Section("Напитки") {
                if sortedDrinks.isEmpty {
                    Text("Нет записей")
                        .foregroundStyle(.secondary)
                }
                ForEach(sortedDrinks) { drink in
                    Button {
                        activeSheet = .editDrink(drink.id)
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
                            Label("Удалить", systemImage: "trash")
                        }
                    }
                }
            }

            Section("Вода") {
                if sortedWaters.isEmpty {
                    Text("Нет записей")
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
                            Label("Удалить", systemImage: "trash")
                        }
                    }
                }
            }

            Section("Приемы пищи") {
                if sortedMeals.isEmpty {
                    Text("Нет записей")
                        .foregroundStyle(.secondary)
                }
                ForEach(sortedMeals) { meal in
                    HStack {
                        VStack(alignment: .leading) {
                            Text((meal.title ?? "Прием пищи").localized)
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
                            Label("Удалить", systemImage: "trash")
                        }
                    }
                }
            }

            if let checkIn = session.morningCheckIn {
                Section("Утренний чек-ин") {
                    Text("Самочувствие: \(checkIn.wellbeingScore)/5")
                    if !checkIn.symptoms.isEmpty {
                        Text("Симптомы: \(checkIn.symptoms.map { $0.label }.joined(separator: ", "))")
                    }
                    if let sleep = checkIn.sleepHours {
                        Text("Сон: \(sleep, format: .number) ч")
                    }
                    if let hadWater = checkIn.hadWater {
                        Text(hadWater ? "Пил(а) воду" : "Без воды")
                    }
                }
            }
        }
        .navigationTitle(session.startAt.formatted(date: .abbreviated, time: .omitted))
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
            case .editDrink(let drinkID):
                if let drink = session.drinks.first(where: { $0.id == drinkID }) {
                    DrinkEditorSheet(drink: drink, session: session, profile: profile)
                }
            case .share:
                ShareCardView(session: session)
            }
        }
    }
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
