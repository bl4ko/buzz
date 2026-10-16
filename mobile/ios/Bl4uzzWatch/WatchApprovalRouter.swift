import Foundation

enum WatchApprovalRouter {
  static func route(
    target: BuzzApprovalTarget,
    decision: BuzzApprovalDecision,
    phoneReachable: Bool,
    sendToPhone: (BuzzApprovalTarget, BuzzApprovalDecision) async -> Bool,
    directCredentialsRelayHost: String?,
    sendDirect: (BuzzApprovalTarget, BuzzApprovalDecision) async throws -> Void,
    notifyFailure: () -> Void
  ) async {
    if phoneReachable, await sendToPhone(target, decision) { return }
    guard let host = directCredentialsRelayHost, URL(string: target.relayURL)?.host == host else {
      notifyFailure()
      return
    }
    do {
      try await sendDirect(target, decision)
    } catch {
      notifyFailure()
    }
  }
}
