import CryptoKit
import Foundation
import XCTest

@testable import BuzzPushKit

final class BuzzLiveActivityTests: XCTestCase {
  private let origin = "https://buzz.bl4ko.com"
  private let eventID = String(repeating: "ab", count: 32)
  private let key = String(repeating: "0", count: 63) + "1"

  private func contentStates(in value: Any) -> [Any] {
    if let text = value as? String, text.hasPrefix("{"),
      let data = text.data(using: .utf8),
      let parsed = try? JSONSerialization.jsonObject(with: data)
    {
      return contentStates(in: parsed)
    }
    if let object = value as? [String: Any] {
      if let aps = object["aps"] as? [String: Any], let state = aps["content-state"] {
        return [state]
      }
      return object.values.flatMap { contentStates(in: $0) }
    }
    if let array = value as? [Any] {
      return array.flatMap { contentStates(in: $0) }
    }
    return []
  }

  func testGoldenPayloadsDecodeIntoContentState() throws {
    let url = try XCTUnwrap(Bundle.module.url(forResource: "live_activity_payloads", withExtension: "json"))
    let fixture = try JSONSerialization.jsonObject(with: Data(contentsOf: url))
    let states = contentStates(in: fixture)
    XCTAssertGreaterThanOrEqual(states.count, 5)
    var decoded: [BuzzApprovalsContentState] = []
    for state in states {
      let data = try JSONSerialization.data(withJSONObject: state)
      decoded.append(try JSONDecoder().decode(BuzzApprovalsContentState.self, from: data))
    }
    XCTAssertTrue(decoded.allSatisfy { $0.decision == nil })
    XCTAssertTrue(decoded.contains { $0.openCount == 0 && $0.askEventID.isEmpty && $0.caseID == nil })
    XCTAssertTrue(decoded.contains { $0.openCount > 0 && $0.caseID == nil })
    XCTAssertTrue(decoded.contains { $0.ask.count == 120 && $0.ask.utf8.count > 120 })
    let first = try XCTUnwrap(decoded.first { $0.caseID != nil })
    XCTAssertEqual(first.askEventID.utf8.count, 64)
    XCTAssertGreaterThan(first.askedAt, 1_700_000_000)
  }

  func testContentStateEncodesSpecKeys() throws {
    let state = BuzzApprovalsContentState(
      askEventID: eventID, caseID: "C-1", ask: "Ask", agent: "Zeus", channel: "ops", openCount: 2, askedAt: 10)
    let object = try XCTUnwrap(
      JSONSerialization.jsonObject(with: JSONEncoder().encode(state)) as? [String: Any])
    XCTAssertEqual(
      Set(object.keys), ["askEventID", "caseID", "ask", "agent", "channel", "openCount", "askedAt"])
  }

  func testBoundOriginHashesMatchGatewayVectors() throws {
    let url = try XCTUnwrap(Bundle.module.url(forResource: "live_activity_payloads", withExtension: "json"))
    let fixture = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
    let hashes = try XCTUnwrap(fixture["bound_origin_hashes"] as? [[String: String]])
    XCTAssertFalse(hashes.isEmpty)
    var seen: [String: Set<String>] = [:]
    for vector in hashes {
      let origin = try XCTUnwrap(vector["origin"])
      let relay = try XCTUnwrap(vector["relay_pubkey"])
      XCTAssertEqual(BuzzLiveActivityOrigin.boundHashHex(origin: origin, relayPubkey: relay), vector["sha256"], origin)
      seen[origin, default: []].insert(try XCTUnwrap(vector["sha256"]))
    }
    XCTAssertTrue(seen.values.contains { $0.count > 1 })
    let invalid = try XCTUnwrap(fixture["invalid_origins"] as? [String])
    XCTAssertFalse(invalid.isEmpty)
    for origin in invalid {
      XCTAssertNil(BuzzLiveActivityOrigin.boundHashHex(origin: origin, relayPubkey: key), origin)
    }
    let invalidKeys = try XCTUnwrap(fixture["invalid_relay_pubkeys"] as? [String])
    XCTAssertFalse(invalidKeys.isEmpty)
    for relay in invalidKeys {
      XCTAssertNil(BuzzLiveActivityOrigin.boundHashHex(origin: origin, relayPubkey: relay), relay)
    }
    XCTAssertEqual(BuzzLiveActivityOrigin.canonical("wss://Buzz.bl4ko.com"), origin)
    XCTAssertEqual(BuzzLiveActivityOrigin.canonical("wss://buzz.bl4ko.com/"), origin)
    XCTAssertEqual(BuzzLiveActivityOrigin.canonical("https://buzz.bl4ko.com:443"), origin)
    XCTAssertEqual(BuzzLiveActivityOrigin.canonical("https://relay.example:8443/"), "https://relay.example:8443")
    XCTAssertNil(BuzzLiveActivityOrigin.canonical("ws://localhost:3000"))
    XCTAssertNil(BuzzLiveActivityOrigin.canonical("https://buzz.bl4ko.com:0"))
  }

  func testLiveActivityTranscriptsMatchVectors() throws {
    let fixture = try BuzzPushTranscriptTests.fixture()
    let challengeID = BuzzPushTranscriptTests.challengeId
    let installation = BuzzPushTranscriptTests.installationHandle
    let challenge = BuzzPushTranscriptTests.challenge
    let gateway = BuzzPushTranscriptTests.gatewayOrigin
    let hash = try XCTUnwrap(
      BuzzLiveActivityOrigin.boundHashHex(origin: origin, relayPubkey: BuzzPushTranscriptTests.relayPubkey))
    let token = BuzzPushTranscriptTests.endpoint
    let cases: [(String, Data)] = [
      (
        "live_activity",
        try BuzzPushTranscript.liveActivity(
          gatewayOrigin: gateway, challengeId: challengeID, challenge: challenge,
          installationHandle: installation, startToken: token, origins: [hash])
      ),
      (
        "live_activity_off",
        try BuzzPushTranscript.liveActivity(
          gatewayOrigin: gateway, challengeId: challengeID, challenge: challenge,
          installationHandle: installation, startToken: nil, origins: [])
      ),
      (
        "live_activity_update",
        try BuzzPushTranscript.liveActivityUpdate(
          gatewayOrigin: gateway, challengeId: challengeID, challenge: challenge,
          installationHandle: installation, originHash: hash, updateToken: token)
      ),
      (
        "live_activity_update_clear",
        try BuzzPushTranscript.liveActivityUpdate(
          gatewayOrigin: gateway, challengeId: challengeID, challenge: challenge,
          installationHandle: installation, originHash: hash, updateToken: nil)
      ),
    ]
    for (name, bytes) in cases {
      let vector = try XCTUnwrap(fixture.vectors.first { $0.name == name }, name)
      XCTAssertEqual(String(decoding: bytes, as: UTF8.self), vector.transcript, name)
      XCTAssertEqual(SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined(), vector.sha256, name)
    }
  }

  func testOriginsFromSnapshotAreCanonicalSortedAndUnique() {
    let snapshot = PushLeaseSnapshot(communities: [
      PushLeaseCommunity(id: "b", name: "B", relayUrl: "wss://zeta.example", pubkey: nil, policies: []),
      PushLeaseCommunity(id: "a", name: "A", relayUrl: "wss://buzz.bl4ko.com", pubkey: nil, policies: []),
      PushLeaseCommunity(id: "c", name: "C", relayUrl: "wss://BUZZ.bl4ko.com/", pubkey: nil, policies: []),
      PushLeaseCommunity(id: "d", name: "D", relayUrl: "ws://127.0.0.1:3000", pubkey: nil, policies: []),
    ])
    XCTAssertEqual(BuzzLiveActivityOrigin.origins(in: snapshot), [origin, "https://zeta.example"])
  }

  func testTasksLinkEncodesOriginAndEvent() throws {
    let url = try XCTUnwrap(BuzzLiveActivityLink.tasks(origin: origin, askEventID: eventID))
    XCTAssertEqual(url.absoluteString, "buzz://tasks?origin=https%3A%2F%2Fbuzz.bl4ko.com&event=\(eventID)")
    XCTAssertNil(BuzzLiveActivityLink.tasks(origin: origin, askEventID: ""))
    XCTAssertNil(BuzzLiveActivityLink.tasks(origin: "http://x", askEventID: eventID))
  }

  func testStoredRelayFindsCommunityForOrigin() throws {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("la-snapshot-\(UUID().uuidString).json")
    defer { try? FileManager.default.removeItem(at: url) }
    let snapshot = PushLeaseSnapshot(communities: [
      PushLeaseCommunity(id: "c1", name: "One", relayUrl: "wss://buzz.bl4ko.com", pubkey: nil, policies: []),
      PushLeaseCommunity(id: "c2", name: "Two", relayUrl: "wss://zeta.example", pubkey: nil, policies: []),
    ])
    try JSONEncoder().encode(snapshot).write(to: url)
    XCTAssertEqual(BuzzPushStoredRelay.communityID(origin: origin, snapshotURL: url), "c1")
    XCTAssertEqual(BuzzPushStoredRelay.communityID(origin: "https://zeta.example", snapshotURL: url), "c2")
    XCTAssertNil(BuzzPushStoredRelay.communityID(origin: "https://other.example", snapshotURL: url))
  }

  func testSigningKeychainServiceIsSeparateFromExtensionKey() {
    XCTAssertEqual(BuzzLiveActivitySigningKeychain.service, "buzz.liveactivity.signing")
    XCTAssertNotEqual(BuzzLiveActivitySigningKeychain.service, BuzzPushSigningKeychain.service)
    XCTAssertNil(BuzzLiveActivitySigningKeychain.privateKey(communityID: "missing-\(UUID().uuidString)", accessGroup: nil))
  }

  private final class Recorder: @unchecked Sendable {
    var marks: [BuzzApprovalDecision?] = []
    var sends: [(BuzzApprovalTarget, BuzzApprovalDecision, String)] = []
    var notices: [String] = []
    var events: [String] = []
  }

  private func run(
    origin: String? = nil,
    askEventID: String? = nil,
    decision: BuzzApprovalDecision = .approve,
    community: String? = "c1",
    relay: String? = "https://buzz.bl4ko.com",
    key: String?? = .none,
    sendError: Error? = nil,
    recorder: Recorder
  ) async -> Bool {
    let loadedKey: String? = key ?? self.key
    return await BuzzLiveActivityDecisionRunner.run(
      origin: origin ?? self.origin,
      askEventID: askEventID ?? eventID,
      decision: decision,
      communityID: { _ in community },
      storedRelayURL: { _ in relay },
      loadKey: { _ in loadedKey },
      mark: { decision in
        recorder.marks.append(decision)
        recorder.events.append("mark")
      },
      send: { target, decision, key in
        recorder.events.append("send")
        recorder.sends.append((target, decision, key))
        if let sendError { throw sendError }
      },
      notifyFailure: { recorder.notices.append($0) }
    )
  }

  func testDecisionRunnerLockedKeyNotifiesUnlockAndDoesNotSend() async {
    let recorder = Recorder()
    let sent = await run(key: .some(nil), recorder: recorder)
    XCTAssertFalse(sent)
    XCTAssertTrue(recorder.sends.isEmpty)
    XCTAssertTrue(recorder.marks.isEmpty)
    XCTAssertEqual(recorder.notices, [BuzzLiveActivityDecisionRunner.lockedBody])
    XCTAssertEqual(BuzzLiveActivityDecisionRunner.lockedBody, "Unlock your iPhone and try again.")
  }

  func testDecisionRunnerUnknownOriginDoesNotSend() async {
    let recorder = Recorder()
    let unknown = await run(community: nil, recorder: recorder)
    let mismatch = await run(relay: "https://other.example", recorder: recorder)
    let missingRelay = await run(relay: nil, recorder: recorder)
    XCTAssertFalse(unknown || mismatch || missingRelay)
    XCTAssertTrue(recorder.sends.isEmpty)
    XCTAssertTrue(recorder.marks.isEmpty)
    XCTAssertEqual(recorder.notices.count, 3)
  }

  func testDecisionRunnerMarksThenSends() async {
    let recorder = Recorder()
    let sent = await run(decision: .deny, relay: "https://buzz.bl4ko.com", recorder: recorder)
    XCTAssertTrue(sent)
    XCTAssertEqual(recorder.events, ["mark", "send"])
    XCTAssertEqual(recorder.marks, [.deny])
    XCTAssertEqual(recorder.sends.count, 1)
    XCTAssertEqual(
      recorder.sends[0].0, BuzzApprovalTarget(relayURL: "https://buzz.bl4ko.com", eventID: eventID, communityID: "c1"))
    XCTAssertEqual(recorder.sends[0].1, .deny)
    XCTAssertEqual(recorder.sends[0].2, key)
    XCTAssertTrue(recorder.notices.isEmpty)
  }

  func testDecisionRunnerSendFailureClearsMarkAndNotifies() async {
    struct Refused: Error {}
    let recorder = Recorder()
    let sent = await run(sendError: Refused(), recorder: recorder)
    XCTAssertFalse(sent)
    XCTAssertEqual(recorder.events, ["mark", "send", "mark"])
    XCTAssertEqual(recorder.marks, [.approve, nil])
    XCTAssertEqual(recorder.notices, [BuzzApprovalActionHandler.failureBody])
  }

  func testDecisionRunnerRejectsBadEventID() async {
    let recorder = Recorder()
    let upper = await run(askEventID: eventID.uppercased(), recorder: recorder)
    let short = await run(askEventID: "abcd", recorder: recorder)
    let empty = await run(askEventID: "", recorder: recorder)
    let badOrigin = await run(origin: "https://Buzz.bl4ko.com", recorder: recorder)
    XCTAssertFalse(upper || short || empty || badOrigin)
    XCTAssertTrue(recorder.sends.isEmpty)
    XCTAssertTrue(recorder.marks.isEmpty)
  }
}

final class BuzzLiveActivityRegistrarTests: XCTestCase {
  private let gateway = URL(string: "https://push.example")!
  private let installation = "22222222-2222-4222-8222-222222222222"
  private let keyId = "qqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqo="
  private let challengeID = "11111111-1111-4111-8111-111111111111"
  private let challenge = "AAECAwQFBgcICQoLDA0ODxAREhMUFRYXGBkaGxwdHh8"

  override func tearDown() { LiveActivityHTTPStub.reset() }

  private let relayA = String(repeating: "a", count: 64)
  private let relayB = String(repeating: "b", count: 64)

  private func record(
    handle: String?, relay: String = "wss://buzz.bl4ko.com", relayPubkey: String? = nil,
    expiresAt: Int64 = 4_000_000_000
  ) -> BuzzPushEndpointGrantRecord {
    BuzzPushEndpointGrantRecord(
      gatewayOrigin: "https://push.example", relayOrigin: relay,
      relayPubkey: relayPubkey ?? relayA, gatewayInstallationHandle: handle,
      appAttestKeyId: keyId, installationId: String(repeating: "0", count: 32), endpointGrant: "grant",
      endpointHash: String(repeating: "1", count: 64), appProfile: BuzzDevPushEnrollmentDriver.appProfile,
      endpointEpoch: 1, generation: 1, expiresAt: expiresAt)
  }

  private func registrar(records: [BuzzPushEndpointGrantRecord], appAttest: LiveActivityAppAttest) throws
    -> BuzzLiveActivityRegistrar
  {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [LiveActivityHTTPStub.self]
    return try BuzzLiveActivityRegistrar(
      gatewayBaseURL: gateway, store: LiveActivityGrantStore(records: records),
      session: URLSession(configuration: configuration), appAttest: appAttest,
      now: { Date(timeIntervalSince1970: 1_760_640_000) })
  }

  private func stubGateway() {
    LiveActivityHTTPStub.handler = { request in
      if request.url?.path == "/v1/installations/challenges" {
        return (200, Data("{\"challenge_id\":\"\(self.challengeID)\",\"challenge\":\"\(self.challenge)\",\"expires_at\":4000000000}".utf8))
      }
      return (204, Data())
    }
  }

  private func startRequest(
    records: [BuzzPushEndpointGrantRecord], token: Data?, origins: [String], registered: String? = nil
  ) throws -> BuzzLiveActivityStartRequest {
    try XCTUnwrap(
      BuzzLiveActivityStartPlanner.request(
        records: records, origins: origins, activitiesEnabled: true, startToken: token, now: 1_760_640_000,
        registeredFingerprint: registered))
  }

  func testRegisterPostsAssertedBodyWithBoundHashes() async throws {
    stubGateway()
    let attest = LiveActivityAppAttest()
    let records = [
      record(handle: installation), record(handle: installation, relay: "wss://zeta.example", relayPubkey: relayB),
    ]
    let subject = try registrar(records: records, appAttest: attest)
    try await subject.register(
      try startRequest(
        records: records, token: Data([0x01, 0xab]),
        origins: ["https://zeta.example", "https://buzz.bl4ko.com", "https://zeta.example"]))
    let requests = LiveActivityHTTPStub.requests
    XCTAssertEqual(requests.map { $0.url?.path }, ["/v1/installations/challenges", "/v1/installations/live-activity"])
    let body = try XCTUnwrap(JSONSerialization.jsonObject(with: requests[1].body) as? [String: Any])
    let hashes = [
      try XCTUnwrap(BuzzLiveActivityOrigin.boundHashHex(origin: "https://buzz.bl4ko.com", relayPubkey: relayA)),
      try XCTUnwrap(BuzzLiveActivityOrigin.boundHashHex(origin: "https://zeta.example", relayPubkey: relayB)),
    ].sorted()
    XCTAssertEqual(body["v"] as? Int, 1)
    XCTAssertEqual(body["challenge_id"] as? String, challengeID)
    XCTAssertEqual(body["challenge"] as? String, challenge)
    XCTAssertEqual(body["installation_handle"] as? String, installation)
    XCTAssertEqual(body["start_token"] as? String, "01ab")
    XCTAssertEqual(body["origins"] as? [String], hashes)
    XCTAssertEqual(body["assertion"] as? String, "assertion-1")
    XCTAssertEqual(Set(body.keys), ["v", "challenge_id", "challenge", "installation_handle", "start_token", "origins", "assertion"])
    XCTAssertEqual(attest.keyIds, [keyId])
    XCTAssertEqual(
      attest.clientData,
      [
        try BuzzPushTranscript.liveActivity(
          gatewayOrigin: gateway, challengeId: UUID(uuidString: challengeID)!, challenge: challenge,
          installationHandle: UUID(uuidString: installation)!, startToken: "01ab", origins: hashes)
      ])
  }

  func testRegisterOffSendsNullAndNoOrigins() async throws {
    stubGateway()
    let records = [record(handle: installation)]
    let subject = try registrar(records: records, appAttest: LiveActivityAppAttest())
    let on = try startRequest(records: records, token: Data([1]), origins: ["https://buzz.bl4ko.com"])
    try await subject.register(try startRequest(records: records, token: nil, origins: [], registered: on.fingerprint))
    let body = try XCTUnwrap(
      JSONSerialization.jsonObject(with: LiveActivityHTTPStub.requests[1].body) as? [String: Any])
    XCTAssertTrue(body["start_token"] is NSNull)
    XCTAssertEqual(body["origins"] as? [String], [])
  }

  func testRegisterRejectsRequestForAnotherGateway() async throws {
    stubGateway()
    let other = BuzzPushEndpointGrantRecord(
      gatewayOrigin: "https://push2.example", relayOrigin: "wss://buzz.bl4ko.com", relayPubkey: relayA,
      gatewayInstallationHandle: installation, appAttestKeyId: keyId, installationId: String(repeating: "0", count: 32),
      endpointGrant: "grant", endpointHash: String(repeating: "1", count: 64),
      appProfile: BuzzDevPushEnrollmentDriver.appProfile, endpointEpoch: 1, generation: 1, expiresAt: 4_000_000_000)
    let subject = try registrar(records: [other], appAttest: LiveActivityAppAttest())
    do {
      try await subject.register(try startRequest(records: [other], token: Data([1]), origins: ["https://buzz.bl4ko.com"]))
      XCTFail("expected notEnrolled")
    } catch {
      XCTAssertEqual(error as? BuzzLiveActivityRegistrationError, .notEnrolled)
    }
    XCTAssertTrue(LiveActivityHTTPStub.requests.isEmpty)
  }

  func testSetUpdateTokenPostsBoundOriginHash() async throws {
    stubGateway()
    let subject = try registrar(records: [record(handle: installation, relayPubkey: relayB)], appAttest: LiveActivityAppAttest())
    try await subject.setUpdateToken(origin: "https://buzz.bl4ko.com", token: nil)
    let request = LiveActivityHTTPStub.requests[1]
    XCTAssertEqual(request.url?.path, "/v1/installations/live-activity/update-token")
    let body = try XCTUnwrap(JSONSerialization.jsonObject(with: request.body) as? [String: Any])
    XCTAssertEqual(
      body["origin_hash"] as? String,
      BuzzLiveActivityOrigin.boundHashHex(origin: "https://buzz.bl4ko.com", relayPubkey: relayB))
    XCTAssertTrue(body["update_token"] is NSNull)
    XCTAssertEqual(
      Set(body.keys), ["v", "challenge_id", "challenge", "installation_handle", "origin_hash", "update_token", "assertion"])
  }

  func testSetUpdateTokenNeedsRelayKeyForOrigin() async throws {
    stubGateway()
    let subject = try registrar(records: [record(handle: installation)], appAttest: LiveActivityAppAttest())
    do {
      try await subject.setUpdateToken(origin: "https://zeta.example", token: Data([1]))
      XCTFail("expected unboundOrigin")
    } catch {
      XCTAssertEqual(error as? BuzzLiveActivityRegistrationError, .unboundOrigin)
    }
    XCTAssertTrue(LiveActivityHTTPStub.requests.isEmpty)
  }

  func testRegistrarNeedsAnEnrolledInstallation() async throws {
    stubGateway()
    let subject = try registrar(
      records: [record(handle: nil), record(handle: installation, expiresAt: 1)], appAttest: LiveActivityAppAttest())
    do {
      try await subject.setUpdateToken(origin: "https://buzz.bl4ko.com", token: Data([1]))
      XCTFail("expected notEnrolled")
    } catch {
      XCTAssertEqual(error as? BuzzLiveActivityRegistrationError, .notEnrolled)
    }
    XCTAssertTrue(LiveActivityHTTPStub.requests.isEmpty)
  }

  func testUpdateTokenRejectsNonCanonicalOrigin() async throws {
    stubGateway()
    let subject = try registrar(records: [record(handle: installation)], appAttest: LiveActivityAppAttest())
    do {
      try await subject.setUpdateToken(origin: "https://buzz.bl4ko.com/", token: Data([1]))
      XCTFail("expected invalidOrigin")
    } catch {
      XCTAssertEqual(error as? BuzzLiveActivityRegistrationError, .invalidOrigin)
    }
  }

  func testRegistrarSurfacesGatewayRejection() async throws {
    LiveActivityHTTPStub.handler = { request in
      if request.url?.path == "/v1/installations/challenges" {
        return (200, Data("{\"challenge_id\":\"\(self.challengeID)\",\"challenge\":\"\(self.challenge)\",\"expires_at\":4000000000}".utf8))
      }
      return (404, Data("{\"error\":\"not_found\"}".utf8))
    }
    let subject = try registrar(records: [record(handle: installation)], appAttest: LiveActivityAppAttest())
    do {
      try await subject.setUpdateToken(origin: "https://buzz.bl4ko.com", token: Data([1]))
      XCTFail("expected rejection")
    } catch {
      XCTAssertEqual(error as? BuzzLiveActivityRegistrationError, .rejected(status: 404, code: "not_found"))
    }
  }

  func testRegistrarKeepsStatusWhenTheErrorBodyIsNotJSON() async throws {
    LiveActivityHTTPStub.handler = { request in
      if request.url?.path == "/v1/installations/challenges" {
        return (200, Data("{\"challenge_id\":\"\(self.challengeID)\",\"challenge\":\"\(self.challenge)\",\"expires_at\":4000000000}".utf8))
      }
      return (502, Data("bad gateway".utf8))
    }
    let subject = try registrar(records: [record(handle: installation)], appAttest: LiveActivityAppAttest())
    do {
      try await subject.setUpdateToken(origin: "https://buzz.bl4ko.com", token: nil)
      XCTFail("expected rejection")
    } catch {
      XCTAssertEqual(error as? BuzzLiveActivityRegistrationError, .rejected(status: 502, code: nil))
    }
  }
}

private final class LiveActivityAppAttest: BuzzDevAppAttesting, @unchecked Sendable {
  var keyIds: [String] = []
  var clientData: [Data] = []
  func prepareAttestation() async throws -> BuzzDevAttestation { throw URLError(.unsupportedURL) }
  func attestation(_ prepared: BuzzDevAttestation, clientData: Data) async throws -> BuzzDevAttestation {
    throw URLError(.unsupportedURL)
  }
  func assertion(keyId: String, clientData: Data) async throws -> String {
    keyIds.append(keyId)
    self.clientData.append(clientData)
    return "assertion-\(keyIds.count)"
  }
}

private final class LiveActivityGrantStore: BuzzPushEndpointGrantStore {
  let saved: [BuzzPushEndpointGrantRecord]
  init(records: [BuzzPushEndpointGrantRecord]) { saved = records }
  func records() throws -> [BuzzPushEndpointGrantRecord] { saved }
  func save(_ record: BuzzPushEndpointGrantRecord) throws {}
  func pendingEnrollment(gatewayOrigin: String, relayOrigin: String, appProfile: String) throws
    -> BuzzPushPendingEnrollmentRecord?
  { nil }
  func savePendingEnrollment(_ record: BuzzPushPendingEnrollmentRecord) throws {}
  func removePendingEnrollment(gatewayOrigin: String, relayOrigin: String, appProfile: String) throws {}
}

private final class LiveActivityHTTPStub: URLProtocol, @unchecked Sendable {
  static let lock = NSLock()
  nonisolated(unsafe) static var handler: ((URLRequest) throws -> (Int, Data))?
  nonisolated(unsafe) static var recorded: [URLRequest] = []

  static var requests: [URLRequest] {
    lock.lock()
    defer { lock.unlock() }
    return recorded
  }

  static func reset() {
    lock.lock()
    handler = nil
    recorded = []
    lock.unlock()
  }

  override class func canInit(with request: URLRequest) -> Bool { true }
  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
  override func startLoading() {
    var copy = request
    copy.httpBody = request.body
    Self.lock.lock()
    Self.recorded.append(copy)
    let handler = Self.handler
    Self.lock.unlock()
    do {
      let (status, data) = try handler?(copy) ?? { throw URLError(.unsupportedURL) }()
      client?.urlProtocol(
        self, didReceive: HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!,
        cacheStoragePolicy: .notAllowed)
      client?.urlProtocol(self, didLoad: data)
      client?.urlProtocolDidFinishLoading(self)
    } catch {
      client?.urlProtocol(self, didFailWithError: error)
    }
  }
  override func stopLoading() {}
}

extension URLRequest {
  fileprivate var body: Data {
    if let httpBody { return httpBody }
    guard let stream = httpBodyStream else { return Data() }
    stream.open()
    defer { stream.close() }
    var data = Data()
    var buffer = [UInt8](repeating: 0, count: 4096)
    while stream.hasBytesAvailable {
      let count = stream.read(&buffer, maxLength: buffer.count)
      if count <= 0 { break }
      data.append(buffer, count: count)
    }
    return data
  }
}
