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
      binaryMessenger: engineBridge.applicationRegistrar.messenger
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
    do {
      try setTorch(initialLevel())
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
    let delay: TimeInterval
    switch mode {
    case 1: delay = Double.random(in: 0.45...1.50)
    case 2: delay = Double.random(in: 1.20...2.60)
    default: delay = Double.random(in: 0.35...1.15)
    }
    flickerTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
      self?.flicker()
    }
  }

  private func flicker() {
    guard running else { return }
    let level: Float
    switch mode {
    case 1: level = Float.random(in: 0.040...0.090)
    case 2: level = Float.random(in: 0.022...0.050)
    default: level = Float.random(in: 0.042...0.095)
    }
    try? setTorch(level)
    scheduleFlicker()
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

      guard let url = Bundle.main.url(
        forResource: "files/SafeFlame/Resources/\(soundName)",
        withExtension: "wav",
        subdirectory: "flutter_assets"
      ) ?? Bundle.main.url(forResource: soundName, withExtension: "wav") else { return }

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
