import AVFoundation
import SwiftUI
import UIKit

enum FlameMode: Int, CaseIterable, Identifiable {
    case fireplace
    case candle
    case moonlight

    var id: Self { self }

    var title: String {
        switch self {
        case .fireplace: return "Fireplace"
        case .candle: return "Candle"
        case .moonlight: return "Moonlight"
        }
    }

    var iconName: String {
        switch self {
        case .fireplace: return "flame.fill"
        case .candle: return "flame"
        case .moonlight: return "moon.stars.fill"
        }
    }

    var imageName: String? {
        switch self {
        case .fireplace: return nil
        case .candle: return "candle"
        case .moonlight: return "moon"
        }
    }

    var soundName: String {
        switch self {
        case .fireplace: return "fireplace"
        case .candle: return "candle"
        case .moonlight: return "nightlight"
        }
    }

    var soundExtension: String {
        return "wav"
    }

    var soundVolume: Float {
        switch self {
        case .fireplace: return 0.34
        case .candle: return 0.18
        case .moonlight: return 0.16
        }
    }

    var defaultTorchLevel: Float {
        switch self {
        case .fireplace: return 0.065
        case .candle: return 0.05
        case .moonlight: return 0.035
        }
    }

    var targetTorchLevels: ClosedRange<Float> {
        switch self {
        case .fireplace: return 0.042...0.095
        case .candle: return 0.04...0.09
        case .moonlight: return 0.022...0.05
        }
    }

    var fadeDurations: ClosedRange<UInt64> {
        switch self {
        case .fireplace: return 900_000_000...1_800_000_000
        case .candle: return 450_000_000...1_100_000_000
        case .moonlight: return 1_800_000_000...3_200_000_000
        }
    }

    var pauses: ClosedRange<UInt64> {
        switch self {
        case .fireplace: return 450_000_000...1_200_000_000
        case .candle: return 180_000_000...650_000_000
        case .moonlight: return 900_000_000...1_800_000_000
        }
    }

    // A real flame is mostly calm, with occasional air movement that causes
    // a quick dip, a small bloom, and then a gentle return to normal.
    var airPulseChance: Double {
        switch self {
        case .fireplace: return 0.055
        case .candle: return 0.12
        case .moonlight: return 0
        }
    }

    var airPulseDipLevels: ClosedRange<Float> {
        switch self {
        case .fireplace: return 0.026...0.043
        case .candle: return 0.034...0.042
        case .moonlight: return 0.022...0.05
        }
    }

    var airPulseBloomLevels: ClosedRange<Float> {
        switch self {
        case .fireplace: return 0.10...0.145
        case .candle: return 0.082...0.105
        case .moonlight: return 0.022...0.05
        }
    }

    var airPulseDipDurations: ClosedRange<UInt64> {
        switch self {
        case .fireplace: return 180_000_000...320_000_000
        case .candle: return 140_000_000...280_000_000
        case .moonlight: return 1_800_000_000...3_200_000_000
        }
    }

    var airPulseBloomDurations: ClosedRange<UInt64> {
        switch self {
        case .fireplace: return 350_000_000...700_000_000
        case .candle: return 280_000_000...600_000_000
        case .moonlight: return 1_800_000_000...3_200_000_000
        }
    }

    var accentColor: Color {
        switch self {
        case .fireplace: return .orange
        case .candle: return Color(red: 1.0, green: 0.48, blue: 0.16)
        case .moonlight: return Color(red: 0.42, green: 0.62, blue: 1.0)
        }
    }
}

@MainActor
final class CandleController: ObservableObject {
    @Published private(set) var isRunning = false
    @Published private(set) var mode: FlameMode = .fireplace
    @Published private(set) var isSleepDimmed = false

    private var torch: AVCaptureDevice?
    private var flickerTask: Task<Void, Never>?
    private var audioEngine: AVAudioEngine?
    private var audioPlayerNode: AVAudioPlayerNode?
    private var savedBrightness: CGFloat?

    init() {
        torch = AVCaptureDevice.default(for: .video)
    }

    deinit {
        flickerTask?.cancel()
        audioPlayerNode?.stop()
        audioEngine?.stop()
    }

    func toggle() {
        isRunning ? stop() : start()
    }

    func toggleSleepDimmer() {
        isSleepDimmed ? wakeFromSleepDimmer() : enterSleepDimmer()
    }

    func enterSleepDimmer() {
        guard isRunning, !isSleepDimmed else { return }
        savedBrightness = UIScreen.main.brightness
        UIScreen.main.brightness = 0.01
        isSleepDimmed = true
        UIApplication.shared.isIdleTimerDisabled = true
    }

    func wakeFromSleepDimmer() {
        guard isSleepDimmed else { return }
        UIScreen.main.brightness = savedBrightness ?? 0.5
        savedBrightness = nil
        isSleepDimmed = false
    }

    func selectPreviousMode() {
        let count = FlameMode.allCases.count
        let index = (mode.rawValue - 1 + count) % count
        selectMode(FlameMode(rawValue: index) ?? .fireplace)
    }

    func selectNextMode() {
        let count = FlameMode.allCases.count
        let index = (mode.rawValue + 1) % count
        selectMode(FlameMode(rawValue: index) ?? .fireplace)
    }

    private func selectMode(_ newMode: FlameMode) {
        guard newMode != mode else { return }
        mode = newMode

        guard isRunning else { return }
        flickerTask?.cancel()
        flickerTask = nil
        try? setTorchLevel(mode.defaultTorchLevel)
        startFlickerLoopIfNeeded()
        playAudio()
    }

    func start() {
        guard !isRunning else { return }
        guard let torch, torch.hasTorch, torch.isTorchAvailable else { return }

        do {
            try setTorchLevel(mode.defaultTorchLevel)
        } catch {
            return
        }

        isRunning = true
        UIApplication.shared.isIdleTimerDisabled = true
        startFlickerLoopIfNeeded()

        playAudio()
    }

    func stop() {
        guard isRunning || flickerTask != nil else { return }

        isRunning = false
        wakeFromSleepDimmer()
        flickerTask?.cancel()
        flickerTask = nil
        stopAudio()
        UIApplication.shared.isIdleTimerDisabled = false

        if let torch {
            do {
                try torch.lockForConfiguration()
                defer { torch.unlockForConfiguration() }
                torch.torchMode = .off
            } catch {
                // The torch may already be unavailable or cooling down.
            }
        }

        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    func scenePhaseChanged(to phase: ScenePhase) {
        guard isRunning else { return }

        if phase == .active {
            // iOS may suspend the flicker task while the phone is locked.
            // Resume it automatically when the app becomes visible again.
            startFlickerLoopIfNeeded()
        }
    }

    private func startFlickerLoopIfNeeded() {
        guard flickerTask == nil, isRunning else { return }
        let selectedMode = mode

        flickerTask = Task { [weak self] in
            guard let self else { return }

            while !Task.isCancelled {
                if Double.random(in: 0...1) < selectedMode.airPulseChance {
                    // A small gust: dip quickly, bloom briefly, then settle.
                    let dip = Float.random(in: selectedMode.airPulseDipLevels)
                    let bloom = Float.random(in: selectedMode.airPulseBloomLevels)
                    await self.fadeTorch(
                        to: dip,
                        over: UInt64.random(in: selectedMode.airPulseDipDurations)
                    )
                    await self.fadeTorch(
                        to: bloom,
                        over: UInt64.random(in: selectedMode.airPulseBloomDurations)
                    )
                }

                let target = Float.random(in: selectedMode.targetTorchLevels)
                let duration = UInt64.random(in: selectedMode.fadeDurations)
                await self.fadeTorch(to: target, over: duration)

                let pause = UInt64.random(in: selectedMode.pauses)
                try? await Task.sleep(nanoseconds: pause)
            }
        }
    }

    private func fadeTorch(to target: Float, over duration: UInt64) async {
        let steps = max(1, Int(duration / 100_000_000))
        let stepDuration = duration / UInt64(steps)
        let startingLevel = torch?.torchLevel ?? 0.065

        for step in 1...steps {
            guard !Task.isCancelled else { return }
            let progress = Float(step) / Float(steps)
            let eased = progress * progress * (3 - 2 * progress)
            let level = startingLevel + ((target - startingLevel) * eased)

            try? setTorchLevel(level)
            try? await Task.sleep(nanoseconds: stepDuration)
        }
    }

    private func playAudio() {
        stopAudio()

        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try session.setActive(true)

            guard let url = Bundle.main.url(forResource: mode.soundName, withExtension: mode.soundExtension) else {
                throw CandleError.audioMissing
            }

            let file = try AVAudioFile(forReading: url)
            guard let buffer = AVAudioPCMBuffer(
                pcmFormat: file.processingFormat,
                frameCapacity: AVAudioFrameCount(file.length)
            ) else {
                throw CandleError.audioBufferUnavailable
            }
            try file.read(into: buffer)

            let engine = AVAudioEngine()
            let playerNode = AVAudioPlayerNode()
            engine.attach(playerNode)
            engine.connect(playerNode, to: engine.mainMixerNode, format: buffer.format)
            engine.mainMixerNode.outputVolume = mode.soundVolume

            // Buffer looping is scheduled by AVAudioEngine at the sample boundary,
            // avoiding the tiny restart gap that AVAudioPlayer can introduce.
            playerNode.scheduleBuffer(buffer, at: nil, options: .loops)
            try engine.start()
            playerNode.play()
            audioEngine = engine
            audioPlayerNode = playerNode
        } catch {
            // The torch remains useful if a bundled sound cannot be loaded.
            stopAudio()
        }
    }

    private func stopAudio() {
        audioPlayerNode?.stop()
        audioEngine?.stop()
        audioPlayerNode = nil
        audioEngine = nil
    }

    private func setTorchLevel(_ level: Float) throws {
        guard let torch else { return }
        try setTorchLevel(level, on: torch)
    }

    private func setTorchLevel(_ level: Float, on torch: AVCaptureDevice) throws {
        guard torch.hasTorch, torch.isTorchAvailable else { return }
        try torch.lockForConfiguration()
        defer { torch.unlockForConfiguration() }
        try torch.setTorchModeOn(level: max(0, min(level, 1)))
    }
}

private enum CandleError: Error {
    case audioMissing
    case audioBufferUnavailable
}
