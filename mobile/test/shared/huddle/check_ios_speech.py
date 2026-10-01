from pathlib import Path
import subprocess
import tempfile

source = Path(__file__).resolve().parents[3] / "ios/Runner/HuddleMediaPlugin.swift"
speech = source.read_text().split("private final class HuddleSpeech:", 1)[1]
stubs = r'''
import Foundation
typealias FlutterResult = (Any?) -> Void
struct FlutterError { init(code: String, message: String, details: Any?) {} }
protocol AVAudioPlayerDelegate: AnyObject {}
final class AVAudioPlayer {
  weak var delegate: AVAudioPlayerDelegate?
  init(data: Data) throws {}
  func play() -> Bool { true }
  func stop() {}
}
final class AVAudioPCMBuffer {
  let samples = UnsafeMutablePointer<Float>.allocate(capacity: 960)
  let channels = UnsafeMutablePointer<UnsafeMutablePointer<Float>>.allocate(capacity: 1)
  var floatChannelData: UnsafePointer<UnsafeMutablePointer<Float>>? { UnsafePointer(channels) }
  let frameLength: UInt32 = 960
  let format = Format()
  struct Format { let sampleRate = 48000.0 }
  init(_ value: Float) {
    samples.initialize(repeating: value, count: 960)
    channels.initialize(to: samples)
  }
  deinit { samples.deallocate(); channels.deallocate() }
}
'''
checks = r'''
var clips: [Data] = []
private let speech = HuddleSpeech(onAudio: { clips.append($0) }, onError: { fatalError($0) })
speech.start(agentName: "Hermes") { _ in }
let quiet = AVAudioPCMBuffer(0)
let voice = AVAudioPCMBuffer(0.1)
for _ in 0..<1000 { speech.append(quiet) }
assert(clips.isEmpty)
for _ in 0..<15 { speech.append(voice) }
for _ in 0..<29 { speech.append(quiet) }
assert(clips.isEmpty)
speech.append(quiet)
assert(clips.count == 1)
let clip = clips[0]
assert(String(data: clip.prefix(4), encoding: .utf8) == "RIFF")
assert(String(data: clip[8..<16], encoding: .utf8) == "WAVEfmt ")
assert(String(data: clip[36..<40], encoding: .utf8) == "data")
assert(clip[22] == 1 && clip[34] == 16)
assert(clip.count <= 44 + 48000 * 2 * 6 / 5)
for _ in 0..<800 { speech.append(voice) }
assert(clips.count == 2)
assert(clips[1].count <= 44 + 48000 * 2 * 15)
speech.stop()
for _ in 0..<50 { speech.append(voice); speech.append(quiet) }
assert(clips.count == 2)
speech.start(agentName: nil) { _ in }
speech.play(clips[0])
for _ in 0..<50 { speech.append(voice); speech.append(quiet) }
assert(clips.count == 2)
print("iOS speech capture checks passed")
'''
with tempfile.TemporaryDirectory() as directory:
    script = Path(directory) / "speech.swift"
    script.write_text(stubs + "\nprivate final class HuddleSpeech:" + speech + checks)
    subprocess.run(["swift", str(script)], check=True)
