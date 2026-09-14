import SwiftUI
import UIKit

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
                    modeIcon
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

            if candle.isRunning && !candle.isSleepDimmed {
                VStack {
                    Spacer()

                    Button {
                        candle.enterSleepDimmer()
                    } label: {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 15, weight: .light))
                            .foregroundStyle(Color.white.opacity(0.34))
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Dim screen")
                    .accessibilityHint("Dims the screen while the flame keeps running. Tap anywhere to wake it.")
                    .padding(.bottom, 18)
                }
            }

            if candle.isSleepDimmed {
                Color.black
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture {
                        candle.wakeFromSleepDimmer()
                    }
                    .accessibilityAddTraits(.isButton)
                    .accessibilityLabel("Wake screen")
            }
        }
    }

    @ViewBuilder
    private var modeIcon: some View {
        if let imageName = candle.mode.imageName {
            if let path = Bundle.main.path(forResource: imageName, ofType: "png"),
               let image = UIImage(contentsOfFile: path) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 66, height: 66)
            } else {
                fallbackModeIcon
            }
        } else {
            fallbackModeIcon
        }
    }

    private var fallbackModeIcon: some View {
        Image(systemName: candle.mode.iconName)
            .font(.system(size: 34, weight: .medium))
            .foregroundStyle(candle.isRunning ? Color.white : Color.black.opacity(0.78))
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
