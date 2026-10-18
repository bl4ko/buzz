import AppKit
import Vision

let arguments = CommandLine.arguments
guard arguments.count == 3, let image = NSImage(contentsOfFile: arguments[1]),
  let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil),
  let scale = Double(arguments[2])
else {
  FileHandle.standardError.write(Data("usage: ocr <png> <pixels-per-point>\n".utf8))
  exit(2)
}
let width = Double(cgImage.width)
let height = Double(cgImage.height)
let request = VNRecognizeTextRequest()
request.recognitionLevel = .fast
request.usesLanguageCorrection = false
if let cpu = try request.supportedComputeStageDevices[.main]?.first(where: {
  if case .cpu = $0 { return true }
  return false
}) {
  request.setComputeDevice(cpu, for: .main)
}
try VNImageRequestHandler(cgImage: cgImage).perform([request])
for observation in request.results ?? [] {
  guard let text = observation.topCandidates(1).first?.string else { continue }
  let box = observation.boundingBox
  let line: [String: Any] = [
    "text": text,
    "x": (box.midX * width / scale).rounded(),
    "y": ((1 - box.midY) * height / scale).rounded(),
  ]
  let data = try JSONSerialization.data(withJSONObject: line, options: [.sortedKeys])
  print(String(decoding: data, as: UTF8.self))
}
