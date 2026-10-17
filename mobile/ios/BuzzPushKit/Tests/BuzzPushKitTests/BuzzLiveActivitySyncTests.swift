import Foundation
import XCTest

@testable import BuzzPushKit

final class BuzzLiveActivityBindingTests: XCTestCase {
  private let origin = "https://buzz.bl4ko.com"
  private let relayA = String(repeating: "a", count: 64)
  private let relayB = String(repeating: "b", count: 64)

  func testBoundHashMatchesContract() {
    XCTAssertEqual(BuzzLiveActivityOrigin.boundHashDomain, "buzz.push.la-origin.v1")
    XCTAssertEqual(
      BuzzLiveActivityOrigin.boundHashHex(origin: origin, relayPubkey: relayA),
      "2dfd263b6fd5b66e15ba6f73320d811991eaca636560781788e0b858a4d51a61")
    XCTAssertEqual(
      BuzzLiveActivityOrigin.boundHashHex(origin: origin, relayPubkey: relayB),
      "2c2548c35bea272a6a39e83e81a8959c705966c22eba86d3cc3d98b40a7bf0c4")
    XCTAssertEqual(
      BuzzLiveActivityOrigin.boundHashHex(origin: "https://zeta.example", relayPubkey: relayA),
      "28bf895ca46e6f38fbc31819454aa8594536cd18bac46ea86e288c965c186692")
  }

  func testBoundHashRejectsNonCanonicalOriginAndBadRelayKey() {
    XCTAssertNil(BuzzLiveActivityOrigin.boundHashHex(origin: "wss://buzz.bl4ko.com", relayPubkey: relayA))
    XCTAssertNil(BuzzLiveActivityOrigin.boundHashHex(origin: "https://buzz.bl4ko.com:0", relayPubkey: relayA))
    XCTAssertNil(BuzzLiveActivityOrigin.boundHashHex(origin: origin, relayPubkey: relayA.uppercased()))
    XCTAssertNil(BuzzLiveActivityOrigin.boundHashHex(origin: origin, relayPubkey: String(relayA.dropLast())))
    XCTAssertNil(BuzzLiveActivityOrigin.boundHashHex(origin: origin, relayPubkey: ""))
  }
}

final class BuzzLiveActivityStartPlannerTests: XCTestCase {
  private let gateway = "https://push.example"
  private let handle = "22222222-2222-4222-8222-222222222222"
  private let otherHandle = "33333333-3333-4333-8333-333333333333"
  private let relayA = String(repeating: "a", count: 64)
  private let relayB = String(repeating: "b", count: 64)
  private let origins = ["https://buzz.bl4ko.com", "https://zeta.example"]
  private let token = Data([0x01, 0xab])
  private let now: Int64 = 1_760_640_000

  private func record(
    relay: String = "wss://buzz.bl4ko.com",
    relayPubkey: String? = nil,
    gatewayOrigin: String? = nil,
    handle: String?? = .none,
    keyId: String = "key-1",
    expiresAt: Int64 = 4_000_000_000,
    generation: Int64 = 1
  ) -> BuzzPushEndpointGrantRecord {
    BuzzPushEndpointGrantRecord(
      gatewayOrigin: gatewayOrigin ?? gateway, relayOrigin: relay, relayPubkey: relayPubkey ?? relayA,
      relayMetadataPubkey: relayPubkey ?? relayA, gatewayInstallationHandle: handle ?? self.handle,
      appAttestKeyId: keyId, installationId: String(repeating: "0", count: 32), endpointGrant: "grant",
      endpointHash: String(repeating: "1", count: 64), appProfile: BuzzDevPushEnrollmentDriver.appProfile,
      endpointEpoch: 1, generation: generation, expiresAt: expiresAt)
  }

  private func bothCommunities(handle: String? = nil, gatewayOrigin: String? = nil) -> [BuzzPushEndpointGrantRecord] {
    [
      record(gatewayOrigin: gatewayOrigin, handle: .some(handle ?? self.handle)),
      record(relay: "wss://zeta.example", relayPubkey: relayB, gatewayOrigin: gatewayOrigin, handle: .some(handle ?? self.handle)),
    ]
  }

  private func plan(
    records: [BuzzPushEndpointGrantRecord],
    origins: [String]?,
    enabled: Bool = true,
    token: Data?? = .none,
    registered: String? = nil
  ) -> BuzzLiveActivityStartRequest? {
    BuzzLiveActivityStartPlanner.request(
      records: records, origins: origins, activitiesEnabled: enabled, startToken: token ?? self.token, now: now,
      registeredFingerprint: registered)
  }

  func testRequestRegistersBoundHashesOfTheInstallation() throws {
    let request = try XCTUnwrap(plan(records: bothCommunities(), origins: origins))
    XCTAssertEqual(request.installation.gatewayOrigin, gateway)
    XCTAssertEqual(request.installation.handle, handle)
    XCTAssertEqual(request.installation.appAttestKeyId, "key-1")
    XCTAssertEqual(request.startToken, "01ab")
    XCTAssertEqual(
      request.originHashes,
      [
        "2dfd263b6fd5b66e15ba6f73320d811991eaca636560781788e0b858a4d51a61",
        try XCTUnwrap(BuzzLiveActivityOrigin.boundHashHex(origin: "https://zeta.example", relayPubkey: relayB)),
      ].sorted())
  }

  func testCommunityWithoutRelayKeyIsNotRegistered() throws {
    let request = try XCTUnwrap(plan(records: [record()], origins: origins + ["https://unknown.example"]))
    XCTAssertEqual(request.originHashes, ["2dfd263b6fd5b66e15ba6f73320d811991eaca636560781788e0b858a4d51a61"])
    XCTAssertNil(plan(records: [record()], origins: ["https://zeta.example"]))
  }

  func testRelayKeyOfAnotherInstallationIsNotUsed() throws {
    let records = [
      record(expiresAt: 4_000_000_100),
      record(relay: "wss://zeta.example", relayPubkey: relayB, handle: .some(otherHandle)),
    ]
    let request = try XCTUnwrap(plan(records: records, origins: origins))
    XCTAssertEqual(request.installation.handle, handle)
    XCTAssertEqual(request.originHashes, ["2dfd263b6fd5b66e15ba6f73320d811991eaca636560781788e0b858a4d51a61"])
  }

  func testNoInstallationSendsNothingSoNothingIsSaved() throws {
    XCTAssertNil(plan(records: [], origins: origins))
    XCTAssertNil(plan(records: [record(handle: .some(nil))], origins: origins))
    XCTAssertNil(plan(records: [record(expiresAt: now)], origins: origins))
    let later = try XCTUnwrap(plan(records: bothCommunities(), origins: origins))
    XCTAssertEqual(later.originHashes.count, 2)
  }

  func testUnchangedRegistrationSendsNothing() throws {
    let first = try XCTUnwrap(plan(records: bothCommunities(), origins: origins))
    XCTAssertNil(plan(records: bothCommunities(), origins: origins.reversed(), registered: first.fingerprint))
  }

  func testFingerprintCoversInstallationGatewayTokenAndHashes() throws {
    let base = try XCTUnwrap(plan(records: bothCommunities(), origins: origins))
    let reenrolled = try XCTUnwrap(
      plan(records: bothCommunities(handle: otherHandle), origins: origins, registered: base.fingerprint))
    let moved = try XCTUnwrap(
      plan(records: bothCommunities(gatewayOrigin: "https://push2.example"), origins: origins, registered: base.fingerprint))
    let newToken = try XCTUnwrap(
      plan(records: bothCommunities(), origins: origins, token: .some(Data([2])), registered: base.fingerprint))
    let rekeyed = try XCTUnwrap(
      plan(
        records: [record(), record(relay: "wss://zeta.example", relayPubkey: relayA)], origins: origins,
        registered: base.fingerprint))
    let fewer = try XCTUnwrap(plan(records: bothCommunities(), origins: [origins[0]], registered: base.fingerprint))
    let fingerprints = [base, reenrolled, moved, newToken, rekeyed, fewer].map(\.fingerprint)
    XCTAssertEqual(Set(fingerprints).count, fingerprints.count)
    XCTAssertEqual(reenrolled.installation.handle, otherHandle)
    XCTAssertEqual(moved.installation.gatewayOrigin, "https://push2.example")
  }

  func testWaitsForStartTokenWhenOriginsExist() {
    XCTAssertNil(plan(records: bothCommunities(), origins: origins, token: .some(nil)))
  }

  func testMissingSnapshotKeepsRegistrationWhileEnabled() {
    XCTAssertNil(plan(records: bothCommunities(), origins: nil, registered: "previous"))
  }

  func testTurningOffClearsOnlyAfterARegistration() throws {
    XCTAssertNil(plan(records: bothCommunities(), origins: origins, enabled: false))
    XCTAssertNil(plan(records: bothCommunities(), origins: [], token: .some(nil)))
    let on = try XCTUnwrap(plan(records: bothCommunities(), origins: origins))
    let off = try XCTUnwrap(plan(records: bothCommunities(), origins: nil, enabled: false, registered: on.fingerprint))
    XCTAssertNil(off.startToken)
    XCTAssertEqual(off.originHashes, [])
    XCTAssertNil(plan(records: bothCommunities(), origins: [], registered: off.fingerprint))
    let empty = try XCTUnwrap(plan(records: bothCommunities(), origins: [], registered: on.fingerprint))
    XCTAssertEqual(empty.fingerprint, off.fingerprint)
  }

  func testOriginLimitIsKept() throws {
    let many = (0..<20).map { "https://c\($0).example" }
    let records = many.map { record(relay: $0.replacingOccurrences(of: "https://", with: "wss://")) }
    let request = try XCTUnwrap(plan(records: records, origins: many))
    XCTAssertEqual(request.originHashes.count, BuzzLiveActivityRegistrar.maximumOrigins)
    XCTAssertEqual(request.originHashes, request.originHashes.sorted())
  }

  func testInstallationOriginHashUsesNewestGenerationRelayKey() throws {
    let records = [record(generation: 1), record(relayPubkey: relayB, generation: 2)]
    let installation = try XCTUnwrap(BuzzLiveActivityInstallation.current(records: records, now: now))
    XCTAssertEqual(
      installation.originHash("https://buzz.bl4ko.com"),
      BuzzLiveActivityOrigin.boundHashHex(origin: "https://buzz.bl4ko.com", relayPubkey: relayB))
    XCTAssertNil(installation.originHash("https://zeta.example"))
    XCTAssertNil(installation.originHash("wss://buzz.bl4ko.com"))
  }
}

final class BuzzLiveActivityDuplicateTests: XCTestCase {
  private let origin = "https://buzz.bl4ko.com"

  private func item(_ id: String, _ stale: TimeInterval?, origin: String? = nil) -> BuzzLiveActivityInstance {
    BuzzLiveActivityInstance(
      id: id, origin: origin ?? self.origin, staleDate: stale.map(Date.init(timeIntervalSince1970:)))
  }

  func testRegisteredTokenWinsAStaleDateTie() {
    let items = [item("z", 100), item("registered", 100)]
    XCTAssertEqual(BuzzLiveActivityInstance.activitiesToEnd(items, registered: [origin: "registered"]), ["z"])
    XCTAssertEqual(
      BuzzLiveActivityInstance.activitiesToEnd(items.reversed(), registered: [origin: "registered"]), ["z"])
  }

  func testNewerServerStartWinsOverRegisteredToken() {
    let items = [item("registered", 100), item("restarted", 500)]
    XCTAssertEqual(
      BuzzLiveActivityInstance.activitiesToEnd(items, registered: [origin: "registered"]), ["registered"])
  }

  func testKeepsLatestStaleDateWithoutRegisteredToken() {
    let items = [item("old", 100), item("new", 500), item("none", nil), item("other", 1, origin: "https://zeta.example")]
    XCTAssertEqual(Set(BuzzLiveActivityInstance.activitiesToEnd(items)), ["old", "none"])
    XCTAssertEqual(
      Set(BuzzLiveActivityInstance.activitiesToEnd(items, registered: [origin: "gone"])), ["old", "none"])
  }

  func testTieBreakDoesNotDependOnOrder() {
    let items = [item("b", 100), item("a", 100), item("c", 100)]
    let forward = BuzzLiveActivityInstance.activitiesToEnd(items)
    let backward = BuzzLiveActivityInstance.activitiesToEnd(items.reversed())
    XCTAssertEqual(Set(forward), Set(backward))
    XCTAssertEqual(forward.count, 2)
  }

  func testEndsActivitiesOfOriginsThatAreNotAllowed() {
    let items = [item("keep", 100), item("drop", 100, origin: "https://zeta.example")]
    XCTAssertEqual(
      BuzzLiveActivityInstance.activitiesToEnd(items, allowedOrigins: [origin], registered: ["https://zeta.example": "drop"]),
      ["drop"])
  }
}

final class BuzzLiveActivityUpdateTokenSyncTests: XCTestCase {
  private let origin = "https://buzz.bl4ko.com"

  private final class Gateway: @unchecked Sendable {
    private let lock = NSLock()
    private var script: [Error?]
    private var calls: [(String, Data?)] = []
    private var delays: [UInt64] = []
    private var waiters: [(Int, XCTestExpectation)] = []
    private var held: [CheckedContinuation<Void, Never>] = []
    private var holding: Bool

    convenience init(failures: Int = 0, error: Error = URLError(.notConnectedToInternet), holdRetries: Bool = false) {
      self.init(script: Array(repeating: error, count: failures), holdRetries: holdRetries)
    }

    init(script: [Error?], holdRetries: Bool = false) {
      self.script = script
      holding = holdRetries
    }

    private func locked<T>(_ body: () -> T) -> T {
      lock.lock()
      defer { lock.unlock() }
      return body()
    }

    var sent: [(String, Data?)] { locked { calls } }
    var slept: [UInt64] { locked { delays } }

    func expect(_ count: Int, _ expectation: XCTestExpectation) {
      locked { waiters.append((count, expectation)) }
      fire()
    }

    func send(_ origin: String, _ token: Data?) throws {
      let failure: Error? = locked {
        calls.append((origin, token))
        return script.isEmpty ? nil : script.removeFirst()
      }
      fire()
      if let failure { throw failure }
    }

    func sleep(_ seconds: UInt64) async {
      locked { delays.append(seconds) }
      await withCheckedContinuation { continuation in
        let resume = locked { () -> Bool in
          guard holding else { return true }
          held.append(continuation)
          return false
        }
        if resume { continuation.resume() }
      }
    }

    func releaseRetries() {
      let continuations = locked { () -> [CheckedContinuation<Void, Never>] in
        holding = false
        defer { held = [] }
        return held
      }
      continuations.forEach { $0.resume() }
    }

    private func fire() {
      let ready: [XCTestExpectation] = locked {
        let count = calls.count
        let hits = waiters.filter { $0.0 <= count }.map(\.1)
        waiters.removeAll { $0.0 <= count }
        return hits
      }
      ready.forEach { $0.fulfill() }
    }
  }

  private func sync(_ gateway: Gateway) -> BuzzLiveActivityUpdateTokenSync {
    BuzzLiveActivityUpdateTokenSync(
      send: { try gateway.send($0, $1) },
      sleep: { await gateway.sleep($0) })
  }

  private func waitForSends(_ gateway: Gateway, _ count: Int) async {
    let expectation = expectation(description: "\(count) sends")
    gateway.expect(count, expectation)
    await fulfillment(of: [expectation], timeout: 5)
    try? await Task.sleep(nanoseconds: 50_000_000)
  }

  func testClearsOnlyWhenTheRegisteredActivityEnds() async {
    let gateway = Gateway()
    let subject = sync(gateway)
    await subject.tokenChanged(origin: origin, activityID: "a", token: Data([1]))
    await waitForSends(gateway, 1)
    await subject.activityEnded(origin: origin, activityID: "never-registered")
    await subject.activityEnded(origin: "https://zeta.example", activityID: "a")
    let registered = await subject.registeredActivities()
    XCTAssertEqual(registered, [origin: "a"])
    await subject.activityEnded(origin: origin, activityID: "a")
    await waitForSends(gateway, 2)
    XCTAssertEqual(gateway.sent.map(\.1), [Data([1]), nil])
    let afterEnd = await subject.registeredActivities()
    XCTAssertEqual(afterEnd, [:])
  }

  func testOldActivityEndingAfterNewTokenSendsNoClear() async {
    let gateway = Gateway()
    let subject = sync(gateway)
    await subject.tokenChanged(origin: origin, activityID: "old", token: Data([1]))
    await waitForSends(gateway, 1)
    await subject.tokenChanged(origin: origin, activityID: "new", token: Data([2]))
    await waitForSends(gateway, 2)
    await subject.activityEnded(origin: origin, activityID: "old")
    try? await Task.sleep(nanoseconds: 100_000_000)
    XCTAssertEqual(gateway.sent.map(\.1), [Data([1]), Data([2])])
    let registered = await subject.registeredActivities()
    XCTAssertEqual(registered, [origin: "new"])
  }

  func testEndOfRegisteredActivityFallsBackToAnotherLiveToken() async {
    let gateway = Gateway()
    let subject = sync(gateway)
    await subject.tokenChanged(origin: origin, activityID: "a", token: Data([1]))
    await waitForSends(gateway, 1)
    await subject.tokenChanged(origin: origin, activityID: "b", token: Data([2]))
    await waitForSends(gateway, 2)
    await subject.tokenChanged(origin: origin, activityID: "a", token: Data([3]))
    await waitForSends(gateway, 3)
    await subject.activityEnded(origin: origin, activityID: "a")
    await waitForSends(gateway, 4)
    XCTAssertEqual(gateway.sent.map(\.1), [Data([1]), Data([2]), Data([3]), Data([2])])
    let registered = await subject.registeredActivities()
    XCTAssertEqual(registered, [origin: "b"])
  }

  func testEndedActivityTokenIsIgnored() async {
    let gateway = Gateway()
    let subject = sync(gateway)
    await subject.activityEnded(origin: origin, activityID: "a")
    await subject.tokenChanged(origin: origin, activityID: "a", token: Data([1]))
    try? await Task.sleep(nanoseconds: 100_000_000)
    XCTAssertTrue(gateway.sent.isEmpty)
  }

  func testFailedSendRetriesWithBoundedBackoff() async {
    let gateway = Gateway(failures: 9)
    let subject = sync(gateway)
    await subject.tokenChanged(origin: origin, activityID: "a", token: Data([1]))
    await waitForSends(gateway, 10)
    XCTAssertEqual(gateway.slept, [2, 4, 8, 16, 32, 64, 128, 256, 300])
    XCTAssertEqual(gateway.sent.count, 10)
    let registered = await subject.registeredActivities()
    XCTAssertEqual(registered, [origin: "a"])
  }

  func testRetrySendsTheLatestWantedToken() async {
    let gateway = Gateway(failures: 1, holdRetries: true)
    let subject = sync(gateway)
    await subject.tokenChanged(origin: origin, activityID: "a", token: Data([1]))
    await waitForSends(gateway, 1)
    await subject.tokenChanged(origin: origin, activityID: "b", token: Data([2]))
    gateway.releaseRetries()
    await waitForSends(gateway, 2)
    try? await Task.sleep(nanoseconds: 100_000_000)
    XCTAssertEqual(gateway.sent.map(\.1), [Data([1]), Data([2])])
    XCTAssertEqual(gateway.slept, [2])
  }

  func testTerminalErrorsAreNotRetried() async {
    let terminal: [BuzzLiveActivityRegistrationError] = [.invalidOrigin, .unboundOrigin, .notEnrolled]
    for error in terminal {
      let gateway = Gateway(failures: 1, error: error)
      let subject = sync(gateway)
      await subject.tokenChanged(origin: origin, activityID: "a", token: Data([1]))
      await waitForSends(gateway, 1)
      try? await Task.sleep(nanoseconds: 100_000_000)
      XCTAssertEqual(gateway.sent.count, 1, "\(error)")
      XCTAssertTrue(gateway.slept.isEmpty, "\(error)")
      let registered = await subject.registeredActivities()
      XCTAssertEqual(registered, [origin: "a"], "\(error)")
    }
  }

  func testClearOfAnUnregisteredOriginStops() async {
    let gateway = Gateway(script: [nil, BuzzLiveActivityRegistrationError.rejected(status: 404, code: "not_found")])
    let subject = sync(gateway)
    await subject.tokenChanged(origin: origin, activityID: "a", token: Data([1]))
    await waitForSends(gateway, 1)
    await subject.activityEnded(origin: origin, activityID: "a")
    await waitForSends(gateway, 2)
    try? await Task.sleep(nanoseconds: 100_000_000)
    XCTAssertEqual(gateway.sent.map(\.1), [Data([1]), nil])
    XCTAssertTrue(gateway.slept.isEmpty)
  }

  func testNotFoundForANewTokenAndCounterConflictForAClearAreRetried() async {
    let notFound = BuzzLiveActivityRegistrationError.rejected(status: 404, code: "not_found")
    let conflict = BuzzLiveActivityRegistrationError.rejected(status: 404, code: "not_authorized")
    let gateway = Gateway(script: [notFound, nil, conflict])
    let subject = sync(gateway)
    await subject.tokenChanged(origin: origin, activityID: "a", token: Data([1]))
    await waitForSends(gateway, 2)
    await subject.activityEnded(origin: origin, activityID: "a")
    await waitForSends(gateway, 4)
    XCTAssertEqual(gateway.sent.map(\.1), [Data([1]), Data([1]), nil, nil])
    XCTAssertEqual(gateway.slept.count, 2)
  }

  func testNewTokenInterruptsTheBackoff() async {
    let gateway = Gateway(failures: 1, holdRetries: true)
    let subject = sync(gateway)
    await subject.tokenChanged(origin: origin, activityID: "a", token: Data([1]))
    await waitForSends(gateway, 1)
    XCTAssertEqual(gateway.slept.count, 1)
    await subject.tokenChanged(origin: origin, activityID: "a", token: Data([2]))
    await waitForSends(gateway, 2)
    XCTAssertEqual(gateway.sent.map(\.1), [Data([1]), Data([2])])
    let registered = await subject.registeredActivities()
    XCTAssertEqual(registered, [origin: "a"])
    gateway.releaseRetries()
  }
}
