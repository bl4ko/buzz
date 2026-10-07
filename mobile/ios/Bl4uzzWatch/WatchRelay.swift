import Foundation
import Security

struct WatchCredentials: Codable {
  let scope: String
  let relayURL: URL
  let privateKeyHex: String
  let pubkey: String

  init(scope: String, relayURL: String, privateKeyHex: String, pubkey: String) throws {
    guard let url = URL(string: relayURL), url.scheme == "https", url.host?.isEmpty == false,
      url.user == nil, url.password == nil, url.query == nil, url.fragment == nil,
      url.path.isEmpty || url.path == "/", scope.hasSuffix(":" + pubkey), scope.count <= 256
    else { throw WatchRelayError.invalidSetup }
    let probe = try NostrHTTPAuth.signedEvent(
      kind: 22242, tags: [], content: "", privateKeyHex: privateKeyHex
    )
    guard probe.pubkey == pubkey else { throw WatchRelayError.invalidSetup }
    self.scope = scope
    self.relayURL = url
    self.privateKeyHex = privateKeyHex
    self.pubkey = pubkey
  }

  private static var keychainQuery: [String: Any] {
    [kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: "com.bl4ko.buzz.watch.sign-in",
      kSecAttrAccount as String: "active"]
  }

  static func load() throws -> WatchCredentials? {
    var query = keychainQuery
    query[kSecReturnData as String] = true
    query[kSecMatchLimit as String] = kSecMatchLimitOne
    var result: CFTypeRef?
    let status = SecItemCopyMatching(query as CFDictionary, &result)
    if status == errSecItemNotFound { return nil }
    guard status == errSecSuccess, let data = result as? Data else {
      throw WatchRelayError.keychain
    }
    let stored = try JSONDecoder().decode(Self.self, from: data)
    return try Self(
      scope: stored.scope, relayURL: stored.relayURL.absoluteString,
      privateKeyHex: stored.privateKeyHex, pubkey: stored.pubkey
    )
  }

  func save() throws {
    let attributes: [String: Any] = [
      kSecValueData as String: try JSONEncoder().encode(self),
      kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
    ]
    let status = SecItemUpdate(Self.keychainQuery as CFDictionary, attributes as CFDictionary)
    if status == errSecItemNotFound {
      let query = Self.keychainQuery.merging(attributes) { _, value in value }
      guard SecItemAdd(query as CFDictionary, nil) == errSecSuccess else {
        throw WatchRelayError.keychain
      }
    } else if status != errSecSuccess {
      throw WatchRelayError.keychain
    }
  }

  static func remove() throws {
    let status = SecItemDelete(keychainQuery as CFDictionary)
    guard status == errSecSuccess || status == errSecItemNotFound else {
      throw WatchRelayError.keychain
    }
  }
}

enum WatchRelayError: Error, LocalizedError {
  case invalidSetup, keychain, invalidResponse, denied, unconfirmed
  case mention
  case http(Int)

  var errorDescription: String? {
    switch self {
    case .invalidSetup: return "Watch sign-in is not valid. Set up again with your iPhone."
    case .keychain: return "Unlock your watch to use its saved sign-in."
    case .invalidResponse: return "The relay response is not valid."
    case .denied: return "The relay denied access. Check your account and channel membership."
    case .unconfirmed: return "The message was not confirmed. Check the channel before you send again."
    case .mention: return "A mentioned name is missing or has more than one match. Use a direct message instead."
    case .http(let status): return "The relay request failed (HTTP \(status)). Try Refresh."
    }
  }
}

final class WatchRelay: NSObject, URLSessionTaskDelegate {
  let credentials: WatchCredentials
  private let configuration: URLSessionConfiguration
  private var relayPubkey: String?
  private lazy var session: URLSession = {
    let config = configuration
    config.timeoutIntervalForRequest = 20
    config.timeoutIntervalForResource = 25
    config.urlCache = nil
    return URLSession(configuration: config, delegate: self, delegateQueue: nil)
  }()

  init(credentials: WatchCredentials, configuration: URLSessionConfiguration = .ephemeral) {
    self.credentials = credentials
    self.configuration = configuration
  }

  func close() { session.invalidateAndCancel() }

  func urlSession(
    _ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void
  ) {
    completionHandler(nil)
  }

  func request(_ message: [String: Any]) async throws -> [String: Any] {
    switch message["action"] as? String {
    case "channels": return try await channels()
    case "messages":
      guard message["scope"] as? String == credentials.scope,
        let id = message["channelId"] as? String, !id.isEmpty, id.count <= 128
      else { throw WatchRelayError.invalidSetup }
      return try await messages(in: id, dm: message["dm"] as? Bool == true)
    case "send":
      guard message["scope"] as? String == credentials.scope,
        let id = message["channelId"] as? String, !id.isEmpty, id.count <= 128,
        let text = message["text"] as? String, text.utf16.count <= 2000,
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      else { throw WatchRelayError.invalidSetup }
      let tags = try await sendTags(channelID: id, text: text)
      let event = try NostrHTTPAuth.signedEvent(
        kind: 9, tags: tags, content: text.trimmingCharacters(in: .whitespacesAndNewlines),
        privateKeyHex: credentials.privateKeyHex
      )
      let response = try await post("events", body: JSONEncoder().encode(event))
      guard let result = try JSONSerialization.jsonObject(with: response) as? [String: Any],
        result["accepted"] as? Bool == true, result["event_id"] as? String == event.id
      else { throw WatchRelayError.unconfirmed }
      return ["sent": true, "scope": credentials.scope]
    default: throw WatchRelayError.invalidResponse
    }
  }

  private func metadataKey() async throws -> String {
    if let relayPubkey { return relayPubkey }
    var request = URLRequest(url: credentials.relayURL)
    request.setValue("application/nostr+json", forHTTPHeaderField: "Accept")
    let data = try await perform(request)
    guard let document = try JSONSerialization.jsonObject(with: data) as? [String: Any],
      let key = document["self"] as? String, key.utf8.count == 64,
      key.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) })
    else { throw WatchRelayError.invalidResponse }
    relayPubkey = key
    return key
  }

  private func post(_ path: String, body: Data) async throws -> Data {
    let url = credentials.relayURL.appendingPathComponent(path)
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.httpBody = body
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.setValue(
      try NostrHTTPAuth.authorizationHeader(
        url: url, method: "POST", body: body, privateKeyHex: credentials.privateKeyHex,
        nonce: UUID().uuidString
      ), forHTTPHeaderField: "Authorization"
    )
    return try await perform(request)
  }

  private func perform(_ request: URLRequest) async throws -> Data {
    let (data, response) = try await session.data(for: request)
    guard let response = response as? HTTPURLResponse else { throw WatchRelayError.invalidResponse }
    if response.statusCode == 401 || response.statusCode == 403 { throw WatchRelayError.denied }
    guard response.statusCode == 200 else { throw WatchRelayError.http(response.statusCode) }
    guard data.count <= 2_000_000 else { throw WatchRelayError.invalidResponse }
    return data
  }

  private func query(_ filters: [[String: Any]]) async throws -> [VerifiedNostrEvent] {
    let filters = filters.map { $0.merging(["consistency": "strong"]) { _, value in value } }
    let body = try JSONSerialization.data(withJSONObject: filters, options: [.withoutEscapingSlashes])
    let data = try await post("query", body: body)
    let events = try JSONDecoder().decode([VerifiedNostrEvent].self, from: data)
    guard events.count <= 1000, events.allSatisfy({ $0.hasValidIDAndSignature() }) else {
      throw WatchRelayError.invalidResponse
    }
    return events
  }

  private func sendTags(channelID: String, text: String) async throws -> [[String]] {
    let key = try await metadataKey()
    let events = try await query([
      ["kinds": [39000, 39002], "authors": [key], "#d": [channelID], "limit": 2]
    ])
    guard let meta = events.first(where: { $0.kind == 39000 && $0.pubkey == key && $0.tag("d") == channelID }),
      let members = events.first(where: { $0.kind == 39002 && $0.pubkey == key && $0.tag("d") == channelID }),
      members.tags.contains(where: { $0.count >= 2 && $0[0] == "p" && $0[1] == credentials.pubkey }),
      meta.tag("archived") != "true"
    else { throw WatchRelayError.denied }
    let type = meta.tag("t") ?? (meta.tags.contains { $0.first == "hidden" } ? "dm" : "stream")
    guard type == "dm" || type == "stream" else { throw WatchRelayError.denied }
    let peers = Set(members.tags.filter { $0.count >= 2 && $0[0] == "p" && $0[1] != credentials.pubkey }.map { $0[1] })
    var recipients = type == "dm" ? peers : []
    let pattern = try NSRegularExpression(pattern: "@([\\p{L}\\p{N}_]+)")
    let names = pattern.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap {
      Range($0.range(at: 1), in: text).map { String(text[$0]).lowercased() }
    }
    if !names.isEmpty {
      guard peers.count <= 256 else { throw WatchRelayError.mention }
      let labels = try await profileLabels(Array(peers))
      for name in names {
        let matches = labels.filter {
          let label = $0.value.lowercased()
          return label == name || label.split(whereSeparator: { $0.isWhitespace }).first.map(String.init) == name
        }
        guard matches.count == 1, let pubkey = matches.first?.key else { throw WatchRelayError.mention }
        recipients.insert(pubkey)
      }
    }
    return [["h", channelID]] + recipients.sorted().map { ["p", $0] }
  }

  private func channels() async throws -> [String: Any] {
    let key = try await metadataKey()
    let memberships = try await query([
      ["kinds": [39002], "authors": [key], "#p": [credentials.pubkey], "limit": 500]
    ])
    let ids = Set(memberships.filter {
      $0.kind == 39002 && $0.pubkey == key && $0.tags.contains { $0.count >= 2 && $0[0] == "p" && $0[1] == credentials.pubkey }
    }.compactMap { $0.tag("d") })
    if ids.isEmpty { return ["scope": credentials.scope, "channels": []] }
    let selected = Array(ids.sorted().prefix(128))
    let metas = try await query([
      ["kinds": [39000], "authors": [key], "#d": selected, "limit": 128]
    ])
    let latest = Self.latest(metas.filter { $0.kind == 39000 && $0.pubkey == key }, by: { $0.tag("d") })
    let visible = latest.values.filter {
      guard let id = $0.tag("d"), ids.contains(id), $0.tag("archived") != "true" else { return false }
      let type = $0.tag("t") ?? ($0.tags.contains { $0.first == "hidden" } ? "dm" : "stream")
      return type == "stream" || type == "dm"
    }
    let peers = Set(visible.flatMap { event in
      event.tags.filter { $0.count >= 2 && $0[0] == "p" && $0[1] != credentials.pubkey }.map { $0[1] }
    })
    let profiles = try await profileLabels(Array(peers.sorted().prefix(256)))
    let result: [[String: Any]] = visible.map { event in
      let isDM = event.tag("t") == "dm" || event.tags.contains { $0.first == "hidden" }
      let labels = event.tags.filter { $0.count >= 2 && $0[0] == "p" && $0[1] != credentials.pubkey }
        .map { profiles[$0[1]] ?? String($0[1].prefix(8)) }
      let name = isDM && !labels.isEmpty ? labels.joined(separator: ", ") : event.tag("name") ?? "Channel"
      return ["id": event.tag("d")!, "name": String(name.unicodeScalars.prefix(64)), "dm": isDM]
    }.sorted { ($0["name"] as! String).localizedCaseInsensitiveCompare($1["name"] as! String) == .orderedAscending }
    return ["scope": credentials.scope, "channels": Array(result.prefix(30))]
  }

  private func profileLabels(_ authors: [String]) async throws -> [String: String] {
    if authors.isEmpty { return [:] }
    let profiles = try await query([["kinds": [0], "authors": authors, "limit": authors.count]])
    var labels: [String: String] = [:]
    for event in Self.latest(profiles.filter { $0.kind == 0 && authors.contains($0.pubkey) }, by: { $0.pubkey }).values {
      guard let data = event.content.data(using: .utf8),
        let profile = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
      else { continue }
      let name = (profile["display_name"] as? String) ?? (profile["name"] as? String)
      if let name, !name.isEmpty { labels[event.pubkey] = String(name.unicodeScalars.prefix(32)) }
    }
    return labels
  }

  private func messages(in id: String, dm: Bool) async throws -> [String: Any] {
    let originals = try await query([["kinds": [9, 40002, 40008], "#h": [id], "limit": 40]])
      .filter { [9, 40002, 40008].contains($0.kind) && $0.tag("h") == id }
    if originals.isEmpty { return ["scope": credentials.scope, "messages": []] }
    let ids = originals.map(\.id)
    let changes = try await query([
      ["kinds": [5, 9005, 40003], "#e": ids, "#h": [id], "limit": 200]
    ])
    let recipients = dm ? [] : originals.flatMap { $0.tags.filter { $0.count >= 2 && $0[0] == "p" }.map { $0[1].lowercased() } }
    let labels = try await profileLabels(Array(Set(originals.map(\.pubkey) + recipients).sorted().prefix(256)))
    return ["scope": credentials.scope, "messages": Self.timeline(originals + changes, channelID: id, labels: labels, dm: dm)]
  }

  static func timeline(_ events: [VerifiedNostrEvent], channelID: String, labels: [String: String], dm: Bool = false) -> [[String: Any]] {
    let scoped = events.filter { $0.tag("h") == channelID }
    let deleted = Set(scoped.filter { $0.kind == 5 || $0.kind == 9005 }.flatMap {
      $0.tags.filter { $0.count >= 2 && $0[0] == "e" }.map { $0[1] }
    })
    let edits = latest(scoped.filter { $0.kind == 40003 && !deleted.contains($0.id) }, by: {
      $0.tags.last { $0.count >= 2 && $0[0] == "e" }?[1]
    })
    return scoped.filter { [9, 40002, 40008].contains($0.kind) && !deleted.contains($0.id) }
      .sorted { $0.createdAt == $1.createdAt ? $0.id < $1.id : $0.createdAt < $1.createdAt }
      .suffix(20).map { event in
        let text = edits[event.id]?.content ?? event.content
        return ["id": event.id, "author": labels[event.pubkey] ?? String(event.pubkey.prefix(8)),
          "text": String(text.unicodeScalars.prefix(300)),
          "notified": dm ? [] : notifiedLabels(event, text: text, labels: labels)]
      }
  }

  // ponytail: plain "@Label" text match, not the iPhone mention binder
  static func notifiedLabels(_ event: VerifiedNostrEvent, text: String, labels: [String: String]) -> [String] {
    var seen: Set<String> = [event.pubkey.lowercased()]
    return event.tags.compactMap { tag in
      guard tag.count >= 2, tag[0] == "p", !tag[1].isEmpty, seen.insert(tag[1].lowercased()).inserted else { return nil }
      let label = labels[tag[1].lowercased()] ?? String(tag[1].lowercased().prefix(8))
      return text.range(of: "@" + label, options: .caseInsensitive) == nil ? label : nil
    }
  }

  private static func latest(
    _ events: [VerifiedNostrEvent], by key: (VerifiedNostrEvent) -> String?
  ) -> [String: VerifiedNostrEvent] {
    var result: [String: VerifiedNostrEvent] = [:]
    for event in events {
      guard let id = key(event) else { continue }
      if let previous = result[id], previous.createdAt > event.createdAt ||
        (previous.createdAt == event.createdAt && previous.id < event.id) { continue }
      result[id] = event
    }
    return result
  }
}

extension VerifiedNostrEvent {
  func tag(_ name: String) -> String? {
    tags.first { $0.count >= 2 && $0[0] == name }?[1]
  }
}
