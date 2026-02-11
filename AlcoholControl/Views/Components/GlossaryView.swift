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
            .navigationTitle("Подсказки терминов")
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

    private let quickTerms: [(String, String)] = [
        ("BAC (примерно)", "Оценка BAC по модели, а не мед. измерение."),
        ("До ~0.00", "Примерное время, когда BAC по модели снизится до 0."),
        ("Риск тяжелого утра", "Эвристика на базе BAC, темпа, воды и длительности."),
        ("Риск провалов памяти", "Оценка вероятности фрагментарной памяти о части эпизодов.")
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Подсказки терминов")
                .font(.headline)
            ForEach(quickTerms, id: \.0) { item in
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.0)
                        .font(.subheadline.weight(.semibold))
                    Text(item.1)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            if let onOpenFullGlossary {
                Divider()
                Button("Открыть полный словарь") {
                    onOpenFullGlossary()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .padding(12)
        .frame(width: 320, alignment: .leading)
    }
}
