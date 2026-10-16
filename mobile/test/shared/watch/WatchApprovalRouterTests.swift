import XCTest
@testable import WatchCheck

final class WatchApprovalRouterTests: XCTestCase {
  private let target = BuzzApprovalTarget(relayURL: "https://buzz.example", eventID: String(repeating: "a", count: 64), communityID: "c1")

  func testPhoneFirstThenDirectThenFailureNotice() async {
    var log: [String] = []
    await WatchApprovalRouter.route(target: target, decision: .approve, phoneReachable: true,
      sendToPhone: { _, _ in log.append("phone"); return true },
      directCredentialsRelayHost: "buzz.example", sendDirect: { _, _ in log.append("direct") },
      notifyFailure: { log.append("fail") })
    await WatchApprovalRouter.route(target: target, decision: .deny, phoneReachable: false,
      sendToPhone: { _, _ in log.append("phone"); return true },
      directCredentialsRelayHost: "buzz.example", sendDirect: { _, decision in log.append("direct:\(decision.emoji)") },
      notifyFailure: { log.append("fail") })
    await WatchApprovalRouter.route(target: target, decision: .deny, phoneReachable: false,
      sendToPhone: { _, _ in true },
      directCredentialsRelayHost: "other.example", sendDirect: { _, _ in log.append("direct") },
      notifyFailure: { log.append("fail") })
    struct Down: Error {}
    await WatchApprovalRouter.route(target: target, decision: .deny, phoneReachable: true,
      sendToPhone: { _, _ in false },
      directCredentialsRelayHost: "buzz.example", sendDirect: { _, _ in throw Down() },
      notifyFailure: { log.append("fail") })
    XCTAssertEqual(log, ["phone", "direct:\u{274C}", "fail", "fail"])
  }

  func testApproveReachesTheRelayDirectlyAndThroughThePhone() async {
    var log: [String] = []
    await WatchApprovalRouter.route(target: target, decision: .approve, phoneReachable: false,
      sendToPhone: { _, _ in log.append("phone"); return true },
      directCredentialsRelayHost: "buzz.example", sendDirect: { _, decision in log.append("direct:\(decision.emoji)") },
      notifyFailure: { log.append("fail") })
    await WatchApprovalRouter.route(target: target, decision: .approve, phoneReachable: true,
      sendToPhone: { _, decision in log.append("phone:\(decision.emoji)"); return true },
      directCredentialsRelayHost: nil, sendDirect: { _, _ in log.append("direct") },
      notifyFailure: { log.append("fail") })
    XCTAssertEqual(log, ["direct:\u{2705}", "phone:\u{2705}"])
  }
}
