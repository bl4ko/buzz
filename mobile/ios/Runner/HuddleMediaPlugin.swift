import AVFoundation
import Flutter
import UIKit

/// Foreground-only native seam for iOS Huddle media.
///
/// Owns microphone permission, the voice-processing audio session, native
/// Opus capture/playout, interruptions, and the built-in output toggle.
final class HuddleMediaPlugin {
  private let channel: FlutterMethodChannel
  private let speechChannel: FlutterMethodChannel
  private var speech: HuddleSpeech?
  private let audioSession = AVAudioSession.sharedInstance()
  private var audioSessionPrepared = false
  private var speakerEnabled = false
  private var audioEngine: HuddleAudioEngine?
  private var interruptionObserver: NSObjectProtocol?
  private var mediaServicesResetObserver: NSObjectProtocol?

  init(messenger: FlutterBinaryMessenger) {
    channel = FlutterMethodChannel(
      name: "buzz/huddle_media",
      binaryMessenger: messenger
    )
    speechChannel = FlutterMethodChannel(name: "buzz/huddle_speech", binaryMessenger: messenger)
    speechChannel.setMethodCallHandler { [weak self] call, result in
      self?.handleSpeech(call, result: result)
    }
    channel.setMethodCallHandler { [weak self] call, result in
      self?.handle(call, result: result)
    }
    interruptionObserver = NotificationCenter.default.addObserver(
      forName: AVAudioSession.interruptionNotification,
      object: audioSession,
      queue: .main
    ) { [weak self] notification in
      self?.handleInterruption(notification)
    }
    mediaServicesResetObserver = NotificationCenter.default.addObserver(
      forName: AVAudioSession.mediaServicesWereResetNotification,
      object: audioSession,
      queue: .main
    ) { [weak self] _ in
      self?.handleMediaServicesReset()
    }
  }

  deinit {
    channel.setMethodCallHandler(nil)
    speechChannel.setMethodCallHandler(nil)
    speech?.stop()
    audioEngine?.stop()
    audioEngine = nil
    if let interruptionObserver {
      NotificationCenter.default.removeObserver(interruptionObserver)
    }
    if let mediaServicesResetObserver {
      NotificationCenter.default.removeObserver(mediaServicesResetObserver)
    }
    if audioSessionPrepared {
      try? audioSession.overrideOutputAudioPort(.none)
      try? audioSession.setActive(
        false,
        options: [.notifyOthersOnDeactivation]
      )
    }
  }

  private func handle(
    _ call: FlutterMethodCall,
    result: @escaping FlutterResult
  ) {
    switch call.method {
    case "getCapabilities":
      result(capabilities)
    case "requestMicrophonePermission":
      requestMicrophonePermission(result: result)
    case "openSystemSettings":
      openSystemSettings(result: result)
    case "prepare":
      prepare(arguments: call.arguments, result: result)
    case "start":
      start(result: result)
    case "setMuted":
      setMuted(arguments: call.arguments, result: result)
    case "setSpeakerEnabled":
      setSpeakerEnabled(arguments: call.arguments, result: result)
    case "playRemoteOpusFrame":
      playRemoteOpusFrame(arguments: call.arguments, result: result)
    case "removeRemotePeer":
      removeRemotePeer(arguments: call.arguments, result: result)
    case "stop":
      stop(result: result)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func handleSpeech(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "start":
      guard audioEngine != nil else {
        result(FlutterError(code: "invalid_state", message: "Join the Huddle first.", details: nil))
        return
      }
      if speech == nil {
        speech = HuddleSpeech(
          onAudio: { [weak self] audio in
            self?.speechChannel.invokeMethod("audio", arguments: ["audio": FlutterStandardTypedData(bytes: audio)])
          },
          onError: { [weak self] message in
            self?.speechChannel.invokeMethod("error", arguments: ["message": message])
          },
          onPlaybackFinished: { [weak self] in
            self?.speechChannel.invokeMethod("status", arguments: ["message": "Listening on this device"])
          }
        )
      }
      let arguments = call.arguments as? [String: Any]
      speech?.start(agentName: arguments?["agentName"] as? String, result: result)
    case "stop":
      speech?.stop()
      result(nil)
    case "play":
      let arguments = call.arguments as? [String: Any]
      guard let audio = arguments?["audio"] as? FlutterStandardTypedData else {
        result(FlutterError(code: "invalid_arguments", message: "Missing speech audio.", details: nil))
        return
      }
      guard let speech else {
        result(FlutterError(code: "invalid_state", message: "Start agent speech first.", details: nil))
        return
      }
      speech.play(audio.data, result: result)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private var capabilities: [String: Any] {
    let supportsOpus = HuddleAudioEngine.isSupported()
    return [
      "platform": "ios",
      "audioSession": true,
      "microphonePermission": true,
      "capture": supportsOpus,
      "playback": supportsOpus,
      "opusEncoding": supportsOpus,
      "opusDecoding": supportsOpus,
    ]
  }

  private func requestMicrophonePermission(result: @escaping FlutterResult) {
    switch audioSession.recordPermission {
    case .granted:
      result("granted")
    case .denied:
      result("denied")
    case .undetermined:
      audioSession.requestRecordPermission { granted in
        DispatchQueue.main.async {
          result(granted ? "granted" : "denied")
        }
      }
    @unknown default:
      result("restricted")
    }
  }

  /// Open the iOS Settings app on this app's page so the user can grant a
  /// previously denied microphone permission. iOS never re-prompts once denied,
  /// so this is the only in-app recovery path.
  private func openSystemSettings(result: @escaping FlutterResult) {
    guard let url = URL(string: UIApplication.openSettingsURLString) else {
      result(false)
      return
    }
    DispatchQueue.main.async {
      guard UIApplication.shared.canOpenURL(url) else {
        result(false)
        return
      }
      UIApplication.shared.open(url, options: [:]) { opened in
        result(opened)
      }
    }
  }

  private func prepare(arguments: Any?, result: @escaping FlutterResult) {
    guard let values = arguments as? [String: Any],
      (values["protocolVersion"] as? NSNumber)?.intValue == 2,
      (values["sampleRateHz"] as? NSNumber)?.intValue == 48_000,
      (values["channels"] as? NSNumber)?.intValue == 1,
      (values["frameSamples"] as? NSNumber)?.intValue == 960
    else {
      result(
        FlutterError(
          code: "invalid_configuration",
          message: "Expected the fixed Huddle Opus v2 media configuration.",
          details: nil
        )
      )
      return
    }
    guard HuddleAudioEngine.isSupported() else {
      result(
        FlutterError(
          code: "unsupported",
          message: "This iOS device does not expose native Opus encode/decode.",
          details: nil
        )
      )
      return
    }
    guard audioSession.recordPermission == .granted else {
      result(
        FlutterError(
          code: "microphone_permission_denied",
          message: "Microphone permission is required for a Huddle.",
          details: nil
        )
      )
      return
    }

    do {
      try audioSession.setCategory(
        .playAndRecord,
        mode: .voiceChat,
        options: [.allowBluetoothHFP]
      )
      try audioSession.setPreferredSampleRate(48_000)
      try audioSession.setPreferredIOBufferDuration(0.02)
      try audioSession.setActive(true)
      try audioSession.overrideOutputAudioPort(.none)
      audioSessionPrepared = true
      speakerEnabled = false
      result([
        "audioSessionPrepared": true,
        "sampleRateHz": Int(audioSession.sampleRate),
        "channels": 1,
        "frameSamples": 960,
      ])
    } catch {
      audioSessionPrepared = false
      try? audioSession.overrideOutputAudioPort(.none)
      try? audioSession.setActive(
        false,
        options: [.notifyOthersOnDeactivation]
      )
      result(
        FlutterError(
          code: "audio_session_failed",
          message: "Unable to prepare the iOS Huddle audio session.",
          details: error.localizedDescription
        )
      )
    }
  }

  private func start(result: @escaping FlutterResult) {
    guard audioSessionPrepared else {
      result(
        FlutterError(
          code: "invalid_state",
          message: "Prepare Huddle audio before starting it.",
          details: nil
        )
      )
      return
    }
    guard audioEngine == nil else {
      result(
        FlutterError(
          code: "invalid_state",
          message: "Huddle audio is already running.",
          details: nil
        )
      )
      return
    }

    do {
      let engine = try HuddleAudioEngine(
        onLocalPacket: { [weak self] packet in
          self?.emitLocalPacket(packet)
        },
        onFailure: { [weak self] code, message in
          self?.emitNativeFailure(code: code, message: message)
        },
        onDiagnostics: { [weak self] diagnostics in
          self?.emitCaptureDiagnostics(diagnostics)
        },
        onCapture: { [weak self] buffer in
          DispatchQueue.main.async { [weak self] in
            self?.speech?.append(buffer)
          }
        },
        diagnosticsEnabled: Self.diagnosticsEnabled
      )
      try engine.start()
      audioEngine = engine
      result(nil)
    } catch {
      result(
        FlutterError(
          code: "media_start_failed",
          message: "Unable to start iOS Huddle audio.",
          details: error.localizedDescription
        )
      )
    }
  }

  private func setMuted(arguments: Any?, result: @escaping FlutterResult) {
    guard let values = arguments as? [String: Any],
      let muted = values["muted"] as? Bool
    else {
      result(
        FlutterError(
          code: "invalid_arguments",
          message: "Missing Huddle mute state.",
          details: nil
        )
      )
      return
    }
    do {
      guard let audioEngine else {
        throw HuddleNativeMediaError.invalidState(
          "Huddle audio is not running."
        )
      }
      try audioEngine.setMuted(muted)
      speech?.resetCapture()
      result(nil)
    } catch {
      result(
        FlutterError(
          code: "invalid_state",
          message: error.localizedDescription,
          details: nil
        )
      )
    }
  }

  private func setSpeakerEnabled(
    arguments: Any?,
    result: @escaping FlutterResult
  ) {
    guard audioSessionPrepared, audioEngine != nil else {
      result(
        FlutterError(
          code: "invalid_state",
          message: "Huddle audio is not running.",
          details: nil
        )
      )
      return
    }
    guard let values = arguments as? [String: Any],
      let enabled = values["enabled"] as? Bool
    else {
      result(
        FlutterError(
          code: "invalid_arguments",
          message: "Missing Huddle speaker state.",
          details: nil
        )
      )
      return
    }

    do {
      try audioSession.overrideOutputAudioPort(enabled ? .speaker : .none)
      speakerEnabled = enabled
      result(nil)
    } catch {
      result(
        FlutterError(
          code: "audio_route_failed",
          message: "Unable to change Huddle audio output.",
          details: error.localizedDescription
        )
      )
    }
  }

  private func playRemoteOpusFrame(
    arguments: Any?,
    result: @escaping FlutterResult
  ) {
    guard let values = arguments as? [String: Any],
      let peerIndex = (values["peerIndex"] as? NSNumber)?.intValue,
      (0...255).contains(peerIndex),
      let sequence = (values["sequence"] as? NSNumber)?.intValue,
      (0...0xffff).contains(sequence),
      let timestamp = (values["timestamp48k"] as? NSNumber)?.int64Value,
      (0...Int64(UInt32.max)).contains(timestamp),
      let levelDbov = (values["levelDbov"] as? NSNumber)?.intValue,
      (-127...0).contains(levelDbov),
      let typedData = values["opus"] as? FlutterStandardTypedData,
      !typedData.data.isEmpty,
      typedData.data.count <= HuddleAudioFormats.maximumOpusPacketBytes
    else {
      result(
        FlutterError(
          code: "invalid_arguments",
          message: "Malformed remote Huddle Opus packet.",
          details: nil
        )
      )
      return
    }

    do {
      guard let audioEngine else {
        throw HuddleNativeMediaError.invalidState(
          "Huddle audio is not running."
        )
      }
      try audioEngine.enqueueRemote(
        HuddleRemoteOpusPacket(
          peerIndex: peerIndex,
          sequence: sequence,
          timestamp48k: timestamp,
          levelDbov: levelDbov,
          opus: typedData.data
        )
      )
      result(nil)
    } catch {
      result(
        FlutterError(
          code: "playback_failed",
          message: error.localizedDescription,
          details: nil
        )
      )
    }
  }

  private func removeRemotePeer(
    arguments: Any?,
    result: @escaping FlutterResult
  ) {
    guard let values = arguments as? [String: Any],
      let peerIndex = (values["peerIndex"] as? NSNumber)?.intValue,
      (0...255).contains(peerIndex)
    else {
      result(
        FlutterError(
          code: "invalid_arguments",
          message: "Missing Huddle peer index.",
          details: nil
        )
      )
      return
    }
    guard let audioEngine else {
      result(
        FlutterError(
          code: "invalid_state",
          message: "Huddle audio is not running.",
          details: nil
        )
      )
      return
    }
    audioEngine.removeRemotePeer(peerIndex)
    result(nil)
  }

  private func handleInterruption(_ notification: Notification) {
    guard audioSessionPrepared,
      let rawType = notification.userInfo?[AVAudioSessionInterruptionTypeKey]
        as? NSNumber,
      let type = AVAudioSession.InterruptionType(rawValue: rawType.uintValue)
    else { return }

    if type == .began {
      audioEngine?.setInterrupted(true)
      emitInterruptionChanged(true)
      return
    }
    let rawOptions =
      notification.userInfo?[AVAudioSessionInterruptionOptionKey]
      as? NSNumber
    let options = AVAudioSession.InterruptionOptions(
      rawValue: rawOptions?.uintValue ?? 0
    )
    guard options.contains(.shouldResume) else { return }
    do {
      try audioSession.setActive(true)
      if speakerEnabled {
        try audioSession.overrideOutputAudioPort(.speaker)
      }
      audioEngine?.setInterrupted(false)
      emitInterruptionChanged(false)
    } catch {
      emitNativeFailure(
        code: "audio_resume_failed",
        message: "Unable to resume iOS Huddle audio after interruption."
      )
    }
  }

  private func handleMediaServicesReset() {
    speech?.stop()
    guard audioSessionPrepared || audioEngine != nil else { return }
    audioEngine?.stop()
    audioEngine = nil
    audioSessionPrepared = false
    speakerEnabled = false
    emitNativeFailure(
      code: "media_services_reset",
      message: "iOS audio services restarted. Rejoin the Huddle to continue."
    )
  }

  private func stop(result: @escaping FlutterResult) {
    speech?.stop()
    audioEngine?.stop()
    audioEngine = nil
    guard audioSessionPrepared else {
      speakerEnabled = false
      result(nil)
      return
    }
    do {
      try audioSession.overrideOutputAudioPort(.none)
      try audioSession.setActive(
        false,
        options: [.notifyOthersOnDeactivation]
      )
      audioSessionPrepared = false
      speakerEnabled = false
      result(nil)
    } catch {
      result(
        FlutterError(
          code: "audio_session_stop_failed",
          message: "Unable to stop the iOS Huddle audio session.",
          details: error.localizedDescription
        )
      )
    }
  }

  private func emitLocalPacket(_ packet: HuddleLocalOpusPacket) {
    DispatchQueue.main.async { [weak self] in
      guard self?.audioEngine != nil else { return }
      self?.channel.invokeMethod(
        "localOpusFrame",
        arguments: [
          "sequence": packet.sequence,
          "timestamp48k": packet.timestamp48k,
          "levelDbov": packet.levelDbov,
          "flags": packet.flags,
          "opus": FlutterStandardTypedData(bytes: packet.opus),
        ]
      )
    }
  }

  private func emitNativeFailure(code: String, message: String) {
    DispatchQueue.main.async { [weak self] in
      guard self?.audioEngine != nil || code == "media_services_reset" else {
        return
      }
      self?.channel.invokeMethod(
        "nativeError",
        arguments: ["code": code, "message": message]
      )
    }
  }

  private func emitCaptureDiagnostics(
    _ diagnostics: HuddleCaptureDiagnostics
  ) {
    DispatchQueue.main.async { [weak self] in
      guard self?.audioEngine != nil else { return }
      self?.channel.invokeMethod(
        "captureDiagnostics",
        arguments: [
          "frameCount": diagnostics.frameCount,
          "rmsDbovHistogram": diagnostics.rmsDbovHistogram,
          "peakDbovHistogram": diagnostics.peakDbovHistogram,
          "maxPeakDbov": diagnostics.maxPeakDbov,
          "audioSource": 0,
          "audioSourceLabel": "voice_processing_io",
          "deviceId": nil,
          "deviceType": nil,
          "deviceLabel": diagnostics.deviceLabel,
          "acousticEchoCancelerAvailable": true,
          "acousticEchoCancelerEnabled": diagnostics.voiceProcessingEnabled,
          "noiseSuppressorAvailable": false,
          "noiseSuppressorEnabled": nil,
          "automaticGainControlAvailable": false,
          "automaticGainControlEnabled": nil,
        ]
      )
    }
  }

  private func emitInterruptionChanged(_ interrupted: Bool) {
    channel.invokeMethod(
      "interruptionChanged",
      arguments: ["interrupted": interrupted]
    )
  }

  private static var diagnosticsEnabled: Bool {
    #if DEBUG
      true
    #else
      false
    #endif
  }
}

private final class HuddleSpeech: NSObject, AVAudioPlayerDelegate {
  private let onAudio: (Data) -> Void
  private let onError: (String) -> Void
  private let onPlaybackFinished: () -> Void
  private var player: AVAudioPlayer?
  private var playbackResult: FlutterResult?
  private var pcm = Data()
  private var sampleRate = 48000
  private var silentSamples = 0
  private var voicedSamples = 0
  private var listening = false

  init(onAudio: @escaping (Data) -> Void, onError: @escaping (String) -> Void,
       onPlaybackFinished: @escaping () -> Void = {}) {
    self.onAudio = onAudio
    self.onError = onError
    self.onPlaybackFinished = onPlaybackFinished
    super.init()
  }

  func start(agentName: String?, result: @escaping FlutterResult) {
    listening = true
    clearSegment()
    result(nil)
  }

  func stop() {
    listening = false
    player?.stop()
    player = nil
    playbackResult?(nil)
    playbackResult = nil
    clearSegment()
  }

  func append(_ buffer: AVAudioPCMBuffer) {
    guard listening, player == nil, buffer.frameLength > 0,
          let samples = buffer.floatChannelData?.pointee else { return }
    let rate = Int(buffer.format.sampleRate)
    guard rate > 0 else { return }
    if rate != sampleRate { clearSegment(); sampleRate = rate }
    let count = Int(buffer.frameLength)
    let energy = (0..<count).reduce(Float.zero) { $0 + samples[$1] * samples[$1] } / Float(count)
    if energy > 0.000025 {
      voicedSamples += count
      silentSamples = 0
    } else {
      silentSamples += count
    }
    for index in 0..<count {
      var sample = Int16(max(-1, min(1, samples[index])) * 32767).littleEndian
      withUnsafeBytes(of: &sample) { pcm.append(contentsOf: $0) }
    }
    if voicedSamples == 0 {
      let leadingBytes = sampleRate * 2 / 5
      if pcm.count > leadingBytes { pcm.removeFirst(pcm.count - leadingBytes) }
      return
    }
    if silentSamples >= sampleRate * 3 / 5 || pcm.count >= sampleRate * 2 * 15 {
      let maximumBytes = sampleRate * 2 * 15
      if pcm.count > maximumBytes { pcm.removeLast(pcm.count - maximumBytes) }
      if voicedSamples >= sampleRate / 5 { onAudio(wav()) }
      clearSegment()
    }
  }

  func play(_ audio: Data, result: @escaping FlutterResult = { _ in }) {
    clearSegment()
    player?.stop()
    playbackResult?(FlutterError(code: "speech_replaced", message: "Speech playback was replaced.", details: nil))
    playbackResult = nil
    do {
      let next = try AVAudioPlayer(data: audio)
      next.delegate = self
      player = next
      playbackResult = result
      guard next.play() else {
        player = nil
        playbackResult = nil
        result(FlutterError(code: "speech_play_failed", message: "Could not play speech audio.", details: nil))
        return
      }
    } catch {
      player = nil
      result(FlutterError(code: "speech_play_failed", message: error.localizedDescription, details: nil))
    }
  }

  func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
    guard self.player === player else { return }
    self.player = nil
    clearSegment()
    playbackResult?(flag ? nil : FlutterError(code: "speech_play_failed", message: "Speech audio stopped before completion.", details: nil))
    playbackResult = nil
    if flag { onPlaybackFinished() }
  }

  func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
    guard self.player === player else { return }
    self.player = nil
    clearSegment()
    playbackResult?(FlutterError(code: "speech_decode_failed", message: error?.localizedDescription ?? "Could not decode speech audio.", details: nil))
    playbackResult = nil
  }

  func resetCapture() {
    clearSegment()
  }

  private func clearSegment() {
    pcm.removeAll(keepingCapacity: true)
    silentSamples = 0
    voicedSamples = 0
  }

  private func wav() -> Data {
    var data = Data("RIFF".utf8)
    func number<T: FixedWidthInteger>(_ value: T) {
      var little = value.littleEndian
      withUnsafeBytes(of: &little) { data.append(contentsOf: $0) }
    }
    number(UInt32(pcm.count + 36))
    data.append(Data("WAVEfmt ".utf8))
    number(UInt32(16))
    number(UInt16(1))
    number(UInt16(1))
    number(UInt32(sampleRate))
    number(UInt32(sampleRate * 2))
    number(UInt16(2))
    number(UInt16(16))
    data.append(Data("data".utf8))
    number(UInt32(pcm.count))
    data.append(pcm)
    return data
  }
}
