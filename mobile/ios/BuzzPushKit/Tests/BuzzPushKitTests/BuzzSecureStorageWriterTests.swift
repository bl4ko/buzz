import Foundation
import Security
import XCTest
@testable import BuzzPushKit

final class BuzzSecureStorageWriterTests: XCTestCase {
  private let returnKeys = [kSecReturnData, kSecReturnAttributes, kSecReturnRef, kSecReturnPersistentRef, kSecMatchLimit]
    .map { $0 as String }

  private func dictionary(_ value: CFDictionary) -> [String: Any] {
    value as NSDictionary as? [String: Any] ?? [:]
  }

  func testUpdatesTheFlutterSecureStorageItemInPlace() {
    var updates: [([String: Any], [String: Any])] = []
    var adds = 0
    let status = BuzzSecureStorageWriter.write(
      key: "buzz_communities", value: "[1]",
      update: { query, attributes in
        updates.append((self.dictionary(query), self.dictionary(attributes)))
        return errSecSuccess
      },
      add: { _ in
        adds += 1
        return errSecSuccess
      })

    XCTAssertEqual(status, errSecSuccess)
    XCTAssertEqual(adds, 0)
    XCTAssertEqual(updates.count, 1)
    let (query, attributes) = updates[0]
    XCTAssertEqual(query[kSecAttrService as String] as? String, "flutter_secure_storage_service")
    XCTAssertEqual(query[kSecAttrAccount as String] as? String, "buzz_communities")
    XCTAssertEqual(query[kSecAttrAccessible as String] as? String, kSecAttrAccessibleWhenUnlocked as String)
    XCTAssertEqual(query[kSecAttrSynchronizable as String] as? Bool, false)
    XCTAssertTrue(returnKeys.allSatisfy { query[$0] == nil })
    XCTAssertEqual(attributes.keys.sorted(), [kSecValueData as String])
    XCTAssertEqual(attributes[kSecValueData as String] as? Data, Data("[1]".utf8))
  }

  func testAddsOnlyWhenTheItemIsMissing() {
    var added: [String: Any]?
    let status = BuzzSecureStorageWriter.write(
      key: "buzz_active_community_id", value: "id",
      update: { _, _ in errSecItemNotFound },
      add: { item in
        added = self.dictionary(item)
        return errSecSuccess
      })

    XCTAssertEqual(status, errSecSuccess)
    XCTAssertEqual(added?[kSecAttrAccount as String] as? String, "buzz_active_community_id")
    XCTAssertEqual(added?[kSecValueData as String] as? Data, Data("id".utf8))
    XCTAssertEqual(added?[kSecAttrAccessible as String] as? String, kSecAttrAccessibleWhenUnlocked as String)
  }

  func testAFailedUpdateLeavesTheStoredItemAlone() {
    for failure in [errSecInteractionNotAllowed, errSecParam, errSecAuthFailed, errSecIO] {
      var adds = 0
      let status = BuzzSecureStorageWriter.write(
        key: "buzz_communities", value: "[2]",
        update: { _, _ in failure },
        add: { _ in
          adds += 1
          return errSecSuccess
        })

      XCTAssertEqual(status, failure)
      XCTAssertEqual(adds, 0)
    }
  }
}
