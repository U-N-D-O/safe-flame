import AVFoundation
import SwiftUI

@MainActor
final class CandleController: ObservableObject {
    @Published private(set) var isRunning = false

    private var torch: AVCaptureDevice?
    private var flickerTask: Task<Void, Never>?
    private var audioPlayer: AVAudioPlayer?
    private var audioConfigured = false

    init() {
        torch = AVCaptureDevice.default(for: .video)
    }

    deinit {
        flickerTask?.cancel()
    }

    func toggle() {
        isRunning ? stop() : start()
    }

    func start() {
        guard !isRunning else { return }
        guard let torch, torch.hasTorch, torch.isTorchAvailable else { return }

        do {
            try configureAudio()
            try setTorchLevel(0.065)
            audioPlayer?.currentTime = 0
            audioPlayer?.play()
        } catch {
            return
        }

        isRunning = true
        UIApplication.shared.isIdleTimerDisabled = true
        startFlickerLoopIfNeeded()
    }

    func stop() {
        guard isRunning || flickerTask != nil else { return }

        flickerTask?.cancel()
        flickerTask = nil
        audioPlayer?.stop()
        isRunning = false
        UIApplication.shared.isIdleTimerDisabled = false

        if let torch {
            try? setTorchLevel(0, on: torch)
            try? torch.lockForConfiguration()
            torch.torchMode = .off
            torch.unlockForConfiguration()
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

        flickerTask = Task { [weak self] in
            guard let self else { return }

            while !Task.isCancelled {
                let target = Float.random(in: 0.042...0.095)
                let duration = UInt64.random(in: 900...1800) * 1_000_000
                await self.fadeTorch(to: target, over: duration)

                let pause = UInt64.random(in: 450...1200) * 1_000_000
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

    private func configureAudio() throws {
        guard !audioConfigured else { return }

        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
        try session.setActive(true)

        guard let url = Bundle.main.url(forResource: "fireplace", withExtension: "wav") else {
            throw CandleError.audioMissing
        }

        let player = try AVAudioPlayer(contentsOf: url)
        player.numberOfLoops = -1
        player.volume = 0.34
        player.prepareToPlay()
        audioPlayer = player
        audioConfigured = true
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
}
