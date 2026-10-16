import Foundation
import UserNotifications
import WatchConnectivity

final class WatchApprovalActions: NSObject, UNUserNotificationCenterDelegate {
  static let shared = WatchApprovalActions()

  func register() {
    let center = UNUserNotificationCenter.current()
    center.delegate = self
    center.setNotificationCategories([BuzzApprovalCategory.category()])
  }

  func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
    [.banner, .sound]
  }

  func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
    guard let decision = BuzzApprovalDecision(rawValue: response.actionIdentifier),
      let target = BuzzApprovalTarget.decodeIfPresent(from: response.notification.request.content.userInfo)
    else { return }
    let credentials = try? WatchCredentials.load()
    await WatchApprovalRouter.route(
      target: target,
      decision: decision,
      phoneReachable: WCSession.isSupported() && WCSession.default.isReachable,
      sendToPhone: { target, decision in await Self.sendToPhone(target, decision) },
      directCredentialsRelayHost: credentials?.relayURL.host,
      sendDirect: { target, decision in
        guard let credentials else { throw WatchRelayError.invalidSetup }
        let relay = WatchRelay(credentials: credentials)
        defer { relay.close() }
        _ = try await relay.request(["action": "react", "scope": credentials.scope, "eventId": target.eventID, "emoji": decision.emoji])
      },
      notifyFailure: {
        UNUserNotificationCenter.current().add(BuzzApprovalFailureNotice.request(body: "Open Bl4uzz on your iPhone and try again."))
      }
    )
  }

  private static func sendToPhone(_ target: BuzzApprovalTarget, _ decision: BuzzApprovalDecision) async -> Bool {
    await withCheckedContinuation { continuation in
      WCSession.default.sendMessage(
        ["action": "react", "target": target.userInfo, "decision": decision.rawValue],
        replyHandler: { reply in continuation.resume(returning: reply["sent"] as? Bool == true) },
        errorHandler: { _ in continuation.resume(returning: false) }
      )
    }
  }
}
