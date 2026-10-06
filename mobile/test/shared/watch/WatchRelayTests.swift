import CryptoKit
import Foundation
import XCTest
@testable import WatchCheck

final class WatchHTTPFixture: URLProtocol {
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

final class WatchRelayTests: XCTestCase {
  private let key = String(repeating: "0", count: 63) + "1"
  private let relayKey = String(repeating: "0", count: 63) + "2"
  private var accepted = true
  private var matchReceipt = true
  private var failReads = false
  private var member = true
  private var peers: [String] = []
  private var sent: [VerifiedNostrEvent] = []
  private var authIDs: Set<String> = []
  private var channels: [VerifiedNostrEvent] = []
  private var history: [VerifiedNostrEvent] = []
  private var changes: [VerifiedNostrEvent] = []

  private func event(kind: Int, tags: [[String]], content: String = "", key: String? = nil, time: Int = 100) throws -> VerifiedNostrEvent {
    try NostrHTTPAuth.signedEvent(kind: kind, tags: tags, content: content, privateKeyHex: key ?? self.key, createdAt: time)
  }

  private func makeRelay() throws -> WatchRelay {
    let pubkey = try event(kind: 0, tags: []).pubkey
    let relayPubkey = try event(kind: 0, tags: [], key: relayKey).pubkey
    let credentials = try WatchCredentials(scope: "community:\(pubkey)", relayURL: "https://watch.example", privateKeyHex: key, pubkey: pubkey)
    channels = [
      try event(kind: 39000, tags: [["d", "joined"], ["name", "General"], ["t", "stream"]], key: relayKey),
      try event(kind: 39000, tags: [["d", "other"], ["name", "Other"]], key: relayKey),
      try event(kind: 39000, tags: [["d", "archived"], ["name", "Archived"], ["archived", "true"]], key: relayKey),
      try event(kind: 39000, tags: [["d", "forum"], ["name", "Forum"], ["t", "forum"]], key: relayKey),
    ]
    history = [try event(kind: 9, tags: [["h", "joined"]], content: "Hello")]
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [WatchHTTPFixture.self]
    WatchHTTPFixture.handler = { [unowned self] request in
      if request.httpMethod != "POST" {
        return (200, try JSONSerialization.data(withJSONObject: ["self": relayPubkey]))
      }
      let header = try XCTUnwrap(request.value(forHTTPHeaderField: "Authorization"))
      let proof = try JSONDecoder().decode(VerifiedNostrEvent.self, from: XCTUnwrap(Data(base64Encoded: String(header.dropFirst(6)))))
      XCTAssertTrue(proof.hasValidIDAndSignature())
      XCTAssertEqual(proof.tag("u"), request.url!.absoluteString)
      XCTAssertEqual(proof.tag("method"), "POST")
      XCTAssertEqual(proof.pubkey, pubkey)
      XCTAssertTrue(authIDs.insert(proof.id).inserted)
      let body: Data
      if let data = request.httpBody { body = data }
      else {
        let stream = try XCTUnwrap(request.httpBodyStream)
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
          let count = stream.read(&buffer, maxLength: buffer.count)
          if count <= 0 { break }
          data.append(contentsOf: buffer.prefix(count))
        }
        body = data
      }
      XCTAssertEqual(proof.tag("payload"), VerifiedNostrEvent.hex(SHA256.hash(data: body)))
      if request.url!.path == "/events" {
        let message = try JSONDecoder().decode(VerifiedNostrEvent.self, from: body)
        XCTAssertTrue(message.hasValidIDAndSignature())
        sent.append(message)
        return (200, try JSONSerialization.data(withJSONObject: ["accepted": accepted, "event_id": matchReceipt ? message.id : "wrong"]))
      }
      if failReads { return (403, Data()) }
      let filters = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [[String: Any]])
      let filter = try XCTUnwrap(filters.first)
      XCTAssertEqual(filter["consistency"] as? String, "strong")
      let kinds = try XCTUnwrap(filter["kinds"] as? [Int])
      var result: [VerifiedNostrEvent] = []
      if kinds.contains(39002) {
        for id in ["joined", "archived", "forum"] {
          result.append(try event(kind: 39002, tags: [["d", id]] + (member ? [["p", pubkey]] : []) + peers.map { ["p", $0] }, key: relayKey))
        }
      }
      if kinds.contains(39000) { result += channels }
      if kinds.contains(9) { result += history }
      if kinds.contains(40003) { result += changes }
      if let ids = filter["#d"] as? [String] { result = result.filter { ids.contains($0.tag("d") ?? "") } }
      return (200, try JSONEncoder().encode(result))
    }
    return WatchRelay(credentials: credentials, configuration: config)
  }

  override func tearDown() { WatchHTTPFixture.handler = nil }

  func testDirectReadAndSendWithNoPhone() async throws {
    let relay = try makeRelay()
    defer { relay.close() }
    let listing = try await relay.request(["action": "channels"])
    let listed = try XCTUnwrap(listing["channels"] as? [[String: Any]])
    XCTAssertEqual(listed.map { $0["id"] as! String }, ["joined"])
    let args: [String: Any] = ["scope": relay.credentials.scope, "channelId": "joined"]
    let read = try await relay.request(args.merging(["action": "messages"]) { _, value in value })
    XCTAssertEqual((read["messages"] as! [[String: Any]]).first?["text"] as? String, "Hello")
    let result = try await relay.request(args.merging(["action": "send", "text": " Thanks "]) { _, value in value })
    XCTAssertEqual(result["sent"] as? Bool, true)
    XCTAssertEqual(sent.last?.content, "Thanks")
    XCTAssertEqual(sent.last?.tag("h"), "joined")
    XCTAssertEqual(sent.count, 1)
  }

  func testRejectedOrWrongReceiptNeverConfirmsOrRetries() async throws {
    let relay = try makeRelay()
    defer { relay.close() }
    let args: [String: Any] = ["action": "send", "scope": relay.credentials.scope, "channelId": "joined", "text": "Hello"]
    accepted = false
    do { _ = try await relay.request(args); XCTFail("Rejected send confirmed") } catch {}
    accepted = true
    matchReceipt = false
    do { _ = try await relay.request(args); XCTFail("Wrong receipt confirmed") } catch {}
    XCTAssertEqual(sent.count, 2)
  }

  func testMembershipAndScopeFailuresCannotSend() async throws {
    let relay = try makeRelay()
    defer { relay.close() }
    let args: [String: Any] = ["action": "send", "scope": relay.credentials.scope, "channelId": "joined", "text": "Hello"]
    member = false
    do { _ = try await relay.request(args); XCTFail("Nonmember sent") } catch {}
    member = true
    do { _ = try await relay.request(args.merging(["scope": "old"]) { _, value in value }); XCTFail("Old scope sent") } catch {}
    do { _ = try await relay.request(args.merging(["text": String(repeating: "🐝", count: 1001)]) { _, value in value }); XCTFail("Oversized send") } catch {}
    XCTAssertTrue(sent.isEmpty)
  }

  func testDMAddressesItsOtherMembers() async throws {
    let relay = try makeRelay()
    defer { relay.close() }
    let peer = try event(kind: 0, tags: [], key: String(repeating: "0", count: 63) + "3").pubkey
    channels[0] = try event(kind: 39000, tags: [["d", "joined"], ["name", "DM"], ["t", "dm"]], key: relayKey)
    peers = [peer]
    _ = try await relay.request(["action": "send", "scope": relay.credentials.scope, "channelId": "joined", "text": "Hello"])
    XCTAssertTrue(sent.last!.tags.contains(["p", peer]))
    XCTAssertFalse(sent.last!.tags.contains(["p", relay.credentials.pubkey]))
  }

  func testReadDenialAndInvalidSignatureFailClosed() async throws {
    let relay = try makeRelay()
    defer { relay.close() }
    failReads = true
    do { _ = try await relay.request(["action": "channels"]); XCTFail("Denied read succeeded") } catch {}
    failReads = false
    let good = channels[0]
    channels[0] = VerifiedNostrEvent(id: good.id, pubkey: good.pubkey, createdAt: good.createdAt, kind: good.kind, tags: good.tags, content: "tampered", sig: good.sig)
    do { _ = try await relay.request(["action": "channels"]); XCTFail("Invalid signature accepted") } catch {}
  }

  func testTimelineAppliesChangesAndBoundsUnicode() throws {
    let first = try event(kind: 9, tags: [["h", "joined"]], content: String(repeating: "🐝", count: 500))
    let second = try event(kind: 40002, tags: [["h", "joined"]], content: "Before", time: 101)
    let deletion = try event(kind: 9005, tags: [["h", "joined"], ["e", first.id]], time: 102)
    let edit = try event(kind: 40003, tags: [["h", "joined"], ["e", second.id]], content: "After", time: 103)
    let other = try event(kind: 9, tags: [["h", "other"]], content: "Hidden")
    let messages = WatchRelay.timeline([first, second, deletion, edit, other], channelID: "joined", labels: [:])
    XCTAssertEqual(messages.count, 1)
    XCTAssertEqual(messages[0]["text"] as? String, "After")
    let bounded = WatchRelay.timeline([first], channelID: "joined", labels: [:])
    XCTAssertEqual((bounded[0]["text"] as! String).unicodeScalars.count, 300)
  }

  func testSetupRejectsInsecureOriginsAndMismatchedIdentity() throws {
    let pubkey = try event(kind: 0, tags: []).pubkey
    for url in ["http://watch.example", "https://user:pass@watch.example", "https://watch.example/path", "https://watch.example?key=x", "https://watch.example#x"] {
      XCTAssertThrowsError(try WatchCredentials(scope: "community:\(pubkey)", relayURL: url, privateKeyHex: key, pubkey: pubkey))
    }
    XCTAssertThrowsError(try WatchCredentials(scope: "old", relayURL: "https://watch.example", privateKeyHex: key, pubkey: pubkey))
    XCTAssertThrowsError(try WatchCredentials(scope: "community:\(pubkey)", relayURL: "https://watch.example", privateKeyHex: relayKey, pubkey: pubkey))
    XCTAssertThrowsError(try NostrHTTPAuth.signedEvent(kind: 9, tags: [], content: "", privateKeyHex: String(repeating: "+a", count: 32)))
  }
}
