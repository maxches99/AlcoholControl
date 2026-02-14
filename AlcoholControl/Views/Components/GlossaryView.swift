import SwiftUI

struct GlossaryView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                term(L10n.tr("BAC (примерно)"), L10n.tr("Оценка концентрации алкоголя в крови. Это модель, а не медицинский прибор."))
                term(L10n.tr("Пик BAC"), L10n.tr("Максимальное оценочное значение BAC за сессию."))
                term(L10n.tr("До ~0.00"), L10n.tr("Примерное время, когда по модели BAC опустится до 0."))
                term(L10n.tr("Риск тяжелого утра"), L10n.tr("Эвристика, учитывающая BAC, темп, воду, длительность и приемы пищи."))
                term(L10n.tr("Риск провалов памяти"), L10n.tr("Эвристика вероятности, что часть эпизодов может плохо запомниться."))
                term(L10n.tr("Водный баланс"), L10n.tr("Оценка: сколько воды уже выпито относительно целевого объема на сессию."))
                term(L10n.tr("Цель воды"), L10n.tr("Приблизительный ориентир по воде с учетом веса, длительности и объема алкоголя."))
                term(L10n.tr("Прием пищи"), L10n.tr("Еда может частично снижать остроту состояния и риски, особенно при регулярном приеме."))
                term(L10n.tr("Стандартный дринк"), L10n.tr("Условная порция алкоголя (~14 г этанола) для расчетов темпа и нагрузки."))
                term(L10n.tr("Персональный порог"), L10n.tr("Индивидуальный ориентир риска, рассчитанный по вашим предыдущим сессиям."))
                term(L10n.tr("Уверенность модели"), L10n.tr("Показывает, насколько надежна оценка по текущему набору данных (вес, вода, еда, полнота логов)."))
                term(L10n.tr("События риска"), L10n.tr("Конкретные эпизоды в сессии, которые увеличили риск: быстрый темп, крепкие напитки, дефицит воды."))
                term(L10n.tr("План перед началом"), L10n.tr("План до начала вечера: лимит алкоголя, цель воды и ориентир времени завершения."))
                term(L10n.tr("Режим безопасности"), L10n.tr("Более осторожный режим: ранние напоминания о паузах, воде и быстром переходе к действиям безопасности."))
                term(L10n.tr("Кризисный режим"), L10n.tr("Режим срочной помощи: быстрый доступ к экстренным действиям и контакту доверенного человека."))
                term(L10n.tr("Умные напоминания"), L10n.tr("Напоминания, которые учитывают текущий риск, а не только фиксированный интервал."))
                term(L10n.tr("План восстановления (2-4ч)"), L10n.tr("Короткий персонализированный план восстановления после сессии с отметкой выполненных шагов."))
                term(L10n.tr("Паттерны триггеров"), L10n.tr("Повторяющиеся дни, время и типы напитков, которые чаще связаны с тяжелым утром."))
                term(L10n.tr("Недельные цели harm-reduction"), L10n.tr("Недельные лимиты по рискам и цель гидратации для контроля прогресса."))
                term(L10n.tr("Серия"), L10n.tr("Серия сессий подряд, где вы держите полезную привычку, например воду или прием пищи."))
                term(L10n.tr("Тренд"), L10n.tr("Направление изменения показателя по истории: улучшается, ухудшается или стабильно."))
            }
            .navigationTitle(L10n.tr("Термины и пояснения"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.tr("Закрыть")) { dismiss() }
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
                Text(L10n.tr("Быстрые подсказки"))
                    .font(.headline)
                Text(L10n.tr("Короткие пояснения к ключевым метрикам."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            ForEach(quickTerms, id: \.title) { item in
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Image(systemName: item.icon)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Text(L10n.tr(item.title))
                            .font(.subheadline.weight(.semibold))
                    }
                    Text(L10n.tr(item.description))
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
                    Label(L10n.tr("Открыть полный словарь"), systemImage: "text.book.closed")
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
