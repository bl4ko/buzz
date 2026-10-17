import Foundation
import Security
import UserNotifications

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

public struct BuzzApprovalTarget: Codable, Equatable, Sendable {
  public static let userInfoKey = "buzz_push_approval"
  public let relayURL: String
  public let eventID: String
  public let communityID: String

  public init(relayURL: String, eventID: String, communityID: String) {
    self.relayURL = relayURL
    self.eventID = eventID
    self.communityID = communityID
  }

  public var userInfo: [String: String] {
    ["relay_url": relayURL, "event_id": eventID, "community_id": communityID]
  }

  private static var allowsLocalHTTP: Bool {
    #if DEBUG
      true
    #else
      false
    #endif
  }

  public static func decodeIfPresent(from userInfo: [AnyHashable: Any]) -> BuzzApprovalTarget? {
    guard let raw = userInfo[userInfoKey] as? [String: String], raw.count == 3,
      let relay = raw["relay_url"], let event = raw["event_id"], let community = raw["community_id"],
      event.utf8.count == 64,
      event.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }),
      !community.isEmpty, community.count <= 128,
      let url = URL(string: relay), let host = url.host, !host.isEmpty,
      url.scheme == "https" || (allowsLocalHTTP && url.scheme == "http" && (host == "127.0.0.1" || host == "localhost"))
    else { return nil }
    return BuzzApprovalTarget(relayURL: relay, eventID: event, communityID: community)
  }
}

public enum BuzzApprovalDecision: String, CaseIterable, Sendable {
  case approve = "buzz.approval.approve"
  case deny = "buzz.approval.deny"

  public var emoji: String { self == .approve ? "\u{2705}" : "\u{274C}" }
  public var title: String { self == .approve ? "Approve" : "Deny" }
}

public enum BuzzApprovalCategory {
  public static let identifier = "BUZZ_APPROVAL"

  public static func category() -> UNNotificationCategory {
    UNNotificationCategory(
      identifier: identifier,
      actions: BuzzApprovalDecision.allCases.map { decision in
        UNNotificationAction(
          identifier: decision.rawValue,
          title: decision.title,
          options: decision == .deny ? [.authenticationRequired, .destructive] : [.authenticationRequired]
        )
      },
      intentIdentifiers: [],
      options: []
    )
  }
}

public enum BuzzPushSigningKeychain {
  public static let service = "buzz.push.nse.signing"

  public static func privateKey(communityID: String, accessGroup: String?) -> String? {
    privateKey(service: service, communityID: communityID, accessGroup: accessGroup)
  }

  static func privateKey(service: String, communityID: String, accessGroup: String?) -> String? {
    var query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: communityID,
      kSecReturnData as String: true,
      kSecMatchLimit as String: kSecMatchLimitOne,
    ]
    if let accessGroup, !accessGroup.isEmpty {
      query[kSecAttrAccessGroup as String] = accessGroup
    }
    var item: CFTypeRef?
    guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess, let data = item as? Data else { return nil }
    return String(data: data, encoding: .utf8)
  }
}

public enum BuzzApprovalReactionError: Error, Equatable {
  case invalidRelay
  case rejected
}

public struct BuzzApprovalReactionSender {
  public static let requestTimeout: TimeInterval = 15
  private let session: URLSession

  public init(session: URLSession = .shared) {
    self.session = session
  }

  public static func reaction(for target: BuzzApprovalTarget, decision: BuzzApprovalDecision, privateKeyHex: String) throws -> VerifiedNostrEvent {
    try NostrHTTPAuth.signedEvent(kind: 7, tags: [["e", target.eventID]], content: decision.emoji, privateKeyHex: privateKeyHex)
  }

  public func send(_ target: BuzzApprovalTarget, decision: BuzzApprovalDecision, privateKeyHex: String) async throws {
    guard let base = URL(string: target.relayURL), let url = URL(string: "/events", relativeTo: base)?.absoluteURL else {
      throw BuzzApprovalReactionError.invalidRelay
    }
    let event = try Self.reaction(for: target, decision: decision, privateKeyHex: privateKeyHex)
    let body = try JSONEncoder().encode(event)
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.timeoutInterval = Self.requestTimeout
    request.httpBody = body
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.setValue(
      try NostrHTTPAuth.authorizationHeader(url: url, method: "POST", body: body, privateKeyHex: privateKeyHex, nonce: UUID().uuidString),
      forHTTPHeaderField: "Authorization"
    )
    let (data, response) = try await session.data(for: request)
    guard (response as? HTTPURLResponse)?.statusCode == 200, Self.isStored(data, eventID: event.id)
    else { throw BuzzApprovalReactionError.rejected }
  }

  public static func isStored(_ data: Data, eventID: String) -> Bool {
    guard let result = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
      result["event_id"] as? String == eventID
    else { return false }
    switch result["accepted"] as? Bool {
    case true: return true
    case false: return (result["message"] as? String)?.hasPrefix("duplicate:") == true
    default: return false
    }
  }
}

public enum BuzzApprovalActionHandler {
  public static let failureBody = "Open Buzz and try again."

  public static func handle(
    target: BuzzApprovalTarget,
    decision: BuzzApprovalDecision,
    storedRelayURL: (String) -> String?,
    loadKey: (String) -> String?,
    send: (BuzzApprovalTarget, BuzzApprovalDecision, String) async throws -> Void,
    notifyFailure: (String) -> Void
  ) async {
    guard storedRelayURL(target.communityID) == target.relayURL,
      let key = loadKey(target.communityID)
    else {
      notifyFailure(failureBody)
      return
    }
    do {
      try await send(target, decision, key)
    } catch {
      notifyFailure(failureBody)
    }
  }
}

public enum BuzzApprovalFailureNotice {
  public static func request(body: String) -> UNNotificationRequest {
    let content = UNMutableNotificationContent()
    content.title = "Approval not sent"
    content.body = body
    return UNNotificationRequest(identifier: "buzz.approval.failure.\(UUID().uuidString)", content: content, trigger: nil)
  }
}
