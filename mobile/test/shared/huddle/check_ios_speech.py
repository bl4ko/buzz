from pathlib import Path
import subprocess
import tempfile

source = Path(__file__).resolve().parents[3] / "ios/Runner/HuddleMediaPlugin.swift"
speech = source.read_text().split("private final class HuddleSpeech:", 1)[1]
stubs = r'''
import Accelerate
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
  init(_ value: (Int) -> Float) {
    for index in 0..<960 { samples[index] = value(index) }
    channels.initialize(to: samples)
  }
  deinit { samples.deallocate(); channels.deallocate() }
}
'''
checks = r'''
var clips: [Data] = []
var speaking: [Bool] = []
private let speech = HuddleSpeech(
  onAudio: { clips.append($0) }, onError: { fatalError($0) }, onSpeaking: { speaking.append($0) })
var buffers = 0
func feed(_ count: Int, _ amplitude: Float = 0, hz: Double = 1000, gate: (Int) -> Bool = { _ in true }) {
  for _ in 0..<count {
    let start = buffers * 960
    speech.append(AVAudioPCMBuffer { index in
      gate(buffers) ? amplitude * Float(sin(2 * Double.pi * hz * Double(start + index) / 48000)) : 0
    })
    buffers += 1
  }
}
speech.start(agentName: "Hermes") { _ in }
feed(1000)
assert(clips.isEmpty)
feed(15, 0.1)
feed(33)
assert(clips.isEmpty)
feed(3)
assert(clips.count == 1)
assert(speaking == [true])
let clip = clips[0]
assert(String(data: clip.prefix(4), encoding: .utf8) == "RIFF")
assert(String(data: clip[8..<16], encoding: .utf8) == "WAVEfmt ")
assert(String(data: clip[36..<40], encoding: .utf8) == "data")
assert(clip[22] == 1 && clip[24] == 0x80 && clip[25] == 0xbb && clip[34] == 16)
assert(clip.count <= 44 + 48000 * 2 * 7 / 5)
feed(10, 0.1)
feed(50)
assert(clips.count == 1)
assert(speaking == [true, true, false])
feed(500, 0.3, hz: 50)
assert(clips.count == 1)
feed(500, 0.05)
feed(50)
assert(clips.count <= 2)
let beforeQuiet = clips.count
feed(300, 0.003, gate: { $0 % 12 < 7 })
feed(50)
assert(clips.count == beforeQuiet)
let afterTone = clips.count
feed(800, 0.1, gate: { $0 % 12 < 7 })
assert(clips.count == afterTone + 1)
assert(clips[afterTone].count == 44 + 48000 * 2 * 15)
speech.stop()
feed(100, 0.1, gate: { $0 % 2 == 0 })
assert(clips.count == afterTone + 1)
speech.start(agentName: nil) { _ in }
speech.play(clips[0])
feed(100, 0.1, gate: { $0 % 2 == 0 })
assert(clips.count == afterTone + 1)
print("iOS speech capture checks passed")
'''
with tempfile.TemporaryDirectory() as directory:
    script = Path(directory) / "speech.swift"
    script.write_text(stubs + "\nprivate final class HuddleSpeech:" + speech + checks)
    subprocess.run(["swift", str(script)], check=True)
