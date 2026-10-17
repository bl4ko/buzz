import SwiftUI
import WatchConnectivity
import WatchKit

struct WatchChannel: Codable, Identifiable {
  let id: String
  let name: String
  let dm: Bool?
}

struct WatchMessage: Codable, Identifiable {
  let id: String
  let author: String
  let text: String
  let notified: [String]?
  let createdAt: Int?
  let mine: Bool?
}

@MainActor
final class WatchStore: NSObject, ObservableObject, WCSessionDelegate {
  @Published var channels: [WatchChannel] = []
  @Published var messages: [WatchMessage] = []
  @Published var scope = ""
  @Published var error: String?
  @Published var busy = false
  @Published var reachable = false
  @Published var independent = false
  @Published var synced = false
  private var generation = 0
  private var messageChannelID: String?
  private var relay: WatchRelay?

  override init() {
    super.init()
    do {
      if let credentials = try WatchCredentials.load() {
        relay = WatchRelay(credentials: credentials)
        independent = true
        scope = credentials.scope
      }
    } catch {
      self.error = error.localizedDescription
    }
    WCSession.default.delegate = self
    WCSession.default.activate()
  }

  func setupStandalone() {
    request(["action": "setupStandalone", "confirmed": true]) { response in
      do {
        guard let scope = response["scope"] as? String,
          let url = response["relayURL"] as? String,
          let key = response["privateKeyHex"] as? String,
          let pubkey = response["pubkey"] as? String
        else { throw WatchRelayError.invalidSetup }
        let credentials = try WatchCredentials(
          scope: scope, relayURL: url, privateKeyHex: key, pubkey: pubkey
        )
        try credentials.save()
        self.clearSession()
        self.relay = WatchRelay(credentials: credentials)
        self.independent = true
        self.scope = scope
        self.refresh()
      } catch {
        self.error = error.localizedDescription
      }
    }
  }

  func signOut() {
    do {
      try WatchCredentials.remove()
      clearSession()
      error = "Watch sign-in removed. Set up again to connect without your iPhone."
    } catch {
      self.error = error.localizedDescription
    }
  }

  private func clearSession() {
    generation += 1
    relay?.close()
    relay = nil
    independent = false
    synced = false
    busy = false
    channels = []
    messages = []
    messageChannelID = nil
    scope = ""
  }

  func resume() {
    if let id = messageChannelID, let channel = channels.first(where: { $0.id == id }) {
      loadMessages(channel)
    } else {
      refresh()
    }
  }

  func showChannels() {
    messageChannelID = nil
    refresh()
  }

  func refresh() {
    request(["action": "channels"]) { response in
      guard let scope = response["scope"] as? String,
        let channels: [WatchChannel] = self.decode(response["channels"])
      else {
        self.error = "The iPhone response is not valid."
        return
      }
      if self.scope != scope {
        self.messages = []
        self.messageChannelID = nil
      }
      self.scope = scope
      self.channels = channels
      self.synced = true
    }
  }

  func loadMessages(_ channel: WatchChannel) {
    if messageChannelID != channel.id {
      messages = []
      messageChannelID = channel.id
    }
    request(["action": "messages", "scope": scope, "channelId": channel.id, "dm": channel.dm == true]) { response in
      guard response["scope"] as? String == self.scope,
        let messages: [WatchMessage] = self.decode(response["messages"])
      else {
        self.error = "The active account changed. Refresh the watch."
        return
      }
      self.messages = messages
    }
  }

  func send(_ text: String, to channel: WatchChannel, onSent: @escaping () -> Void) {
    request(["action": "send", "scope": scope, "channelId": channel.id, "text": text]) {
      response in
      guard response["sent"] as? Bool == true else {
        self.error = "The message was not confirmed. Check the channel before you send again."
        return
      }
      onSent()
      WKInterfaceDevice.current().play(.success)
      self.loadMessages(channel)
    }
  }

  private func decode<T: Decodable>(_ value: Any?) -> T? {
    guard let value, JSONSerialization.isValidJSONObject(value),
      let data = try? JSONSerialization.data(withJSONObject: value)
    else { return nil }
    return try? JSONDecoder().decode(T.self, from: data)
  }

  private func request(
    _ message: [String: Any], completion: @escaping ([String: Any]) -> Void
  ) {
    guard !busy else { return }
    if let relay, message["action"] as? String != "setupStandalone" {
      error = nil
      busy = true
      let requestGeneration = generation
      Task {
        do {
          let response = try await relay.request(message)
          guard self.generation == requestGeneration else { return }
          self.busy = false
          completion(response)
        } catch {
          guard self.generation == requestGeneration else { return }
          self.busy = false
          if message["action"] as? String == "send" {
            self.error = "\(error.localizedDescription) Check the channel before you send again."
          } else {
            self.error = error.localizedDescription
          }
        }
      }
      return
    }
    guard WCSession.default.activationState == .activated, WCSession.default.isReachable else {
      error = "Open Bl4uzz on your paired iPhone. Then tap Refresh."
      return
    }
    error = nil
    busy = true
    let requestGeneration = generation
    var finished = false
    var timer: Timer?
    let finish: ([String: Any]) -> Void = { response in
      guard !finished else { return }
      finished = true
      timer?.invalidate()
      guard self.generation == requestGeneration else { return }
      self.busy = false
      if let error = response["error"] as? String {
        self.error = error
      } else {
        completion(response)
      }
    }
    timer = Timer.scheduledTimer(withTimeInterval: 28, repeats: false) { _ in
      Task { @MainActor in
        finish(["error": "The iPhone did not reply. Check the channel before you send again."])
      }
    }
    WCSession.default.sendMessage(message) { response in
      Task { @MainActor in finish(response) }
    } errorHandler: { _ in
      Task { @MainActor in
        finish(["error": "The iPhone connection failed. Check the channel before you send again."])
      }
    }
  }

  nonisolated func session(
    _ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState,
    error: Error?
  ) {
    Task { @MainActor in
      self.reachable = session.isReachable
      if !self.independent { self.refresh() }
    }
  }

  nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
    Task { @MainActor in
      self.reachable = session.isReachable
      if session.isReachable && !self.independent { self.resume() }
    }
  }

  nonisolated func session(
    _ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]
  ) {
    Task { @MainActor in
      let newScope = applicationContext["scope"] as? String ?? ""
      if self.independent {
        if applicationContext["resetStandalone"] as? Bool == true ||
          (!newScope.isEmpty && newScope != self.scope) {
          self.signOut()
          self.error = "The iPhone account changed. Set up watch sign-in again."
        }
        return
      }
      if newScope != self.scope || applicationContext["available"] as? Bool != true {
        self.generation += 1
        self.busy = false
        self.channels = []
        self.synced = false
        self.messages = []
        self.messageChannelID = nil
        self.scope = newScope
        self.error = "Open Bl4uzz on your paired iPhone. Then tap Refresh."
      }
    }
  }
}
