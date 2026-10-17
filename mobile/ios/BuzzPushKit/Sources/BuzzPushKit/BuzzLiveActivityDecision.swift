import Foundation

public enum BuzzLiveActivitySigningKeychain {
  public static let service = "buzz.liveactivity.signing"

  public static func privateKey(communityID: String, accessGroup: String?) -> String? {
    BuzzPushSigningKeychain.privateKey(service: service, communityID: communityID, accessGroup: accessGroup)
  }
}

public actor BuzzApprovalSendGate {
  public static let shared = BuzzApprovalSendGate()
  public static let retention: TimeInterval = 60

  private let now: @Sendable () -> Date
  private var sending: Set<String> = []
  private var sent: [String: Date] = [:]

  public init(now: @escaping @Sendable () -> Date = { Date() }) {
    self.now = now
  }

  public func claim(_ key: String) -> Bool {
    let current = now()
    sent = sent.filter { current.timeIntervalSince($0.value) < Self.retention }
    guard !sending.contains(key), sent[key] == nil else { return false }
    sending.insert(key)
    return true
  }

  public func finish(_ key: String, sent wasSent: Bool) {
    sending.remove(key)
    if wasSent { sent[key] = now() }
  }
}

public enum BuzzLiveActivityDecisionRunner {
  public static let lockedBody = "Unlock your iPhone and try again."

  public static func decidesInProcess(bundleURL: URL) -> Bool {
    bundleURL.pathExtension != "appex"
  }

  public static func run(
    origin: String,
    askEventID: String,
    decision: BuzzApprovalDecision,
    bundleURL: URL = Bundle.main.bundleURL,
    gate: BuzzApprovalSendGate = .shared,
    communityID: (String) -> String?,
    storedRelayURL: (String) -> String?,
    loadKey: (String) -> String?,
    mark: (BuzzApprovalDecision?) async -> Void,
    send: (BuzzApprovalTarget, BuzzApprovalDecision, String) async throws -> Void,
    notifyFailure: (String) -> Void
  ) async -> Bool {
    guard decidesInProcess(bundleURL: bundleURL) else { return false }
    guard BuzzLiveActivityOrigin.canonical(origin) == origin,
      BuzzLiveActivityOrigin.isEventID(askEventID),
      let community = communityID(origin),
      let relay = storedRelayURL(community),
      BuzzLiveActivityOrigin.canonical(relay) == origin
    else {
      notifyFailure(BuzzApprovalActionHandler.failureBody)
      return false
    }
    guard let key = loadKey(community) else {
      notifyFailure(lockedBody)
      return false
    }
    let claim = [origin, askEventID, decision.rawValue].joined(separator: " ")
    guard await gate.claim(claim) else { return true }
    await mark(decision)
    do {
      try await send(BuzzApprovalTarget(relayURL: relay, eventID: askEventID, communityID: community), decision, key)
      await gate.finish(claim, sent: true)
      return true
    } catch {
      await gate.finish(claim, sent: false)
      await mark(nil)
      notifyFailure(BuzzApprovalActionHandler.failureBody)
      return false
    }
  }
}
