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
                    Color(red: 0.12, green: 0.16, blue: 0.23).opacity(candle.isRunning ? 0.22 : 0.12),
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
                                .fill(Color(red: 0.075, green: 0.105, blue: 0.16))
                                .overlay {
                                    Circle()
                                        .fill(
                                            LinearGradient(
                                                colors: [
                                                    Color.white.opacity(0.11),
                                                    Color.clear,
                                                    Color.black.opacity(0.22)
                                                ],
                                                startPoint: .topLeading,
                                                endPoint: .bottomTrailing
                                            )
                                        )
                                }
                        }
                        .overlay {
                            Circle()
                                .stroke(Color.white.opacity(0.10), lineWidth: 1)
                                .overlay {
                                    Circle()
                                        .stroke(
                                            candle.isRunning
                                                ? candle.mode.accentColor.opacity(0.42)
                                                : Color.white.opacity(0.05),
                                            lineWidth: 1.5
                                        )
                                        .padding(3)
                                }
                        }
                        .shadow(
                            color: Color.black.opacity(0.82),
                            radius: 16,
                            x: 9,
                            y: 10
                        )
                        .shadow(
                            color: Color.white.opacity(0.07),
                            radius: 11,
                            x: -7,
                            y: -7
                        )
                        .shadow(
                            color: candle.mode.accentColor.opacity(candle.isRunning ? 0.22 : 0.06),
                            radius: candle.isRunning ? 24 : 12
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
                            .foregroundStyle(Color.white.opacity(0.42))
                            .frame(width: 44, height: 44)
                            .background {
                                Circle()
                                    .fill(Color(red: 0.075, green: 0.105, blue: 0.16))
                            }
                            .overlay {
                                Circle()
                                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
                            }
                            .shadow(color: Color.black.opacity(0.7), radius: 8, x: 5, y: 6)
                            .shadow(color: Color.white.opacity(0.05), radius: 6, x: -4, y: -4)
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
            .foregroundStyle(Color.white.opacity(candle.isRunning ? 0.96 : 0.78))
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
