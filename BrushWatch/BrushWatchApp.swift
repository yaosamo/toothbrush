import SwiftUI

@main
struct BrushWatchApp: App {
    @StateObject private var ble = BLEManager()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(ble)
                .onAppear { UIApplication.shared.isIdleTimerDisabled = true }
        }
    }
}
