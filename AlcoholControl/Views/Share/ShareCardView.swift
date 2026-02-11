import SwiftUI
import SwiftData
import UIKit

private enum ShareTemplate: String, CaseIterable, Identifiable {
    case waterBreak
    case stopNow

    var id: String { rawValue }

    var title: String {
        switch self {
        case .waterBreak: return L10n.tr("Водный перерыв")
        case .stopNow: return L10n.tr("Я стопаюсь")
        }
    }

    var subtitle: String {
        switch self {
        case .waterBreak: return L10n.tr("Беру паузу и воду")
        case .stopNow: return L10n.tr("На сегодня достаточно")
        }
    }

    var colors: [Color] {
        switch self {
        case .waterBreak:
            return [Color(red: 0.1, green: 0.45, blue: 0.8), Color(red: 0.0, green: 0.72, blue: 0.7)]
        case .stopNow:
            return [Color(red: 0.95, green: 0.45, blue: 0.18), Color(red: 0.93, green: 0.74, blue: 0.16)]
        }
    }
}

struct ShareCardView: View {
    @Query private var profiles: [UserProfile]

    let session: Session

    @State private var selectedTemplate: ShareTemplate = .waterBreak
    @State private var hideBAC = true
    @State private var showingShare = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Picker("Шаблон", selection: $selectedTemplate) {
                    ForEach(ShareTemplate.allCases) { template in
                        Text(template.title).tag(template)
                    }
                }
                .pickerStyle(.segmented)

                Toggle("Скрыть числа BAC", isOn: $hideBAC)

                shareCardContent
                    .frame(height: 220)

                Button("Share") {
                    showingShare = true
                }
                .buttonStyle(.borderedProminent)

                Text("Шаринг не показывает рекорды или сравнение между людьми.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding()
        }
        .navigationTitle("Share Card")
        .task {
            if let profile = profiles.first {
                hideBAC = profile.hideBACInSharing
            }
        }
        .sheet(isPresented: $showingShare) {
            let renderer = ImageRenderer(content: renderedCard)
            if let image = renderer.uiImage {
                ActivityView(activityItems: [image])
            }
        }
    }

    private var shareCardContent: some View {
        renderedCard
    }

    private var renderedCard: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 20)
                .fill(LinearGradient(colors: selectedTemplate.colors, startPoint: .topLeading, endPoint: .bottomTrailing))

            VStack(alignment: .leading, spacing: 8) {
                Text(selectedTemplate.title)
                    .font(.title2.bold())
                Text(selectedTemplate.subtitle)
                    .font(.headline)

                if !hideBAC {
                    Text("BAC (примерно): \(String(format: "%.3f", session.cachedPeakBAC))")
                        .font(.subheadline)
                }

                Text(session.startAt, format: .dateTime.day().month().year())
                    .font(.footnote)

                Spacer()

                Text("Alcohol Control · оценка приблизительная")
                    .font(.caption)
            }
            .foregroundStyle(.white)
            .padding(18)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }
}

struct ActivityView: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
