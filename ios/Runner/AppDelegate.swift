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
  private var lastMotionTime: TimeInterval = 0
  private var torchLevel: Double = 0
  private var flameMotion = FlameEventMotion(mode: 0)
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

    torchLevel = Double(initialTorchLevel)
    flameMotion = FlameEventMotion(mode: self.mode)
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
    lastMotionTime = ProcessInfo.processInfo.systemUptime
    let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
      self?.flicker()
    }
    flickerTimer = timer
    RunLoop.main.add(timer, forMode: .common)
  }

  private func flicker() {
    guard running else { return }
    let now = ProcessInfo.processInfo.systemUptime
    let delta = min(0.1, max(1.0 / 120.0, now - lastMotionTime))
    lastMotionTime = now

    let motion = flameMotion.value(delta: delta)
    let base: Double = mode == 2 ? 0.0288 : mode == 1 ? 0.052 : 0.0548
    let minimum: Double = (mode == 2 ? 0.022 : mode == 1 ? 0.040 : 0.042) * 0.8
    let maximum: Double = (mode == 2 ? 0.050 : mode == 1 ? 0.090 : 0.095) * 0.8
    torchLevel = max(minimum, min(maximum, base + motion))
    try? setTorch(Float(torchLevel))
  }

  private func initialLevel() -> Float {
    switch mode {
    case 1: return 0.052
    case 2: return 0.0288
    default: return 0.0548
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

/// Short, irregular air movements. Each event nudges the light and then
/// decays back toward zero, so the flame returns to its base instead of
/// following a long wave or holding at a peak.
private final class FlameEventMotion {
  private let mode: Int
  private let eventInterval: ClosedRange<Double>
  private let recovery: Double
  private let regularKick: ClosedRange<Double>
  private let rareKick: ClosedRange<Double>
  private let rareInterval: ClosedRange<Double>
  private let maximumOffset: Double
  private var time = 0.0
  private var nextEvent: Double
  private var nextRareEvent: Double
  private var desiredOffset = 0.0
  private var currentOffset = 0.0
  private var currentVelocity = 0.0
  private var candleStage = 0
  private var candleStageElapsed = 0.0
  private var candleStageDuration = 0.1
  private var candleStageFrom = 0.0
  private var candleStageTo = 0.0
  private var candleDip = 0.0
  private var candleRise = 0.0

  init(mode: Int) {
    self.mode = mode
    switch mode {
    case 1: // Candle: small, sparse, quick disturbances.
      eventInterval = 0.55...1.80
      recovery = 0.34
      regularKick = -0.003...0.003
      rareKick = -0.012...0.012
      rareInterval = 4.0...9.0
      maximumOffset = 0.020
    case 2: // Nightlight: nearly still.
      eventInterval = 1.40...3.20
      recovery = 0.70
      regularKick = -0.0015...0.0015
      rareKick = -0.004...0.004
      rareInterval = 8.0...16.0
      maximumOffset = 0.0112
    default: // Fireplace: more frequent and longer, with larger movement.
      eventInterval = 0.22...0.75
      recovery = 0.78
      regularKick = -0.008...0.008
      rareKick = -0.020...0.020
      rareInterval = 1.8...4.8
      maximumOffset = 0.0212
    }
    nextEvent = Double.random(in: eventInterval)
    nextRareEvent = Double.random(in: rareInterval)
  }

  func value(delta: Double) -> Double {
    if mode == 1 {
      return candleValue(delta: delta)
    }

    time += delta
    if time >= nextEvent {
      desiredOffset += Double.random(in: regularKick)
      nextEvent = time + Double.random(in: eventInterval)
    }
    if time >= nextRareEvent {
      desiredOffset += Double.random(in: rareKick)
      nextRareEvent = time + Double.random(in: rareInterval)
    }
    desiredOffset *= exp(-delta / recovery)
    let response = 18.0
    let damping = 8.0
    let acceleration = (desiredOffset - currentOffset) * response - currentVelocity * damping
    currentVelocity += acceleration * delta
    currentOffset += currentVelocity * delta
    currentOffset = max(-maximumOffset, min(maximumOffset, currentOffset))
    return currentOffset
  }

  private func candleValue(delta: Double) -> Double {
    time += delta
    guard candleStage != 0 else {
      if time >= nextEvent {
        candleDip = Double.random(in: 0.008...0.014)
        candleRise = Double.random(in: 0.005...0.010)
        candleStage = 1
        candleStageElapsed = 0
        candleStageFrom = 0
        candleStageTo = -candleDip
        candleStageDuration = Double.random(in: 0.08...0.15)
      }
      return 0
    }

    candleStageElapsed += delta
    let progress = min(1.0, candleStageElapsed / candleStageDuration)
    let eased = progress * progress * (3.0 - 2.0 * progress)
    currentOffset = candleStageFrom + (candleStageTo - candleStageFrom) * eased

    if progress >= 1.0 {
      switch candleStage {
      case 1: // Return to the exact baseline after the brief dim.
        candleStage = 2
        candleStageFrom = -candleDip
        candleStageTo = 0
        candleStageDuration = Double.random(in: 0.10...0.18)
      case 2: // Briefly hold the exact baseline before rising.
        candleStage = 3
        candleStageFrom = 0
        candleStageTo = 0
        candleStageDuration = Double.random(in: 0.06...0.14)
      case 3: // A slower warm lift, then another smooth return.
        candleStage = 4
        candleStageFrom = 0
        candleStageTo = candleRise
        candleStageDuration = Double.random(in: 0.28...0.50)
      case 4:
        candleStage = 5
        candleStageFrom = candleRise
        candleStageTo = 0
        candleStageDuration = Double.random(in: 0.45...0.85)
      default:
        candleStage = 0
        currentOffset = 0
        nextEvent = time + Double.random(in: 3.0...7.5)
      }
      candleStageElapsed = 0
    }
    return currentOffset
  }
}
