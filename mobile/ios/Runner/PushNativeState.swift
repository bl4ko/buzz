import BuzzPushKit
import Foundation
import Security
import UserNotifications

final class BuzzOneShotCompletion {
  private let lock = NSLock()
  private var completion: (() -> Void)?

  init(_ completion: @escaping () -> Void) {
    self.completion = completion
  }

  func call() {
    lock.lock()
    let completion = completion
    self.completion = nil
    lock.unlock()
    completion?()
  }
}

enum BuzzPushNotificationResponseCoordinator {
  static func handle(
    actionIdentifier: String,
    userInfo: [AnyHashable: Any],
    onTarget: (BuzzPushNavigationTarget) -> Void,
    onApproval: (BuzzApprovalTarget, BuzzApprovalDecision, @escaping () -> Void) -> Void = { _, _, done in done() },
    forwardToFlutter: (@escaping () -> Void) -> Void,
    completion: @escaping () -> Void
  ) {
    let completionGate = BuzzOneShotCompletion(completion)
    if let decision = BuzzApprovalDecision(rawValue: actionIdentifier),
      let target = BuzzApprovalTarget.decodeIfPresent(from: userInfo)
    {
      onApproval(target, decision) { completionGate.call() }
      return
    }
    defer { completionGate.call() }

    if actionIdentifier == UNNotificationDefaultActionIdentifier,
      let target = BuzzPushNavigationTarget.decodeIfPresent(from: userInfo)
    {
      onTarget(target)
    }
    forwardToFlutter { completionGate.call() }
  }
}

enum BuzzPushKeychain {
  static let service = "buzz.push.nse.signing"
  static let items: [(service: String, accessible: CFString)] = [
    (service, kSecAttrAccessibleAfterFirstUnlock),
    (BuzzLiveActivitySigningKeychain.service, kSecAttrAccessibleWhenUnlockedThisDeviceOnly),
  ]

  static func replace(signingKeys: [String: String], accessGroup: String?) throws {
    try deleteAll(accessGroup: accessGroup)
    for (communityID, privateKeyHex) in signingKeys {
      for item in items {
        var query = baseQuery(service: item.service, accessGroup: accessGroup)
        query[kSecAttrAccount as String] = communityID
        query[kSecValueData as String] = Data(privateKeyHex.utf8)
        query[kSecAttrAccessible as String] = item.accessible
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
          try? deleteAll(accessGroup: accessGroup)
          throw keychainError(status, fallback: "Keychain write failed")
        }
      }
    }
  }

  /// Replaces the shared organization session. Device-only, like the app's own copy.
  static func replace(organizationSession: BuzzOrganizationSession?, accessGroup: String?) throws {
    var query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: BuzzOrganizationSession.keychainService,
      kSecAttrAccount as String: BuzzOrganizationSession.keychainAccount,
    ]
    if let accessGroup, !accessGroup.isEmpty {
      query[kSecAttrAccessGroup as String] = accessGroup
    }
    let deletionStatus = SecItemDelete(query as CFDictionary)
    guard deletionStatus == errSecSuccess || deletionStatus == errSecItemNotFound else {
      throw keychainError(deletionStatus, fallback: "Keychain deletion failed")
    }
    guard let organizationSession else { return }
    query[kSecValueData as String] = try JSONEncoder().encode(organizationSession)
    query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
    let status = SecItemAdd(query as CFDictionary, nil)
    guard status == errSecSuccess else {
      throw keychainError(status, fallback: "Keychain write failed")
    }
  }

  private static func deleteAll(accessGroup: String?) throws {
    for item in items {
      let status = SecItemDelete(baseQuery(service: item.service, accessGroup: accessGroup) as CFDictionary)
      guard status == errSecSuccess || status == errSecItemNotFound else {
        throw keychainError(status, fallback: "Keychain deletion failed")
      }
    }
  }

  private static func keychainError(_ status: OSStatus, fallback: String) -> NSError {
    NSError(
      domain: NSOSStatusErrorDomain, code: Int(status),
      userInfo: [
        NSLocalizedDescriptionKey: SecCopyErrorMessageString(status, nil) ?? fallback as CFString
      ]
    )
  }

  private static func baseQuery(service: String, accessGroup: String?) -> [String: Any] {
    var query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
    ]
    if let accessGroup, !accessGroup.isEmpty {
      query[kSecAttrAccessGroup as String] = accessGroup
    }
    return query
  }
}
