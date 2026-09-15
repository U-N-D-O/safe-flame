import AVFoundation
import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private let safeFlame = SafeFlamePlatformController()

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)

    let channel = FlutterMethodChannel(
      name: "com.qila.safeflame/control",
      binaryMessenger: engineBridge.applicationRegistrar.messenger()
    )
    channel.setMethodCallHandler { [weak self] call, result in
      self?.safeFlame.handle(call, result: result)
    }
  }
}

/// The iOS-only hardware/audio half of the shared Flutter app.
/// Android has the equivalent implementation in FlameService.java.
private final class SafeFlamePlatformController: NSObject {
  private var torch: AVCaptureDevice?
  private var flickerTimer: Timer?
  private var motionStartedAt: TimeInterval = 0
  private var motionPhase: Double = 0
  private var gustStartedAt: Double = 0
  private var gustDuration: Double = 1
  private var gustDirection: Double = 1
  private var audioEngine: AVAudioEngine?
  private var audioPlayerNode: AVAudioPlayerNode?
  private var mode = 0
  private(set) var running = false

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "isRunning":
      result(running)
    case "start":
      let requestedMode = (call.arguments as? [String: Any])?["mode"] as? Int ?? 0
      result(start(mode: requestedMode))
    case "stop":
      stop()
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func start(mode: Int) -> Bool {
    guard !running else { return true }
    torch = torch ?? AVCaptureDevice.default(for: .video)
    guard let torch, torch.hasTorch, torch.isTorchAvailable else { return false }

    self.mode = max(0, min(mode, 2))
    let initialTorchLevel = initialLevel()
    do {
      try setTorch(initialTorchLevel)
    } catch {
      return false
    }

    running = true
    UIApplication.shared.isIdleTimerDisabled = true
    startAudio()
    scheduleFlicker()
    return true
  }

  private func stop() {
    guard running || flickerTimer != nil else { return }
    running = false
    flickerTimer?.invalidate()
    flickerTimer = nil
    stopAudio()
    UIApplication.shared.isIdleTimerDisabled = false

    guard let torch else { return }
    do {
      try torch.lockForConfiguration()
      torch.torchMode = .off
      torch.unlockForConfiguration()
    } catch {
      // The torch may already be unavailable or cooling down.
    }
    try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
  }

  private func scheduleFlicker() {
    guard running else { return }
    motionStartedAt = ProcessInfo.processInfo.systemUptime
    motionPhase = Double.random(in: 0...(2 * .pi))
    gustStartedAt = Double.random(in: 15...30)
    gustDuration = Double.random(in: 1.8...3.2)
    gustDirection = 1
    let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
      self?.flicker()
    }
    flickerTimer = timer
    RunLoop.main.add(timer, forMode: .common)
  }

  private func flicker() {
    guard running else { return }
    let elapsed = ProcessInfo.processInfo.systemUptime - motionStartedAt
    let speed = mode == 2 ? 0.32 : mode == 1 ? 0.28 : 0.38
    let t = elapsed * speed
    let p = motionPhase
    // Overlapping, phase-modulated waves never wait at a target brightness.
    // Keep this normalized motion identical to FlameService on Android.
    let drift = 0.55 * sin(1.17 * t + p + 0.32 * sin(0.37 * t + p))
      + 0.30 * sin(2.71 * t + 1.7 * p + 0.22 * sin(0.61 * t))
      + 0.15 * sin(5.13 * t + 0.7 * p)
    if elapsed > gustStartedAt + gustDuration {
      gustStartedAt = elapsed + Double.random(in: 15...30)
      gustDuration = Double.random(in: 1.8...3.2)
      gustDirection = Bool.random() ? 1 : -1
    }
    let progress = max(0, min(1, (elapsed - gustStartedAt) / gustDuration))
    // Smooth pulse has zero velocity at both ends, including when rescheduled.
    let gustStrength = mode == 2 ? 0.0 : mode == 1 ? 0.14 : 0.18
    let pulse = gustStrength * pow(sin(.pi * progress), 4)
    // Mostly a quiet glow: retain only a small part of the full drift range.
    let driftStrength = mode == 2 ? 1.0 : mode == 1 ? 0.18 : 0.24
    let motion = (1 - pulse) * driftStrength * drift + pulse * gustDirection
    let minimum: Double = mode == 2 ? 0.022 : mode == 1 ? 0.040 : 0.042
    let maximum: Double = mode == 2 ? 0.050 : mode == 1 ? 0.090 : 0.095
    let target = minimum + (maximum - minimum) * (0.5 + 0.5 * motion)
    let ramp = min(1, elapsed / 1.2)
    let blend = ramp * ramp * (3 - 2 * ramp)
    let initial = Double(initialLevel())
    try? setTorch(Float(initial + (target - initial) * blend))
  }

  private func initialLevel() -> Float {
    switch mode {
    case 1: return 0.05
    case 2: return 0.035
    default: return 0.065
    }
  }

  private func setTorch(_ level: Float) throws {
    guard let torch, torch.hasTorch, torch.isTorchAvailable else { return }
    try torch.lockForConfiguration()
    defer { torch.unlockForConfiguration() }
    try torch.setTorchModeOn(level: max(0.01, min(level, 1.0)))
  }

  private func startAudio() {
    stopAudio()
    let soundName = mode == 1 ? "candle" : mode == 2 ? "nightlight" : "fireplace"
    do {
      let session = AVAudioSession.sharedInstance()
      try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
      try session.setActive(true)

      // Flutter's App.framework embeds assets at its root, not in a native
      // framework Resources directory. Address the packaged file directly.
      let url = Bundle.main.bundleURL.appendingPathComponent(
        "Frameworks/App.framework/flutter_assets/files/SafeFlame/Resources/\(soundName).wav"
      )
      guard FileManager.default.fileExists(atPath: url.path) else {
        throw NSError(domain: "SafeFlame.Audio", code: 1,
                      userInfo: [NSLocalizedDescriptionKey: "Missing bundled audio: \(soundName)"])
      }

      let file = try AVAudioFile(forReading: url)
      guard let buffer = AVAudioPCMBuffer(
        pcmFormat: file.processingFormat,
        frameCapacity: AVAudioFrameCount(file.length)
      ) else { return }
      try file.read(into: buffer)

      let engine = AVAudioEngine()
      let player = AVAudioPlayerNode()
      engine.attach(player)
      engine.connect(player, to: engine.mainMixerNode, format: buffer.format)
      engine.mainMixerNode.outputVolume = mode == 0 ? 0.34 : mode == 1 ? 0.18 : 0.16
      player.scheduleBuffer(buffer, at: nil, options: .loops)
      try engine.start()
      player.play()
      audioEngine = engine
      audioPlayerNode = player
    } catch {
      NSLog("Safe Flame audio failed: %@", error.localizedDescription)
      stopAudio()
    }
  }

  private func stopAudio() {
    audioPlayerNode?.stop()
    audioEngine?.stop()
    audioPlayerNode = nil
    audioEngine = nil
  }

  deinit {
    stop()
  }
}
