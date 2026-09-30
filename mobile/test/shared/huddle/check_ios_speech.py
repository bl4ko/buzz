from pathlib import Path
import subprocess
import tempfile

source = Path(__file__).resolve().parents[3] / "ios/Runner/HuddleMediaPlugin.swift"
speech = source.read_text().split("private final class HuddleSpeech:", 1)[1]
stubs = r'''
import Foundation
typealias FlutterResult = (Any?) -> Void
struct FlutterError { init(code: String, message: String, details: Any?) {} }
enum Authorization { case authorized }
enum Hint { case dictation }
enum Boundary { case immediate }
protocol AVSpeechSynthesizerDelegate: AnyObject {}
final class AVSpeechSynthesizer {
  weak var delegate: AVSpeechSynthesizerDelegate?
  func stopSpeaking(at: Boundary) {}
  func speak(_ utterance: AVSpeechUtterance) {}
}
struct AVSpeechSynthesisVoice {
  init?(identifier: String) {}
  init?(language: String) {}
}
final class AVSpeechUtterance {
  var voice: AVSpeechSynthesisVoice?
  init(string: String) {}
}
final class AVAudioPCMBuffer {
  let samples = UnsafeMutablePointer<Float>.allocate(capacity: 48000)
  let channels = UnsafeMutablePointer<UnsafeMutablePointer<Float>>.allocate(capacity: 1)
  var floatChannelData: UnsafePointer<UnsafeMutablePointer<Float>>? { UnsafePointer(channels) }
  let frameLength: UInt32 = 48000
  let format = Format()
  struct Format { let sampleRate = 48000.0 }
  init() {
    samples.initialize(repeating: 0, count: 48000)
    channels.initialize(to: samples)
  }
  deinit { samples.deallocate(); channels.deallocate() }
}
final class SFSpeechAudioBufferRecognitionRequest {
  var requiresOnDeviceRecognition = false
  var shouldReportPartialResults = false
  var taskHint = Hint.dictation
  var contextualStrings: [String] = []
  var endings = 0
  func append(_ buffer: AVAudioPCMBuffer) {}
  func endAudio() { endings += 1 }
}
final class SFSpeechRecognitionTask { func cancel() {} }
struct RecognitionResult {
  let bestTranscription: Transcription
  let isFinal: Bool
  struct Transcription { let formattedString: String }
  init(_ text: String, final: Bool) {
    bestTranscription = Transcription(formattedString: text)
    isFinal = final
  }
}
final class SFSpeechRecognizer {
  static var callback: ((RecognitionResult?, Error?) -> Void)?
  static var request: SFSpeechAudioBufferRecognitionRequest?
  let supportsOnDeviceRecognition = true
  let isAvailable = true
  init?(locale: Locale) {}
  static func requestAuthorization(_ completion: (Authorization) -> Void) {
    completion(.authorized)
  }
  func recognitionTask(with request: SFSpeechAudioBufferRecognitionRequest,
    resultHandler: @escaping (RecognitionResult?, Error?) -> Void) -> SFSpeechRecognitionTask {
    Self.request = request
    Self.callback = resultHandler
    return SFSpeechRecognitionTask()
  }
}
'''
checks = r'''
func drain(_ seconds: Double = 0.05) {
  RunLoop.main.run(until: Date().addingTimeInterval(seconds))
}
var transcripts: [String] = []
private let speech = HuddleSpeech(onTranscript: { transcripts.append($0) }, onError: { fatalError($0) })
speech.start(agentName: "Hermes", result: { _ in })
drain()
assert(SFSpeechRecognizer.request?.contextualStrings == ["Hermes"])
let callback = SFSpeechRecognizer.callback!
let request = SFSpeechRecognizer.request!
callback(RecognitionResult("Hey Harmon", final: false), nil)
drain()
speech.append(AVAudioPCMBuffer())
assert(request.endings == 1)
assert(transcripts.isEmpty)
callback(RecognitionResult("Hey Hermes, how are you?", final: true), nil)
drain()
assert(transcripts == ["Hey Hermes, how are you?"])
assert(request.endings == 1)
callback(RecognitionResult("stale result", final: true), nil)
drain()
assert(transcripts.count == 1)
let nextCallback = SFSpeechRecognizer.callback!
nextCallback(RecognitionResult("timeout fallback", final: false), nil)
drain()
speech.append(AVAudioPCMBuffer())
drain(2.1)
assert(transcripts == ["Hey Hermes, how are you?", "timeout fallback"])
speech.stop()
print("iOS speech finalization checks passed")
'''
with tempfile.TemporaryDirectory() as directory:
    path = Path(directory) / "check.swift"
    path.write_text(stubs + "\nprivate final class HuddleSpeech:" + speech + checks)
    subprocess.run(["swift", str(path)], check=True)
