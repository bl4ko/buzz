import SwiftUI
import WatchConnectivity

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
  private var generation = 0
  private var messageChannelID: String?

  override init() {
    super.init()
    WCSession.default.delegate = self
    WCSession.default.activate()
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
      self.refresh()
    }
  }

  nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
    Task { @MainActor in self.reachable = session.isReachable }
  }

  nonisolated func session(
    _ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]
  ) {
    Task { @MainActor in
      let newScope = applicationContext["scope"] as? String ?? ""
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

  var body: some Scene {
    WindowGroup {
      NavigationStack {
        List {
          if let error = store.error { Text(error).foregroundStyle(.secondary) }
          if !store.reachable {
            Text("Open Bl4uzz on your paired iPhone.").font(.footnote)
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
          if store.reachable && store.channels.isEmpty && !store.busy && store.error == nil {
            Text("No channels. Join a channel on your iPhone.")
          }
        }
        .navigationTitle("Bl4uzz")
      }
    }
  }
}

struct ConversationView: View {
  let channel: WatchChannel
  @ObservedObject var store: WatchStore
  @State private var draft = ""
  @State private var draftScope = ""

  private var draftKey: String { "Bl4uzz.draft.\(draftScope).\(channel.id)" }

  var body: some View {
    List {
      if let error = store.error { Text(error).foregroundStyle(.secondary) }
      Button("Refresh", systemImage: "arrow.clockwise") { store.loadMessages(channel) }
        .disabled(store.busy || draftScope != store.scope)
      if store.busy { ProgressView() }
      ForEach(store.messages) { message in
        VStack(alignment: .leading, spacing: 4) {
          Text(message.author).font(.caption).foregroundStyle(.secondary)
          Text(message.text.isEmpty ? "Attachment: open on iPhone." : message.text)
        }
      }
      if draftScope == store.scope {
        TextField("Message", text: $draft, axis: .vertical)
        Button("Send", systemImage: "paperplane") {
          let sentDraft = draft
          store.send(sentDraft, to: channel) {
            draft = confirmedWatchDraft(draft, sent: sentDraft)
          }
        }
        .disabled(
          store.busy || !store.reachable
            || draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || draft.count > 2000
        )
      } else {
        Text("The active account changed. Go back and refresh the channel list.")
      }
    }
    .navigationTitle(channel.name)
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
  }
}
