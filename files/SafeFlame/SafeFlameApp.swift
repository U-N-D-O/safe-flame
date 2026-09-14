import SwiftUI

@main
struct SafeFlameApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var candle = CandleController()

    var body: some Scene {
        WindowGroup {
            ContentView(candle: candle)
                .preferredColorScheme(.dark)
                .onChange(of: scenePhase) { phase in
                    candle.scenePhaseChanged(to: phase)
                }
        }
    }
}
