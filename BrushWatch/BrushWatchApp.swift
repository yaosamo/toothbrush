import SwiftUI

@main
struct BrushWatchApp: App {
    @StateObject private var ble = BLEManager()
    @StateObject private var store = AchievementStore()

    var body: some Scene {
        WindowGroup {
            HomeView()
                .environmentObject(ble)
                .environmentObject(store)
                .onAppear { UIApplication.shared.isIdleTimerDisabled = true }
        }
    }
}
