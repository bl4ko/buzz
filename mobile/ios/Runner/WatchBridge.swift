import Flutter
import WatchConnectivity

final class WatchBridge: NSObject, WCSessionDelegate {
  private let channel: FlutterMethodChannel
  private var state: [String: Any] = ["scope": "", "available": false]

  init(messenger: FlutterBinaryMessenger) {
    channel = FlutterMethodChannel(name: "buzz/watch", binaryMessenger: messenger)
    super.init()
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self, call.method == "setState", let state = call.arguments as? [String: Any] else {
        result(FlutterMethodNotImplemented)
        return
      }
      self.state = state
      self.publishState()
      result(nil)
    }
    if WCSession.isSupported() {
      WCSession.default.delegate = self
      WCSession.default.activate()
    }
  }

  private func publishState() {
    guard WCSession.isSupported(), WCSession.default.activationState == .activated,
      WCSession.default.isWatchAppInstalled
    else { return }
    do {
      try WCSession.default.updateApplicationContext(state)
    } catch {
      NSLog("Bl4uzz watch state transfer failed: %@", error.localizedDescription)
    }
  }

  func session(
    _ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState,
    error: Error?
  ) {
    DispatchQueue.main.async { self.publishState() }
  }

  func sessionWatchStateDidChange(_ session: WCSession) {
    DispatchQueue.main.async { self.publishState() }
  }

  func sessionDidBecomeInactive(_ session: WCSession) {}

  func sessionDidDeactivate(_ session: WCSession) {
    session.activate()
  }

  func session(
    _ session: WCSession, didReceiveMessage message: [String: Any],
    replyHandler: @escaping ([String: Any]) -> Void
  ) {
    DispatchQueue.main.async {
      self.channel.invokeMethod("request", arguments: message) { result in
        if let response = result as? [String: Any] {
          replyHandler(response)
        } else {
          replyHandler(["error": "Open Bl4uzz on your iPhone and try again."])
        }
      }
    }
  }
}
