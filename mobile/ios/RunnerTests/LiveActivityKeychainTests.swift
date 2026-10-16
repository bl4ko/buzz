import BuzzPushKit
import Security
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
}
