import SwiftUI
import SwiftData

struct ContentView: View {
    @EnvironmentObject private var appState: AppState
    @AppStorage("hasPassedAgeGate") private var hasPassedAgeGate = false
    @AppStorage("didFinishOnboarding") private var didFinishOnboarding = false

    var body: some View {
        Group {
            if !hasPassedAgeGate {
                AgeGateView {
                    hasPassedAgeGate = true
                }
            } else if !didFinishOnboarding {
                OnboardingView()
            } else {
                MainTabs(selectedTab: $appState.selectedTab)
            }
        }
    }
}

struct MainTabs: View {
    @Binding var selectedTab: AppTab

    var body: some View {
        TabView(selection: $selectedTab) {
            TodayView()
                .tag(AppTab.today)
                .tabItem {
                    Label("Сегодня", systemImage: "sun.max")
                }
            HistoryView()
                .tag(AppTab.history)
                .tabItem {
                    Label("История", systemImage: "clock")
                }
            AnalyticsView()
                .tag(AppTab.analytics)
                .tabItem {
                    Label("Аналитика", systemImage: "chart.bar")
                }
            SettingsView()
                .tag(AppTab.settings)
                .tabItem {
                    Label("Настройки", systemImage: "gearshape")
                }
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(AppState())
        .modelContainer(
            for: [
                UserProfile.self,
                Session.self,
                DrinkEntry.self,
                WaterEntry.self,
                MealEntry.self,
                MorningCheckIn.self,
                HealthDailySnapshot.self,
                RiskModelRun.self
            ],
            inMemory: true
        )
}
