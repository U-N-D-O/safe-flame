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
  private var lastMotionTime: TimeInterval = 0
  private var torchLevel: Double = 0
  private var torchVelocity: Double = 0
  private var quickMotion = FlameDrift(interval: 0.35)
  private var bodyMotion = FlameDrift(interval: 1.3)
  private var slowMotion = FlameDrift(interval: 4.7)
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
    torchVelocity = 0
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
    lastMotionTime = motionStartedAt
    quickMotion = FlameDrift(interval: mode == 1 ? 0.65 : mode == 2 ? 1.8 : 0.35)
    bodyMotion = FlameDrift(interval: mode == 1 ? 2.0 : 1.3)
    slowMotion = FlameDrift(interval: mode == 1 ? 5.3 : 4.7)
    let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
      self?.flicker()
    }
    flickerTimer = timer
    RunLoop.main.add(timer, forMode: .common)
  }

  private func flicker() {
    guard running else { return }
    let now = ProcessInfo.processInfo.systemUptime
    let elapsed = now - motionStartedAt
    let delta = min(0.1, max(1.0 / 120.0, now - lastMotionTime))
    lastMotionTime = now

    let weights: (Double, Double, Double)
    switch mode {
    case 1: weights = (0.10, 0.55, 0.35) // Candle: quiet body with living detail.
    case 2: weights = (0.05, 0.25, 0.70) // Nightlight: very slow and restrained.
    default: weights = (0.25, 0.60, 0.15) // Fireplace: visibly active.
    }
    let noise = tanh(1.8 * (weights.0 * quickMotion.value(at: elapsed)
      + weights.1 * bodyMotion.value(at: elapsed)
      + weights.2 * slowMotion.value(at: elapsed)))

    // Keep the same relative intensity shape while lowering every level by 20%.
    let minimum: Double = (mode == 2 ? 0.022 : mode == 1 ? 0.040 : 0.042) * 0.8
    let maximum: Double = (mode == 2 ? 0.050 : mode == 1 ? 0.090 : 0.095) * 0.8
    let target = minimum + (maximum - minimum) * (0.5 + 0.5 * noise)

    // Follow a moving target like a small spring. The current brightness
    // always influences the next one, so it never holds at a peak or valley.
    let response = mode == 2 ? 0.45 : mode == 1 ? 0.95 : 1.35
    let damping = mode == 2 ? 1.25 : mode == 1 ? 1.65 : 1.95
    let acceleration = (target - torchLevel) * response - torchVelocity * damping
    torchVelocity += acceleration * delta
    torchLevel += torchVelocity * delta
    torchLevel = max(minimum, min(maximum, torchLevel))
    try? setTorch(Float(torchLevel))
  }

  private func initialLevel() -> Float {
    switch mode {
    case 1: return 0.05 * 0.8
    case 2: return 0.035 * 0.8
    default: return 0.065 * 0.8
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

/// Cubic B-spline noise: brightness, velocity and acceleration stay continuous
/// when a new random control point enters. Layers do not stop at their knots.
private final class FlameDrift {
  private let interval: Double
  private var segment = 0
  private var points = (0..<4).map { _ in Double.random(in: -1...1) }

  init(interval: Double) { self.interval = interval }

  func value(at time: Double) -> Double {
    let position = max(0, time) / interval
    let nextSegment = Int(position)
    while segment < nextSegment {
      points.removeFirst()
      points.append(Double.random(in: -1...1))
      segment += 1
    }
    let u = position - Double(segment)
    let u2 = u * u
    let u3 = u2 * u
    let a = pow(1 - u, 3) * points[0]
    let b = (3 * u3 - 6 * u2 + 4) * points[1]
    let c = (-3 * u3 + 3 * u2 + 3 * u + 1) * points[2]
    let d = u3 * points[3]
    return (a + b + c + d) / 6
  }
}
