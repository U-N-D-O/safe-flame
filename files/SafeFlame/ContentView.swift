import SwiftUI

struct ContentView: View {
    @ObservedObject var candle: CandleController

    var body: some View {
        ZStack {
            Color.black
                .ignoresSafeArea()

            RadialGradient(
                colors: [
                    candle.mode.accentColor.opacity(candle.isRunning ? 0.12 : 0.035),
                    Color.clear
                ],
                center: .center,
                startRadius: 10,
                endRadius: 270
            )
            .ignoresSafeArea()

            HStack(spacing: 22) {
                modeArrow(systemName: "chevron.left", label: "Previous mood") {
                    candle.selectPreviousMode()
                }

                Button {
                    candle.toggle()
                } label: {
                    Image(systemName: candle.mode.iconName)
                        .font(.system(size: 34, weight: .medium))
                        .foregroundStyle(candle.isRunning ? Color.white : Color.black.opacity(0.78))
                        .frame(width: 116, height: 116)
                        .background {
                            Circle()
                                .fill(
                                    candle.isRunning
                                        ? candle.mode.accentColor.opacity(0.72)
                                        : candle.mode.accentColor
                                )
                        }
                        .overlay {
                            Circle()
                                .stroke(Color.white.opacity(0.14), lineWidth: 1)
                        }
                        .shadow(
                            color: candle.mode.accentColor.opacity(candle.isRunning ? 0.42 : 0.18),
                            radius: candle.isRunning ? 34 : 18
                        )
                }
                .buttonStyle(.plain)
                .accessibilityLabel(candle.isRunning ? "Stop \(candle.mode.title)" : "Start \(candle.mode.title)")
                .accessibilityHint("Controls the light and sound")

                modeArrow(systemName: "chevron.right", label: "Next mood") {
                    candle.selectNextMode()
                }
            }
        }
    }

    private func modeArrow(systemName: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 18, weight: .light))
                .foregroundStyle(Color.white.opacity(0.48))
                .frame(width: 36, height: 64)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}
