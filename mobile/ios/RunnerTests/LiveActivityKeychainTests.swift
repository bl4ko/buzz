import AppIntents
import BuzzPushKit
import Security
import UIKit
import XCTest

@testable import Buzz

final class LiveActivityKeychainTests: XCTestCase {
  private let communities = ["la-test-a-\(UUID().uuidString)", "la-test-b-\(UUID().uuidString)"]

  override func tearDown() {
    try? BuzzPushKeychain.replace(signingKeys: [:], accessGroup: nil)
    super.tearDown()
  }

  private func attributes(service: String, account: String) -> [String: Any]? {
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: account,
      kSecReturnAttributes as String: true,
      kSecReturnData as String: true,
      kSecMatchLimit as String: kSecMatchLimitOne,
    ]
    var item: CFTypeRef?
    guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess else { return nil }
    return item as? [String: Any]
  }

  func testReplaceWritesLiveActivityKeyWhenUnlockedOnly() throws {
    try BuzzPushKeychain.replace(signingKeys: [communities[0]: "11"], accessGroup: nil)
    let live = try XCTUnwrap(attributes(service: BuzzLiveActivitySigningKeychain.service, account: communities[0]))
    XCTAssertEqual(live[kSecAttrAccessible as String] as? String, kSecAttrAccessibleWhenUnlockedThisDeviceOnly as String)
    XCTAssertEqual(live[kSecValueData as String] as? Data, Data("11".utf8))
    let extensionKey = try XCTUnwrap(attributes(service: BuzzPushSigningKeychain.service, account: communities[0]))
    XCTAssertEqual(extensionKey[kSecAttrAccessible as String] as? String, kSecAttrAccessibleAfterFirstUnlock as String)
    XCTAssertEqual(BuzzLiveActivitySigningKeychain.privateKey(communityID: communities[0], accessGroup: nil), "11")
  }

  func testReplaceRemovesOldLiveActivityKeys() throws {
    try BuzzPushKeychain.replace(signingKeys: [communities[0]: "11", communities[1]: "22"], accessGroup: nil)
    try BuzzPushKeychain.replace(signingKeys: [communities[1]: "33"], accessGroup: nil)
    XCTAssertNil(attributes(service: BuzzLiveActivitySigningKeychain.service, account: communities[0]))
    XCTAssertNil(attributes(service: BuzzPushSigningKeychain.service, account: communities[0]))
    XCTAssertEqual(BuzzLiveActivitySigningKeychain.privateKey(communityID: communities[1], accessGroup: nil), "33")
    try BuzzPushKeychain.replace(signingKeys: [:], accessGroup: nil)
    XCTAssertNil(attributes(service: BuzzLiveActivitySigningKeychain.service, account: communities[1]))
    XCTAssertNil(attributes(service: BuzzPushSigningKeychain.service, account: communities[1]))
  }

  func testLockedLiveActivityWriteKeepsExtensionKeysAndRetriesWhenUnlocked() throws {
    try BuzzPushKeychain.replace(signingKeys: [communities[0]: "11"], accessGroup: nil)
    var attempts = 0
    try BuzzPushKeychain.replace(
      signingKeys: [communities[0]: "22", communities[1]: "33"], accessGroup: nil,
      liveActivityAdd: { query in
        attempts += 1
        return attempts <= 1 ? errSecInteractionNotAllowed : SecItemAdd(query, nil)
      })
    XCTAssertEqual(BuzzPushSigningKeychain.privateKey(communityID: communities[0], accessGroup: nil), "22")
    XCTAssertEqual(BuzzPushSigningKeychain.privateKey(communityID: communities[1], accessGroup: nil), "33")
    XCTAssertNil(BuzzLiveActivitySigningKeychain.privateKey(communityID: communities[0], accessGroup: nil))
    XCTAssertNil(BuzzLiveActivitySigningKeychain.privateKey(communityID: communities[1], accessGroup: nil))
    NotificationCenter.default.post(name: UIApplication.protectedDataDidBecomeAvailableNotification, object: nil)
    XCTAssertEqual(BuzzLiveActivitySigningKeychain.privateKey(communityID: communities[0], accessGroup: nil), "22")
    XCTAssertEqual(BuzzLiveActivitySigningKeychain.privateKey(communityID: communities[1], accessGroup: nil), "33")
    XCTAssertEqual(BuzzPushSigningKeychain.privateKey(communityID: communities[0], accessGroup: nil), "22")
    XCTAssertEqual(attempts, 3)
    NotificationCenter.default.post(name: UIApplication.protectedDataDidBecomeAvailableNotification, object: nil)
    XCTAssertEqual(attempts, 3)
  }

  func testPendingKeyWriteRetriesWhenTheAppBecomesActive() {
    let attempts = Counter()
    BuzzLiveActivityKeyWriter.shared.write {
      attempts.increment() == 1 ? errSecInteractionNotAllowed : errSecSuccess
    }
    XCTAssertEqual(attempts.value, 1)
    NotificationCenter.default.post(name: UIApplication.didBecomeActiveNotification, object: nil)
    XCTAssertEqual(attempts.value, 2)
    NotificationCenter.default.post(name: UIApplication.didBecomeActiveNotification, object: nil)
    XCTAssertEqual(attempts.value, 2)
  }

  func testOlderPendingWriteNeverRunsAfterANewerWrite() {
    for _ in 0..<300 {
      let order = Recorder()
      let old = Counter()
      BuzzLiveActivityKeyWriter.shared.write {
        order.append("old")
        return old.increment() == 1 ? errSecInteractionNotAllowed : errSecSuccess
      }
      DispatchQueue.concurrentPerform(iterations: 2) { index in
        if index == 0 {
          NotificationCenter.default.post(name: UIApplication.protectedDataDidBecomeAvailableNotification, object: nil)
        } else {
          BuzzLiveActivityKeyWriter.shared.write {
            order.append("new")
            return errSecSuccess
          }
        }
      }
      XCTAssertEqual(order.values.last, "new", "\(order.values)")
      guard order.values.last == "new" else { return }
    }
  }

  func testFailedLiveActivityWriteNeverRemovesExtensionKeys() throws {
    try BuzzPushKeychain.replace(
      signingKeys: [communities[0]: "44"], accessGroup: nil, liveActivityAdd: { _ in errSecDuplicateItem })
    XCTAssertEqual(BuzzPushSigningKeychain.privateKey(communityID: communities[0], accessGroup: nil), "44")
    XCTAssertNil(BuzzLiveActivitySigningKeychain.privateKey(communityID: communities[0], accessGroup: nil))
  }

  func testIntentsUseTheirAuthenticationPolicyAndSigningKey() throws {
    guard #available(iOS 18.0, *) else { throw XCTSkip("Live Activity intents need iOS 18") }
    XCTAssertEqual(BuzzApprovalDecisionIntent.authenticationPolicy, .requiresLocalDeviceAuthentication)
    XCTAssertEqual(BuzzWatchApprovalDecisionIntent.authenticationPolicy, .requiresAuthentication)
    XCTAssertFalse(BuzzApprovalDecisionIntent.isDiscoverable)
    XCTAssertFalse(BuzzWatchApprovalDecisionIntent.isDiscoverable)
    XCTAssertEqual(BuzzLiveActivitySigningKeychain.service, "buzz.liveactivity.signing")
    try BuzzPushKeychain.replace(signingKeys: [communities[0]: "55"], accessGroup: nil)
    let update: [String: Any] = [kSecValueData as String: Data("66".utf8)]
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: "buzz.liveactivity.signing",
      kSecAttrAccount as String: communities[0],
    ]
    XCTAssertEqual(SecItemUpdate(query as CFDictionary, update as CFDictionary), errSecSuccess)
    XCTAssertEqual(BuzzApprovalDecisionIntent.signingKey(communityID: communities[0], accessGroup: nil), "66")
    XCTAssertEqual(BuzzWatchApprovalDecisionIntent.signingKey(communityID: communities[0], accessGroup: nil), "55")
  }
}

private final class Counter: @unchecked Sendable {
  private let lock = NSLock()
  private var count = 0

  var value: Int {
    lock.lock()
    defer { lock.unlock() }
    return count
  }

  func increment() -> Int {
    lock.lock()
    defer { lock.unlock() }
    count += 1
    return count
  }
}

private final class Recorder: @unchecked Sendable {
  private let lock = NSLock()
  private var items: [String] = []

  var values: [String] {
    lock.lock()
    defer { lock.unlock() }
    return items
  }

  func append(_ item: String) {
    lock.lock()
    defer { lock.unlock() }
    items.append(item)
  }
}
