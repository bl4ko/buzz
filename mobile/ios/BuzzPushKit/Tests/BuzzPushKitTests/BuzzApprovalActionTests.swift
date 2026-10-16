import Foundation
import UserNotifications
import XCTest
@testable import BuzzPushKit

final class ApprovalHTTPStub: URLProtocol {
  static var handler: ((URLRequest) throws -> (Int, Data))?
  override class func canInit(with request: URLRequest) -> Bool { true }
  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
  override func startLoading() {
    do {
      let (status, data) = try Self.handler!(request)
      client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
      client?.urlProtocol(self, didLoad: data)
      client?.urlProtocolDidFinishLoading(self)
    } catch {
      client?.urlProtocol(self, didFailWithError: error)
    }
  }
  override func stopLoading() {}
}

final class BuzzApprovalActionTests: XCTestCase {
  private let key = String(repeating: "0", count: 63) + "1"
  private let eventID = String(repeating: "a", count: 64)
  private var target: BuzzApprovalTarget { BuzzApprovalTarget(relayURL: "https://buzz.example", eventID: eventID, communityID: "community-1") }

  private func session() -> URLSession {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [ApprovalHTTPStub.self]
    return URLSession(configuration: configuration)
  }

  override func tearDown() { ApprovalHTTPStub.handler = nil }

  func testDecodeAcceptsOnlyTheContractShape() {
    XCTAssertEqual(BuzzApprovalTarget.decodeIfPresent(from: [BuzzApprovalTarget.userInfoKey: target.userInfo]), target)
    var extra = target.userInfo
    extra["x"] = "y"
    XCTAssertNil(BuzzApprovalTarget.decodeIfPresent(from: [BuzzApprovalTarget.userInfoKey: extra]))
    var upper = target.userInfo
    upper["event_id"] = eventID.uppercased()
    XCTAssertNil(BuzzApprovalTarget.decodeIfPresent(from: [BuzzApprovalTarget.userInfoKey: upper]))
    var plain = target.userInfo
    plain["relay_url"] = "http://buzz.example"
    XCTAssertNil(BuzzApprovalTarget.decodeIfPresent(from: [BuzzApprovalTarget.userInfoKey: plain]))
    plain["relay_url"] = "http://127.0.0.1:3095"
    #if DEBUG
      XCTAssertNotNil(BuzzApprovalTarget.decodeIfPresent(from: [BuzzApprovalTarget.userInfoKey: plain]))
    #else
      XCTAssertNil(BuzzApprovalTarget.decodeIfPresent(from: [BuzzApprovalTarget.userInfoKey: plain]))
    #endif
  }

  func testReactionIsASignedKind7WithOnlyTheTargetTag() throws {
    let approve = try BuzzApprovalReactionSender.reaction(for: target, decision: .approve, privateKeyHex: key)
    XCTAssertEqual(approve.kind, 7)
    XCTAssertEqual(approve.tags, [["e", eventID]])
    XCTAssertEqual(approve.content, "\u{2705}")
    XCTAssertTrue(approve.hasValidIDAndSignature())
    XCTAssertEqual(try BuzzApprovalReactionSender.reaction(for: target, decision: .deny, privateKeyHex: key).content, "\u{274C}")
  }

  func testSendRequiresTheMatchingAcceptedReceipt() async throws {
    var accepted = true
    var matching = true
    ApprovalHTTPStub.handler = { request in
      XCTAssertEqual(request.url?.absoluteString, "https://buzz.example/events")
      XCTAssertEqual(request.timeoutInterval, 15)
      XCTAssertTrue(request.value(forHTTPHeaderField: "Authorization")?.hasPrefix("Nostr ") == true)
      var data = request.httpBody ?? Data()
      if request.httpBody == nil, let stream = request.httpBodyStream {
        stream.open()
        defer { stream.close() }
        var buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
          let count = stream.read(&buffer, maxLength: buffer.count)
          if count <= 0 { break }
          data.append(contentsOf: buffer.prefix(count))
        }
      }
      let event = try JSONDecoder().decode(VerifiedNostrEvent.self, from: data)
      return (200, try JSONSerialization.data(withJSONObject: ["accepted": accepted, "event_id": matching ? event.id : "wrong"]))
    }
    let sender = BuzzApprovalReactionSender(session: session())
    try await sender.send(target, decision: .approve, privateKeyHex: key)
    accepted = false
    await XCTAssertThrowsErrorAsync { try await sender.send(self.target, decision: .approve, privateKeyHex: self.key) }
    accepted = true
    matching = false
    await XCTAssertThrowsErrorAsync { try await sender.send(self.target, decision: .approve, privateKeyHex: self.key) }
  }

  func testFailedApprovalPostsLocalFailureNotice() async {
    var notices: [String] = []
    await BuzzApprovalActionHandler.handle(target: target, decision: .approve, storedRelayURL: { _ in self.target.relayURL }, loadKey: { _ in nil }, send: { _, _, _ in XCTFail("no key, no send") }, notifyFailure: { notices.append($0) })
    struct Refused: Error {}
    await BuzzApprovalActionHandler.handle(target: target, decision: .deny, storedRelayURL: { _ in self.target.relayURL }, loadKey: { _ in self.key }, send: { _, _, _ in throw Refused() }, notifyFailure: { notices.append($0) })
    await BuzzApprovalActionHandler.handle(target: target, decision: .deny, storedRelayURL: { _ in self.target.relayURL }, loadKey: { _ in self.key }, send: { _, _, _ in }, notifyFailure: { notices.append($0) })
    XCTAssertEqual(notices.count, 2)
    let request = BuzzApprovalFailureNotice.request(body: notices[0])
    XCTAssertEqual(request.content.title, "Approval not sent")
    XCTAssertEqual(request.content.body, "Open Buzz and try again.")
  }

  func testRelayThatDiffersFromTheStoredOneIsRefusedBeforeSigning() async {
    var notices: [String] = []
    var keyLoads = 0
    await BuzzApprovalActionHandler.handle(
      target: target, decision: .approve,
      storedRelayURL: { _ in "https://other.example" },
      loadKey: { _ in keyLoads += 1; return self.key },
      send: { _, _, _ in XCTFail("mismatched relay must not be contacted") },
      notifyFailure: { notices.append($0) })
    await BuzzApprovalActionHandler.handle(
      target: target, decision: .approve,
      storedRelayURL: { _ in nil },
      loadKey: { _ in keyLoads += 1; return self.key },
      send: { _, _, _ in XCTFail("unknown community must not be contacted") },
      notifyFailure: { notices.append($0) })
    XCTAssertEqual(notices.count, 2)
    XCTAssertEqual(keyLoads, 0)
  }

  func testStoredRelayLookupReadsTheSnapshot() throws {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("approval-snapshot-\(UUID().uuidString).json")
    defer { try? FileManager.default.removeItem(at: url) }
    let snapshot = PushLeaseSnapshot(communities: [PushLeaseCommunity(id: "community-1", name: "Home", relayUrl: "wss://buzz.example/", pubkey: nil, policies: [])])
    try JSONEncoder().encode(snapshot).write(to: url)
    XCTAssertEqual(BuzzPushStoredRelay.relayURL(communityID: "community-1", snapshotURL: url), "https://buzz.example")
    XCTAssertNil(BuzzPushStoredRelay.relayURL(communityID: "other", snapshotURL: url))
  }

  func testCategoryOffersApproveAndDeny() {
    let category = BuzzApprovalCategory.category()
    XCTAssertEqual(category.identifier, "BUZZ_APPROVAL")
    XCTAssertEqual(category.actions.map(\.identifier), ["buzz.approval.approve", "buzz.approval.deny"])
    XCTAssertEqual(category.actions.map(\.title), ["Approve", "Deny"])
    XCTAssertTrue(category.actions.allSatisfy { $0.options.contains(.authenticationRequired) })
    XCTAssertTrue(category.actions[1].options.contains(.destructive))
  }

  func testApprovalCategoryNeedsATarget() {
    let untargeted = BuzzPushResolution(
      title: "Hermes", body: "Run rm?", subtitle: nil, threadIdentifier: nil, notificationType: .approval)
    XCTAssertNil(untargeted.categoryIdentifier)
    XCTAssertEqual(untargeted.notificationSoundName, "approval.wav")
    let targeted = BuzzPushResolution(
      title: "Hermes", body: "Run rm?", subtitle: nil, threadIdentifier: nil, notificationType: .approval,
      approvalTarget: target)
    XCTAssertEqual(targeted.categoryIdentifier, "BUZZ_APPROVAL")
  }
}

func XCTAssertThrowsErrorAsync(_ body: () async throws -> Void, file: StaticString = #filePath, line: UInt = #line) async {
  do {
    try await body()
    XCTFail("Expected an error", file: file, line: line)
  } catch {}
}
