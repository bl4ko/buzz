import Foundation

public enum BuzzLiveActivitySigningKeychain {
  public static let service = "buzz.liveactivity.signing"

  public static func privateKey(communityID: String, accessGroup: String?) -> String? {
    BuzzPushSigningKeychain.privateKey(service: service, communityID: communityID, accessGroup: accessGroup)
  }
}

public enum BuzzLiveActivityDecisionRunner {
  public static let lockedBody = "Unlock your iPhone and try again."

  public static func run(
    origin: String,
    askEventID: String,
    decision: BuzzApprovalDecision,
    communityID: (String) -> String?,
    storedRelayURL: (String) -> String?,
    loadKey: (String) -> String?,
    mark: (BuzzApprovalDecision?) async -> Void,
    send: (BuzzApprovalTarget, BuzzApprovalDecision, String) async throws -> Void,
    notifyFailure: (String) -> Void
  ) async -> Bool {
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
    await mark(decision)
    do {
      try await send(BuzzApprovalTarget(relayURL: relay, eventID: askEventID, communityID: community), decision, key)
      return true
    } catch {
      await mark(nil)
      notifyFailure(BuzzApprovalActionHandler.failureBody)
      return false
    }
  }
}
