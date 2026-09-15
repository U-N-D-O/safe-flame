import AppKit
import AVFoundation
import Foundation

// Runs on the macOS builder against Runner.app before publication.
let app = URL(fileURLWithPath: CommandLine.arguments[1])
let source = URL(fileURLWithPath: CommandLine.arguments[2])
let plistData = try Data(contentsOf: app.appendingPathComponent("Info.plist"))
let plist = try PropertyListSerialization.propertyList(from: plistData, format: nil) as! [String: Any]
let icons = plist["CFBundleIcons"] as! [String: Any]
let primary = icons["CFBundlePrimaryIcon"] as! [String: Any]
precondition(primary["CFBundleIconName"] as? String == "SafeFlameIcon", "Wrong icon catalog")

let compiled = app.appendingPathComponent("SafeFlameIcon60x60@2x.png")
let decoded = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString + ".png")
let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/sips")
process.arguments = ["-s", "format", "png", compiled.path, "--out", decoded.path]
try process.run()
process.waitUntilExit()
precondition(process.terminationStatus == 0, "Cannot decode compiled icon")
defer { try? FileManager.default.removeItem(at: decoded) }
let actual = NSBitmapImageRep(data: try Data(contentsOf: decoded))!
let expected = NSBitmapImageRep(data: try Data(contentsOf: source))!
precondition(actual.pixelsWide == expected.pixelsWide && actual.pixelsHigh == expected.pixelsHigh)
var error = 0.0
for y in 0..<actual.pixelsHigh {
  for x in 0..<actual.pixelsWide {
    let a = actual.colorAt(x: x, y: y)!.usingColorSpace(.deviceRGB)!
    let b = expected.colorAt(x: x, y: y)!.usingColorSpace(.deviceRGB)!
    error += abs(a.redComponent - b.redComponent)
      + abs(a.greenComponent - b.greenComponent) + abs(a.blueComponent - b.blueComponent)
  }
}
let meanError = error / Double(actual.pixelsWide * actual.pixelsHigh * 3)
precondition(meanError < 0.03, "Compiled icon differs from supplied artwork: \(meanError)")
print("Compiled iPhone icon matches supplied artwork (mean error \(meanError))")

for name in ["fireplace", "candle", "nightlight"] {
  let url = app.appendingPathComponent("Frameworks/App.framework/flutter_assets/files/SafeFlame/Resources/\(name).wav")
  let file = try AVAudioFile(forReading: url)
  let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length))!
  try file.read(into: buffer)
  precondition(buffer.frameLength > 0, "Empty audio: \(name)")
  var peak: Float = 0
  if let channels = buffer.floatChannelData {
    for channel in 0..<Int(buffer.format.channelCount) {
      for frame in 0..<Int(buffer.frameLength) {
        peak = max(peak, abs(channels[channel][frame]))
      }
    }
  }
  precondition(peak > 0, "Silent or unreadable audio: \(name)")
  print("\(name).wav decoded: \(buffer.frameLength) frames, peak \(peak)")
}
