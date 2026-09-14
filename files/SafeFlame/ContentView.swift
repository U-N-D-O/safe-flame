import SwiftUI

struct ContentView: View {
    @ObservedObject var candle: CandleController

    var body: some View {
        ZStack {
            Color.black
                .ignoresSafeArea()

            RadialGradient(
                colors: [
                    Color.orange.opacity(candle.isRunning ? 0.12 : 0.035),
                    Color.clear
                ],
                center: .center,
                startRadius: 10,
                endRadius: 270
            )
            .ignoresSafeArea()

            Button {
                candle.toggle()
            } label: {
                Image(systemName: candle.isRunning ? "stop.fill" : "flame.fill")
                    .font(.system(size: 34, weight: .medium))
                    .foregroundStyle(candle.isRunning ? Color.white : Color.black.opacity(0.78))
                    .frame(width: 116, height: 116)
                    .background {
                        Circle()
                            .fill(
                                candle.isRunning
                                    ? Color(red: 0.58, green: 0.16, blue: 0.05)
                                    : Color(red: 1.0, green: 0.56, blue: 0.12)
                            )
                    }
                    .overlay {
                        Circle()
                            .stroke(Color.white.opacity(0.14), lineWidth: 1)
                    }
                    .shadow(
                        color: Color.orange.opacity(candle.isRunning ? 0.42 : 0.18),
                        radius: candle.isRunning ? 34 : 18
                    )
            }
            .buttonStyle(.plain)
            .accessibilityLabel(candle.isRunning ? "Stop candle" : "Start candle")
            .accessibilityHint("Controls the dim flickering light and fireplace sound")
        }
    }
}
