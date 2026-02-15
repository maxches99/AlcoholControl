//
//  AlcoholControlApp.swift
//  AlcoholControl
//
//  Created by Maxim Chesnikov on 11.02.2026.
//

import SwiftUI
import SwiftData

@main
struct AlcoholControlApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var appState = AppState()
    @AppStorage("selectedAppLanguage") private var selectedAppLanguage = AppLanguage.system.rawValue

    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            UserProfile.self,
            Session.self,
            DrinkEntry.self,
            WaterEntry.self,
            MealEntry.self,
            MorningCheckIn.self,
            HealthDailySnapshot.self,
            RiskModelRun.self,
            PersonalPatternRun.self
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(PurchaseService.shared)
                .environmentObject(appState)
                .environment(\.locale, resolvedLanguage.locale)
                .task {
                    appDelegate.appState = appState
                    await PurchaseService.shared.restore()
                }
        }
        .modelContainer(sharedModelContainer)
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                Task { await PurchaseService.shared.restore() }
            }
        }
    }

    private var resolvedLanguage: AppLanguage {
        AppLanguage(rawValue: selectedAppLanguage) ?? .system
    }
}
