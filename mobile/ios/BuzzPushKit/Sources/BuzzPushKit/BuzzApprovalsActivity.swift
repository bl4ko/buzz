import CryptoKit
import Foundation

#if canImport(ActivityKit) && os(iOS)
  import ActivityKit
#endif

public struct BuzzApprovalsContentState: Codable, Hashable, Sendable {
  public var askEventID: String
  public var caseID: String?
  public var ask: String
  public var agent: String
  public var channel: String
  public var openCount: Int
  public var askedAt: Int
  public var decision: String?

  public init(
    askEventID: String,
    caseID: String? = nil,
    ask: String,
    agent: String,
    channel: String,
    openCount: Int,
    askedAt: Int,
    decision: String? = nil
  ) {
    self.askEventID = askEventID
    self.caseID = caseID
    self.ask = ask
    self.agent = agent
    self.channel = channel
    self.openCount = openCount
    self.askedAt = askedAt
    self.decision = decision
  }

  public var pendingDecision: BuzzApprovalDecision? {
    switch decision {
    case "approve": .approve
    case "deny": .deny
    default: nil
    }
  }

  public func marking(_ decision: BuzzApprovalDecision?) -> BuzzApprovalsContentState {
    var copy = self
    copy.decision = decision.map { $0 == .approve ? "approve" : "deny" }
    return copy
  }
}

#if canImport(ActivityKit) && os(iOS)
  @available(iOS 16.1, *)
  public struct BuzzApprovalsActivityAttributes: ActivityAttributes {
    public typealias ContentState = BuzzApprovalsContentState
    public var origin: String

    public init(origin: String) {
      self.origin = origin
    }
  }
#endif

public enum BuzzLiveActivityOrigin {
  public static func canonical(_ url: String) -> String? {
    guard let components = URLComponents(string: url),
      let scheme = components.scheme?.lowercased(), scheme == "https" || scheme == "wss",
      let host = components.host?.lowercased(), !host.isEmpty,
      components.user == nil, components.password == nil,
      components.query == nil, components.fragment == nil,
      components.path.isEmpty || components.path == "/",
      components.port.map({ (1...65535).contains($0) }) ?? true
    else { return nil }
    var result = URLComponents()
    result.scheme = "https"
    result.host = host
    result.port = components.port == 443 ? nil : components.port
    return result.string
  }

  public static func hashHex(_ origin: String) -> String? {
    guard canonical(origin) == origin else { return nil }
    return SHA256.hash(data: Data(origin.utf8)).map { String(format: "%02x", $0) }.joined()
  }

  public static func origins(in snapshot: PushLeaseSnapshot) -> [String] {
    Array(Set(snapshot.communities.compactMap { canonical($0.relayUrl) })).sorted()
  }

  public static func isEventID(_ value: String) -> Bool {
    value.utf8.count == 64 && value.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) }
  }
}

public enum BuzzLiveActivityLink {
  private static let unreserved = CharacterSet(
    charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")

  public static func tasks(origin: String, askEventID: String) -> URL? {
    guard BuzzLiveActivityOrigin.canonical(origin) == origin,
      BuzzLiveActivityOrigin.isEventID(askEventID),
      let encoded = origin.addingPercentEncoding(withAllowedCharacters: unreserved)
    else { return nil }
    return URL(string: "buzz://tasks?origin=\(encoded)&event=\(askEventID)")
  }
}

public struct BuzzLiveActivityInstance: Equatable, Sendable {
  public let id: String
  public let origin: String
  public let askedAt: Int

  public init(id: String, origin: String, askedAt: Int) {
    self.id = id
    self.origin = origin
    self.askedAt = askedAt
  }

  public static func activitiesToEnd(
    _ items: [BuzzLiveActivityInstance],
    allowedOrigins: Set<String>? = nil
  ) -> [String] {
    var keep: [String: (index: Int, askedAt: Int)] = [:]
    for (index, item) in items.enumerated() where allowedOrigins?.contains(item.origin) ?? true {
      if let current = keep[item.origin], current.askedAt > item.askedAt { continue }
      keep[item.origin] = (index, item.askedAt)
    }
    let kept = Set(keep.values.map(\.index))
    return items.enumerated().filter { !kept.contains($0.offset) }.map(\.element.id)
  }
}
