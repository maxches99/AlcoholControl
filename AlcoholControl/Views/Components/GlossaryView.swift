import SwiftUI

struct GlossaryView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                term("BAC (примерно)", "Оценка концентрации алкоголя в крови. Это модель, а не медицинский прибор.")
                term("Peak BAC", "Максимальное оценочное значение BAC за сессию.")
                term("До ~0.00", "Примерное время, когда по модели BAC опустится до 0.")
                term("Риск тяжелого утра", "Эвристика, учитывающая BAC, темп, воду, длительность и приемы пищи.")
                term("Риск провалов памяти", "Эвристика вероятности, что часть эпизодов может плохо запомниться.")
                term("Водный баланс", "Оценка: сколько воды уже выпито относительно целевого объема на сессию.")
                term("Цель воды", "Приблизительный ориентир по воде с учетом веса, длительности и объема алкоголя.")
                term("Прием пищи", "Еда может частично снижать остроту состояния и риски, особенно при регулярном приеме.")
                term("Стандартный дринк", "Условная порция алкоголя (~14 г этанола) для расчетов темпа и нагрузки.")
                term("Персональный порог", "Индивидуальный ориентир риска, рассчитанный по вашим предыдущим сессиям.")
                term("Уверенность модели", "Показывает, насколько надежна оценка по текущему набору данных (вес, вода, еда, полнота логов).")
                term("События риска", "Конкретные эпизоды в сессии, которые увеличили риск: быстрый темп, крепкие напитки, дефицит воды.")
                term("Pre-session plan", "План до начала вечера: лимит алкоголя, цель воды и ориентир времени завершения.")
                term("Safety mode", "Более осторожный режим: ранние напоминания о паузах, воде и быстром переходе к safety-действиям.")
                term("Crisis mode", "Режим срочной помощи: быстрый доступ к экстренным действиям и контакту доверенного человека.")
                term("Smart reminders", "Напоминания, которые учитывают текущий риск, а не только фиксированный интервал.")
                term("Recovery plan (2-4h)", "Короткий персонализированный план восстановления после сессии с отметкой выполненных шагов.")
                term("Trigger patterns", "Повторяющиеся дни, время и типы напитков, которые чаще связаны с тяжелым утром.")
                term("Weekly harm-reduction goals", "Недельные лимиты по рискам и цель гидратации для контроля прогресса.")
                term("Streak", "Серия сессий подряд, где вы держите полезную привычку, например воду или прием пищи.")
                term("Тренд", "Направление изменения показателя по истории: улучшается, ухудшается или стабильно.")
            }
            .navigationTitle("Термины и пояснения")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Закрыть") { dismiss() }
                }
            }
        }
    }

    private func term(_ title: String, _ description: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.headline)
            Text(description)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }
}

struct GlossaryTooltipView: View {
    var onOpenFullGlossary: (() -> Void)?

    private let quickTerms: [(icon: String, title: String, description: String)] = [
        (
            "waveform.path.ecg",
            "BAC (примерно)",
            "Нужен для ориентира по динамике. Это модель, а не точное измерение."
        ),
        (
            "clock",
            "До ~0.00",
            "Показывает примерное время, когда по расчёту BAC вернется к нулю."
        ),
        (
            "sun.max.trianglebadge.exclamationmark",
            "Риск тяжелого утра",
            "Итоговая оценка по темпу, объему, воде и длительности сессии."
        ),
        (
            "brain.head.profile",
            "Риск провалов памяти",
            "Вероятность того, что часть эпизодов запомнится хуже обычного."
        )
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Быстрые подсказки")
                    .font(.headline)
                Text("Короткие пояснения к ключевым метрикам.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            ForEach(quickTerms, id: \.title) { item in
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Image(systemName: item.icon)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Text(item.title)
                            .font(.subheadline.weight(.semibold))
                    }
                    Text(item.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(uiColor: .secondarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }

            if let onOpenFullGlossary {
                Divider()
                Button {
                    onOpenFullGlossary()
                } label: {
                    Label("Открыть полный словарь", systemImage: "text.book.closed")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
        }
        .padding(14)
        .frame(maxWidth: 320, alignment: .leading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(.white.opacity(0.24))
        )
        .shadow(color: .black.opacity(0.18), radius: 18, y: 8)
    }
}
