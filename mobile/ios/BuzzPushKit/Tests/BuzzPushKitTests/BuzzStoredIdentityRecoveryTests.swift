import XCTest
@testable import BuzzPushKit

final class BuzzStoredIdentityRecoveryTests: XCTestCase {
  private let key = String(repeating: "ab", count: 32)

  func testReturnsSnapshotCommunitiesThatStillHaveTheirSigningKey() {
    let snapshot = PushLeaseSnapshot(communities: [
      PushLeaseCommunity(id: "kept", name: "Home", relayUrl: "wss://buzz.example", pubkey: "p1", policies: []),
      PushLeaseCommunity(id: "no-key", name: "Other", relayUrl: "wss://other.example", pubkey: "p2", policies: []),
      PushLeaseCommunity(id: "no-pubkey", name: "Third", relayUrl: "wss://third.example", pubkey: nil, policies: []),
      PushLeaseCommunity(id: "bad-key", name: "Fourth", relayUrl: "wss://fourth.example", pubkey: "p4", policies: []),
    ])
    let keys = ["kept": key, "no-pubkey": key, "bad-key": "nsec1"]

    let recovered = BuzzStoredIdentityRecovery.communities(snapshot: snapshot) { keys[$0] }

    XCTAssertEqual(recovered, [
      ["id": "kept", "name": "Home", "relayUrl": "wss://buzz.example", "pubkey": "p1", "privateKey": key]
    ])
  }

  func testReturnsNothingWithoutASnapshot() {
    XCTAssertEqual(BuzzStoredIdentityRecovery.communities(snapshot: nil) { _ in self.key }, [])
  }
}
