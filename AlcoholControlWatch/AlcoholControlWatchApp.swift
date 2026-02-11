import SwiftUI

@main
struct AlcoholControlWatchApp: App {
    @StateObject private var store = WatchSnapshotStore()

    var body: some Scene {
        WindowGroup {
            WatchDashboardView()
                .environmentObject(store)
                .onAppear {
                    store.refresh()
                }
        }
    }
}
