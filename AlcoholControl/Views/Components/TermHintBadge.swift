import SwiftUI

struct TermHintOverlayState: Equatable, Identifiable {
    let id: String
    let term: String
    let definition: String
}

struct TermHintAnchorPreferenceKey: PreferenceKey {
    static var defaultValue: [String: Anchor<CGRect>] = [:]

    static func reduce(value: inout [String: Anchor<CGRect>], nextValue: () -> [String: Anchor<CGRect>]) {
        value.merge(nextValue(), uniquingKeysWith: { _, latest in latest })
    }
}

struct TermHintBadge: View {
    let term: String
    let definition: String
    @Binding var activeHint: TermHintOverlayState?

    private var hintID: String { "\(term)|\(definition)" }
    private var isActive: Bool { activeHint?.id == hintID }

    var body: some View {
        Button {
            withAnimation(.spring(response: 0.26, dampingFraction: 0.92)) {
                if isActive {
                    activeHint = nil
                } else {
                    activeHint = TermHintOverlayState(id: hintID, term: term, definition: definition)
                }
            }
        } label: {
            Image(systemName: isActive ? "questionmark.circle.fill" : "questionmark.circle")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(isActive ? Color.accentColor : Color.secondary)
                .frame(width: 28, height: 28)
                .background(isActive ? Color.accentColor.opacity(0.14) : .clear, in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(L10n.format("Подсказка: %@", term))
        .anchorPreference(key: TermHintAnchorPreferenceKey.self, value: .bounds) { [hintID: $0] }
    }
}

struct TermHintOverlayCard: View {
    let hint: TermHintOverlayState
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 8) {
                Text(hint.term)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                Button {
                    withAnimation(.easeInOut(duration: 0.16)) {
                        onClose()
                    }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Закрыть подсказку")
            }
            Text(hint.definition)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(width: 260, alignment: .leading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(.white.opacity(0.24))
        )
        .shadow(color: .black.opacity(0.16), radius: 14, y: 8)
    }
}
