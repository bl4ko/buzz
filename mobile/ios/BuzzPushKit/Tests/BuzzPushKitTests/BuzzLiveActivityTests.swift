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

  func testOriginHashMatchesGatewayVector() throws {
    let url = try XCTUnwrap(Bundle.module.url(forResource: "live_activity_payloads", withExtension: "json"))
    let fixture = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
    let hashes = try XCTUnwrap(fixture["origin_hashes"] as? [[String: String]])
    XCTAssertFalse(hashes.isEmpty)
    for vector in hashes {
      XCTAssertEqual(BuzzLiveActivityOrigin.hashHex(vector["origin"]!), vector["sha256"], vector["origin"]!)
    }
    let invalid = try XCTUnwrap(fixture["invalid_origins"] as? [String])
    XCTAssertFalse(invalid.isEmpty)
    for origin in invalid {
      XCTAssertNil(BuzzLiveActivityOrigin.hashHex(origin), origin)
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
    let hash = try XCTUnwrap(BuzzLiveActivityOrigin.hashHex(origin))
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

  func testActivitiesToEndKeepsNewestPerOrigin() {
    let items = [
      BuzzLiveActivityInstance(id: "old", origin: origin, askedAt: 10),
      BuzzLiveActivityInstance(id: "new", origin: origin, askedAt: 20),
      BuzzLiveActivityInstance(id: "other", origin: "https://zeta.example", askedAt: 5),
      BuzzLiveActivityInstance(id: "tie-first", origin: "https://tie.example", askedAt: 7),
      BuzzLiveActivityInstance(id: "tie-last", origin: "https://tie.example", askedAt: 7),
    ]
    XCTAssertEqual(Set(BuzzLiveActivityInstance.activitiesToEnd(items)), ["old", "tie-first"])
    XCTAssertEqual(
      BuzzLiveActivityInstance.activitiesToEnd(items, allowedOrigins: [origin]).sorted(),
      ["old", "other", "tie-first", "tie-last"])
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

  private func record(handle: String?, expiresAt: Int64 = 4_000_000_000) -> BuzzPushEndpointGrantRecord {
    BuzzPushEndpointGrantRecord(
      gatewayOrigin: "https://push.example", relayOrigin: "wss://buzz.bl4ko.com",
      relayPubkey: String(repeating: "a", count: 64), gatewayInstallationHandle: handle,
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

  func testRegisterStartPostsAssertedBody() async throws {
    stubGateway()
    let attest = LiveActivityAppAttest()
    let subject = try registrar(records: [record(handle: installation)], appAttest: attest)
    try await subject.registerStart(
      token: Data([0x01, 0xab]), origins: ["https://zeta.example", "https://buzz.bl4ko.com", "https://zeta.example"])
    let requests = LiveActivityHTTPStub.requests
    XCTAssertEqual(requests.map { $0.url?.path }, ["/v1/installations/challenges", "/v1/installations/live-activity"])
    let body = try XCTUnwrap(JSONSerialization.jsonObject(with: requests[1].body) as? [String: Any])
    let hashes = ["https://buzz.bl4ko.com", "https://zeta.example"].compactMap(BuzzLiveActivityOrigin.hashHex).sorted()
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

  func testRegisterStartWithoutTokenSendsNullAndNoOrigins() async throws {
    stubGateway()
    let subject = try registrar(records: [record(handle: installation)], appAttest: LiveActivityAppAttest())
    try await subject.registerStart(token: nil, origins: ["https://buzz.bl4ko.com"])
    let body = try XCTUnwrap(
      JSONSerialization.jsonObject(with: LiveActivityHTTPStub.requests[1].body) as? [String: Any])
    XCTAssertTrue(body["start_token"] is NSNull)
    XCTAssertEqual(body["origins"] as? [String], [])
  }

  func testSetUpdateTokenPostsOriginHash() async throws {
    stubGateway()
    let subject = try registrar(records: [record(handle: installation)], appAttest: LiveActivityAppAttest())
    try await subject.setUpdateToken(origin: "https://buzz.bl4ko.com", token: nil)
    let request = LiveActivityHTTPStub.requests[1]
    XCTAssertEqual(request.url?.path, "/v1/installations/live-activity/update-token")
    let body = try XCTUnwrap(JSONSerialization.jsonObject(with: request.body) as? [String: Any])
    XCTAssertEqual(body["origin_hash"] as? String, BuzzLiveActivityOrigin.hashHex("https://buzz.bl4ko.com"))
    XCTAssertTrue(body["update_token"] is NSNull)
    XCTAssertEqual(
      Set(body.keys), ["v", "challenge_id", "challenge", "installation_handle", "origin_hash", "update_token", "assertion"])
  }

  func testRegistrarNeedsAnEnrolledInstallation() async throws {
    stubGateway()
    let subject = try registrar(
      records: [record(handle: nil), record(handle: installation, expiresAt: 1)], appAttest: LiveActivityAppAttest())
    do {
      try await subject.registerStart(token: Data([1]), origins: [])
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
      XCTAssertEqual(error as? BuzzLiveActivityRegistrationError, .rejected(status: 404))
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
