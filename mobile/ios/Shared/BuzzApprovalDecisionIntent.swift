import ActivityKit
import AppIntents
import BuzzPushKit
import Foundation
import UserNotifications

@available(iOS 18.0, *)
struct BuzzApprovalDecisionIntent: LiveActivityIntent {
  static let title: LocalizedStringResource = "Decide approval"
  static var authenticationPolicy: IntentAuthenticationPolicy { .requiresLocalDeviceAuthentication }
  static var isDiscoverable: Bool { false }

  @Parameter(title: "Origin") var origin: String
  @Parameter(title: "Ask") var askEventID: String
  @Parameter(title: "Decision") var decision: String

  init() {}

  init(origin: String, askEventID: String, decision: BuzzApprovalDecision) {
    self.origin = origin
    self.askEventID = askEventID
    self.decision = BuzzApprovalIntentRunner.wire(decision)
  }

  static func signingKey(communityID: String, accessGroup: String?) -> String? {
    BuzzLiveActivitySigningKeychain.privateKey(communityID: communityID, accessGroup: accessGroup)
  }

  func perform() async throws -> some IntentResult {
    await BuzzApprovalIntentRunner.perform(
      origin: origin, askEventID: askEventID, decision: decision, loadKey: Self.signingKey)
    return .result()
  }
}

@available(iOS 18.0, *)
struct BuzzWatchApprovalDecisionIntent: LiveActivityIntent {
  static let title: LocalizedStringResource = "Decide approval on Apple Watch"
  static var authenticationPolicy: IntentAuthenticationPolicy { .requiresAuthentication }
  static var isDiscoverable: Bool { false }

  @Parameter(title: "Origin") var origin: String
  @Parameter(title: "Ask") var askEventID: String
  @Parameter(title: "Decision") var decision: String

  init() {}

  init(origin: String, askEventID: String, decision: BuzzApprovalDecision) {
    self.origin = origin
    self.askEventID = askEventID
    self.decision = BuzzApprovalIntentRunner.wire(decision)
  }

  static func signingKey(communityID: String, accessGroup: String?) -> String? {
    BuzzPushSigningKeychain.privateKey(communityID: communityID, accessGroup: accessGroup)
  }

  func perform() async throws -> some IntentResult {
    await BuzzApprovalIntentRunner.perform(
      origin: origin, askEventID: askEventID, decision: decision, loadKey: Self.signingKey)
    return .result()
  }
}

@available(iOS 18.0, *)
enum BuzzApprovalIntentRunner {
  static func wire(_ decision: BuzzApprovalDecision) -> String {
    decision == .approve ? "approve" : "deny"
  }

  static func perform(
    origin: String,
    askEventID: String,
    decision: String,
    loadKey: @escaping (String, String?) -> String?
  ) async {
    guard let decision = BuzzApprovalDecision.allCases.first(where: { wire($0) == decision }) else { return }
    let accessGroup = Bundle.main.object(forInfoDictionaryKey: "BuzzKeychainAccessGroup") as? String
    let appGroup = Bundle.main.object(forInfoDictionaryKey: "BuzzAppGroupIdentifier") as? String
    let marker = BuzzApprovalActivityMarker(origin: origin, askEventID: askEventID)
    _ = await BuzzLiveActivityDecisionRunner.run(
      origin: origin,
      askEventID: askEventID,
      decision: decision,
      communityID: { BuzzPushStoredRelay.communityID(origin: $0, appGroupIdentifier: appGroup) },
      storedRelayURL: { BuzzPushStoredRelay.relayURL(communityID: $0, appGroupIdentifier: appGroup) },
      loadKey: { loadKey($0, accessGroup) },
      mark: { await marker.mark($0) },
      send: { try await BuzzApprovalReactionSender().send($0, decision: $1, privateKeyHex: $2) },
      notifyFailure: { body in
        UNUserNotificationCenter.current().add(BuzzApprovalFailureNotice.request(body: body))
      }
    )
  }
}

@available(iOS 18.0, *)
actor BuzzApprovalActivityMarker {
  static let pendingStaleSeconds: TimeInterval = 60

  private let origin: String
  private let askEventID: String
  private var previousStaleDates: [String: Date?] = [:]

  init(origin: String, askEventID: String) {
    self.origin = origin
    self.askEventID = askEventID
  }

  func mark(_ decision: BuzzApprovalDecision?) async {
    for activity in Activity<BuzzApprovalsActivityAttributes>.activities
    where activity.attributes.origin == origin && activity.content.state.askEventID == askEventID {
      let staleDate: Date?
      if decision != nil {
        previousStaleDates[activity.id] = activity.content.staleDate
        staleDate = Date().addingTimeInterval(Self.pendingStaleSeconds)
      } else {
        staleDate = previousStaleDates[activity.id] ?? activity.content.staleDate
      }
      await activity.update(
        ActivityContent(
          state: activity.content.state.marking(decision),
          staleDate: staleDate,
          relevanceScore: activity.content.relevanceScore
        )
      )
    }
  }
}
