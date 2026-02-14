import SwiftUI
import SwiftData

struct MorningCheckInView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    let session: Session
    var onSaved: (UUID) -> Void

    @State private var wellbeing: Int?
    @State private var selectedSymptoms: Set<MorningCheckIn.Symptom> = []
    @State private var sleepHours: Double = 7
    @State private var hadWater = true
    @State private var showValidation = false
    @State private var healthStatus = ""
    @State private var isHealthLoading = false

    var body: some View {
        NavigationStack {
            Form {
                Section(L10n.tr("Самочувствие")) {
                    Picker(L10n.tr("Оценка"), selection: $wellbeing) {
                        Text(L10n.tr("Выберите")).tag(Int?.none)
                        ForEach(0...5, id: \.self) { score in
                            Text("\(score)").tag(Int?.some(score))
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Section(L10n.tr("Симптомы (опционально)")) {
                    ForEach(MorningCheckIn.Symptom.allCases.filter { $0 != .none }) { symptom in
                        Toggle(symptom.label, isOn: Binding(
                            get: { selectedSymptoms.contains(symptom) },
                            set: { enabled in
                                if enabled {
                                    selectedSymptoms.insert(symptom)
                                } else {
                                    selectedSymptoms.remove(symptom)
                                }
                            }
                        ))
                    }
                }

                Section(L10n.tr("Дополнительно (опционально)")) {
                    Stepper(value: $sleepHours, in: 0...14, step: 0.5) {
                        HStack {
                            Text(L10n.tr("Сон"))
                            Spacer()
                            Text(L10n.format("%.1f ч", sleepHours))
                        }
                    }

                    Button(isHealthLoading ? L10n.tr("Импортируем...") : L10n.tr("Импортировать сон из Apple Health")) {
                        Task { await importSleepFromHealth() }
                    }
                    .disabled(isHealthLoading)

                    Toggle(L10n.tr("Пил(а) воду"), isOn: $hadWater)

                    if !healthStatus.isEmpty {
                        Text(healthStatus)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                Section {
                    Button(L10n.tr("Готово")) {
                        save()
                    }
                }
            }
            .navigationTitle(L10n.tr("Утренний чек-ин"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.tr("Закрыть")) {
                        dismiss()
                    }
                }
            }
            .alert(L10n.tr("Заполните оценку"), isPresented: $showValidation) {
                Button(L10n.tr("Ок"), role: .cancel) {}
            } message: {
                Text(L10n.tr("Выберите wellbeing score от 0 до 5."))
            }
        }
    }

    private func save() {
        guard let wellbeing else {
            showValidation = true
            return
        }

        let checkIn = MorningCheckIn(
            wellbeingScore: wellbeing,
            symptoms: Array(selectedSymptoms),
            sleepHours: sleepHours,
            hadWater: hadWater,
            session: session
        )

        session.morningCheckIn = checkIn
        session.isActive = false
        session.endAt = session.endAt ?? .now
        context.insert(checkIn)

        onSaved(session.id)
        dismiss()
    }

    private func importSleepFromHealth() async {
        isHealthLoading = true
        defer { isHealthLoading = false }

        guard HealthKitService.shared.isAvailable else {
            healthStatus = L10n.tr("Apple Health недоступен на этом устройстве")
            return
        }

        let granted = await HealthKitService.shared.requestSleepAuthorization()
        guard granted else {
            healthStatus = L10n.tr("Доступ к данным сна не предоставлен.")
            return
        }

        if let imported = await HealthKitService.shared.fetchLastNightSleepHours() {
            sleepHours = imported
            healthStatus = L10n.format("Импортировано: %.1f ч сна.", imported)
        } else {
            healthStatus = L10n.tr("Не удалось получить данные сна за последнюю ночь.")
        }
    }
}
