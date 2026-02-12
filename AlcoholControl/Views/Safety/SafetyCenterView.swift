import SwiftUI

private enum SafetySymptom: String, CaseIterable, Identifiable {
    case confusion
    case vomiting
    case breathing
    case unconscious
    case seizure
    case panic

    var id: String { rawValue }

    var title: String {
        switch self {
        case .confusion: return L10n.tr("Сильная спутанность")
        case .vomiting: return L10n.tr("Повторная рвота")
        case .breathing: return L10n.tr("Затрудненное дыхание")
        case .unconscious: return L10n.tr("Потеря сознания")
        case .seizure: return L10n.tr("Судороги")
        case .panic: return L10n.tr("Сильная тревога/паника")
        }
    }
}

struct SafetyCenterView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    @AppStorage("trustedContactName") private var trustedContactName = ""
    @AppStorage("trustedContactPhone") private var trustedContactPhone = ""

    @State private var selected: Set<SafetySymptom> = []
    @State private var showEmergencyConfirm = false
    @State private var showContactCallConfirm = false
    @State private var showContactMessageConfirm = false
    @State private var crisisMode = false

    private var riskLevel: String {
        if selected.contains(.unconscious) || selected.contains(.breathing) || selected.contains(.seizure) {
            return L10n.tr("Критично")
        }
        if selected.count >= 3 {
            return L10n.tr("Высокий")
        }
        if selected.isEmpty {
            return L10n.tr("Наблюдение")
        }
        return L10n.tr("Повышенный")
    }

    private var hasTrustedContact: Bool {
        !trustedContactPhone.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            List {
                Section(L10n.tr("Кризисный режим")) {
                    Toggle("Мне нужна помощь прямо сейчас", isOn: $crisisMode)
                    if crisisMode {
                        Text("Сразу перейдите к безопасности: остановитесь, позовите человека рядом и вызовите помощь при ухудшении.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        Button("Экстренный вызов 112", role: .destructive) {
                            showEmergencyConfirm = true
                        }
                        if hasTrustedContact {
                            Button("Сообщить доверенному контакту") {
                                showContactMessageConfirm = true
                            }
                        }
                    }
                }

                Section("Оценка состояния") {
                    Text("Если есть опасные симптомы, лучше сразу обратиться за помощью. Не оставайтесь в одиночку.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                    ForEach(SafetySymptom.allCases) { symptom in
                        Toggle(symptom.title, isOn: Binding(
                            get: { selected.contains(symptom) },
                            set: { enabled in
                                if enabled {
                                    selected.insert(symptom)
                                } else {
                                    selected.remove(symptom)
                                }
                            }
                        ))
                    }
                }

                Section("Текущий уровень") {
                    HStack {
                        Text("Риск")
                        Spacer()
                        Text(riskLevel)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(riskColor)
                    }
                    Text("Не используйте приложение для решения о вождении.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Действия") {
                    Button("Позвонить 112", role: .destructive) {
                        showEmergencyConfirm = true
                    }

                    if hasTrustedContact {
                        Button("Позвонить доверенному контакту") {
                            showContactCallConfirm = true
                        }
                        Button("Написать доверенному контакту") {
                            showContactMessageConfirm = true
                        }
                    } else {
                        Text("Добавьте доверенный контакт в Настройках для быстрого звонка/сообщения.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Короткий план") {
                    Text("1. Прекратите употребление алкоголя.")
                    Text("2. Перейдите в безопасное место и не оставайтесь одни.")
                    Text("3. Пейте воду небольшими глотками, если в сознании.")
                    Text("4. При ухудшении состояния вызывайте экстренную помощь.")
                    if crisisMode {
                        Text("5. Не засыпайте в одиночку при выраженных симптомах.")
                    }
                }
            }
            .navigationTitle(L10n.tr("Центр безопасности"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Закрыть") { dismiss() }
                }
            }
            .alert("Вызвать 112?", isPresented: $showEmergencyConfirm) {
                Button("Позвонить", role: .destructive) {
                    call(phone: "112")
                }
                Button("Отмена", role: .cancel) {}
            } message: {
                Text("Если есть риск для жизни или резкое ухудшение состояния, вызовите экстренную помощь.")
            }
            .alert("Позвонить контакту?", isPresented: $showContactCallConfirm) {
                Button("Позвонить") {
                    call(phone: trustedContactPhone)
                }
                Button("Отмена", role: .cancel) {}
            } message: {
                Text(contactLabel)
            }
            .alert("Отправить сообщение?", isPresented: $showContactMessageConfirm) {
                Button("Открыть сообщения") {
                    message(phone: trustedContactPhone)
                }
                Button("Отмена", role: .cancel) {}
            } message: {
                Text(contactLabel)
            }
        }
    }

    private var contactLabel: String {
        let name = trustedContactName.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? trustedContactPhone : "\(name) · \(trustedContactPhone)"
    }

    private var riskColor: Color {
        switch riskLevel {
        case let level where level == L10n.tr("Критично"):
            return .red
        case let level where level == L10n.tr("Высокий"):
            return .orange
        case let level where level == L10n.tr("Повышенный"):
            return .yellow
        default:
            return .green
        }
    }

    private func call(phone: String) {
        let sanitized = phone.filter { $0.isNumber || $0 == "+" }
        guard let url = URL(string: "tel://\(sanitized)") else { return }
        openURL(url)
    }

    private func message(phone: String) {
        let sanitized = phone.filter { $0.isNumber || $0 == "+" }
        let body = "Мне сейчас нужна помощь, будь на связи."
        let encodedBody = body.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? body
        guard let url = URL(string: "sms:\(sanitized)&body=\(encodedBody)") else { return }
        openURL(url)
    }
}
