import SwiftUI
import WatchConnectivity
import WatchKit

struct WatchChannel: Codable, Identifiable {
  let id: String
  let name: String
}

struct WatchMessage: Codable, Identifiable {
  let id: String
  let author: String
  let text: String
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
    }
  }

  func loadMessages(_ channel: WatchChannel) {
    if messageChannelID != channel.id {
      messages = []
      messageChannelID = channel.id
    }
    request(["action": "messages", "scope": scope, "channelId": channel.id]) { response in
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
        self.messages = []
        self.messageChannelID = nil
        self.scope = newScope
        self.error = "Open Bl4uzz on your paired iPhone. Then tap Refresh."
      }
    }
  }
}

@main
struct Bl4uzzApp: App {
  @StateObject private var store = WatchStore()
  @Environment(\.scenePhase) private var scenePhase
  @State private var confirmSetup = false
  @State private var confirmSignOut = false

  var body: some Scene {
    WindowGroup {
      NavigationStack {
        List {
          if let error = store.error { Text(error).foregroundStyle(.secondary) }
          if !store.reachable && !store.independent && store.error == nil {
            Text("Open Bl4uzz on your paired iPhone.").font(.footnote)
          }
          if store.independent {
            Label("Direct connection", systemImage: "wifi").font(.footnote)
          } else {
            Button("Connect without iPhone", systemImage: "applewatch") { confirmSetup = true }
              .disabled(store.busy || !store.reachable)
          }
          Button("Refresh", systemImage: "arrow.clockwise") { store.refresh() }
            .disabled(store.busy)
          if store.busy { ProgressView() }
          ForEach(store.channels) { channel in
            NavigationLink(channel.name) {
              ConversationView(channel: channel, store: store)
            }
            .disabled(store.busy)
          }
          if (store.reachable || store.independent) && store.channels.isEmpty && !store.busy && store.error == nil {
            Text("No channels. Join a channel on your iPhone.")
          }
          if store.independent {
            Button("Sign out of watch", role: .destructive) { confirmSignOut = true }
          }
        }
        .navigationTitle("Bl4uzz")
        .onAppear { store.showChannels() }
      }
      .onChange(of: scenePhase) { _, phase in
        if phase == .active { store.resume() }
      }
      .alert("Connect without iPhone?", isPresented: $confirmSetup) {
        Button("Connect") { store.setupStandalone() }
        Button("Cancel", role: .cancel) {}
      } message: {
        Text("Copy your current iPhone sign-in to this watch's Keychain. Then use Wi-Fi or cellular without the iPhone. Open Bl4uzz on your iPhone for this setup step.")
      }
      .alert("Sign out of watch?", isPresented: $confirmSignOut) {
        Button("Sign out", role: .destructive) { store.signOut() }
        Button("Cancel", role: .cancel) {}
      } message: {
        Text("Remove the saved watch sign-in. Your iPhone stays signed in.")
      }
    }
  }
}

struct ConversationView: View {
  let channel: WatchChannel
  @ObservedObject var store: WatchStore
  @State private var draft = ""
  @State private var draftScope = ""
  @State private var showQuickReplies = false
  @Environment(\.scenePhase) private var scenePhase

  private var draftKey: String { "Bl4uzz.draft.\(draftScope).\(channel.id)" }

  var body: some View {
    List {
      if let error = store.error { Text(error).foregroundStyle(.secondary) }
      Button("Refresh", systemImage: "arrow.clockwise") { store.loadMessages(channel) }
        .disabled(store.busy || draftScope != store.scope)
      if store.busy { ProgressView() }
      if draftScope == store.scope {
        TextField("Message", text: $draft, axis: .vertical)
        Button("Quick reply", systemImage: "text.bubble") { showQuickReplies = true }
        Button("Send", systemImage: "paperplane") {
          let sentDraft = draft
          store.send(sentDraft, to: channel) {
            draft = confirmedWatchDraft(draft, sent: sentDraft)
          }
        }
        .disabled(
          store.busy || (!store.independent && !store.reachable)
            || draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || draft.utf16.count > 2000
        )
        if draft.utf16.count > 2000 {
          Text("Use 2000 characters or fewer.").foregroundStyle(.red)
        }
      } else {
        Text("The active account changed. Go back and refresh the channel list.")
      }
      if store.messages.isEmpty && !store.busy && store.error == nil {
        Text("No messages yet.").foregroundStyle(.secondary)
      }
      ForEach(store.messages.reversed()) { message in
        VStack(alignment: .leading, spacing: 4) {
          Text(message.author).font(.caption).foregroundStyle(.secondary)
          Text(message.text.isEmpty ? "Attachment: open on iPhone." : message.text)
        }
      }
    }
    .navigationTitle(channel.name)
    .confirmationDialog("Quick reply", isPresented: $showQuickReplies) {
      ForEach(["Yes", "No", "Thanks", "I will check."], id: \.self) { text in
        Button(text) { draft = text }
      }
    }
    .onAppear {
      draftScope = store.scope
      draft = UserDefaults.standard.string(forKey: draftKey) ?? ""
      store.loadMessages(channel)
    }
    .onChange(of: draft) { _, value in
      if value.isEmpty {
        UserDefaults.standard.removeObject(forKey: draftKey)
      } else {
        UserDefaults.standard.set(value, forKey: draftKey)
      }
    }
    .task {
      while !Task.isCancelled {
        do { try await Task.sleep(for: .seconds(15)) } catch { return }
        if scenePhase == .active && !store.busy && store.error == nil && draftScope == store.scope {
          store.loadMessages(channel)
        }
      }
    }
  }
}
