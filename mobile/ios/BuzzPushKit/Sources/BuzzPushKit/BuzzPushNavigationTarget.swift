import Foundation

/// A stable destination attached by the notification service extension after
/// it resolves and verifies the event that produced a push wake.
public struct BuzzPushNavigationTarget: Codable, Equatable, Sendable {
  public static let userInfoKey = "buzz_push_navigation"

  public let eventID: String
  public let communityID: String
  public let channelID: String
  public let threadRootID: String?

  public init(eventID: String, communityID: String, channelID: String, threadRootID: String? = nil) {
    self.eventID = eventID
    self.communityID = communityID
    self.channelID = channelID
    self.threadRootID = threadRootID
  }

  public var userInfoValue: [String: String] {
    var value = [
      "event_id": eventID,
      "community_id": communityID,
      "channel_id": channelID,
    ]
    value["thread_root_id"] = threadRootID
    return value
  }

  /// Decodes a target without trusting other fields from the APNs payload.
  public static func decodeIfPresent(
    from userInfo: [AnyHashable: Any]
  ) -> BuzzPushNavigationTarget? {
    guard let raw = userInfo[userInfoKey] as? [String: Any],
      raw.count == (raw["thread_root_id"] == nil ? 3 : 4),
      let eventID = raw["event_id"] as? String,
      let communityID = raw["community_id"] as? String,
      let channelID = raw["channel_id"] as? String,
      !eventID.isEmpty,
      !communityID.isEmpty,
      !channelID.isEmpty
    else {
      return nil
    }
    let threadRootID = raw["thread_root_id"] as? String
    if raw["thread_root_id"] != nil, threadRootID?.isEmpty != false {
      return nil
    }
    return BuzzPushNavigationTarget(
      eventID: eventID,
      communityID: communityID,
      channelID: channelID,
      threadRootID: threadRootID
    )
  }

}

/// Thread-safe one-item buffer spanning notification delivery and Flutter
/// engine startup during a cold notification launch.
public final class BuzzPushNavigationBuffer: @unchecked Sendable {
  private let lock = NSLock()
  private var target: BuzzPushNavigationTarget?

  public init() {}

  public func record(_ target: BuzzPushNavigationTarget) {
    lock.lock()
    self.target = target
    lock.unlock()
  }

  public func peek() -> BuzzPushNavigationTarget? {
    lock.lock()
    defer { lock.unlock() }
    return target
  }

  public func take() -> BuzzPushNavigationTarget? {
    lock.lock()
    defer { lock.unlock() }
    let current = target
    target = nil
    return current
  }

  public func remove(ifMatching expected: BuzzPushNavigationTarget) {
    lock.lock()
    defer { lock.unlock() }
    if target == expected {
      target = nil
    }
  }
}
