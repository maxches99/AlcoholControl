import SwiftUI

struct AgeGateView: View {
    var onApproved: () -> Void

    @State private var underage = false

    var body: some View {
        VStack(spacing: 20) {
            if underage {
                Text("Недоступно")
                    .font(.title2)
                Text("Приложение доступно только для совершеннолетних по локальным правилам.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                Button("Проверить снова") {
                    underage = false
                }
                .buttonStyle(.bordered)
            } else {
                Text("Подтверждение возраста")
                    .font(.title2)
                Text("18+ или локальный минимум. Оценки BAC приблизительные и не подходят для решения, можно ли водить.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                Button("Мне 18+ / допустимый возраст") {
                    onApproved()
                }
                .buttonStyle(.borderedProminent)
                .accessibilityLabel("Подтвердить возраст")

                Button("Мне меньше допустимого возраста") {
                    underage = true
                }
                .foregroundStyle(.red)
                .accessibilityLabel("Отказать в подтверждении возраста")
            }
        }
        .padding()
    }
}
