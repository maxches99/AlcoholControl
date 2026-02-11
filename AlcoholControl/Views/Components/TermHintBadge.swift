import SwiftUI

struct TermHintBadge: View {
    let term: String
    let definition: String

    @State private var showingHint = false
    @State private var autoHideTask: Task<Void, Never>?

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Button {
                withAnimation(.easeInOut(duration: 0.16)) {
                    showingHint.toggle()
                }
                if showingHint {
                    scheduleAutoHide()
                } else {
                    autoHideTask?.cancel()
                }
            } label: {
                Image(systemName: "questionmark.circle")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L10n.format("Подсказка: %@", term))

            if showingHint {
                VStack(alignment: .leading, spacing: 8) {
                    Text(term)
                        .font(.headline)
                    Text(definition)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .padding(10)
                .frame(width: 230, alignment: .leading)
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .shadow(radius: 8, y: 4)
                .offset(x: -8, y: 28)
                .transition(.scale(scale: 0.95, anchor: .topTrailing).combined(with: .opacity))
                .zIndex(2)
            }
        }
        .onDisappear {
            autoHideTask?.cancel()
        }
    }

    private func scheduleAutoHide() {
        autoHideTask?.cancel()
        autoHideTask = Task {
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                withAnimation(.easeInOut(duration: 0.16)) {
                    showingHint = false
                }
            }
        }
    }
}
