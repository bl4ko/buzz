import BuzzPushKit
import Foundation
import Security
import UIKit
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

  static func replace(
    signingKeys: [String: String],
    accessGroup: String?,
    liveActivityAdd: @escaping (CFDictionary) -> OSStatus = { SecItemAdd($0, nil) }
  ) throws {
    let status = replaceItems(
      service: service, accessible: kSecAttrAccessibleAfterFirstUnlock, signingKeys: signingKeys,
      accessGroup: accessGroup, add: { SecItemAdd($0, nil) })
    guard status == errSecSuccess else { throw error(status, fallback: "Keychain write failed") }
    BuzzLiveActivityKeyWriter.shared.write {
      replaceItems(
        service: BuzzLiveActivitySigningKeychain.service, accessible: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
        signingKeys: signingKeys, accessGroup: accessGroup, add: liveActivityAdd)
    }
  }

  private static func replaceItems(
    service: String,
    accessible: CFString,
    signingKeys: [String: String],
    accessGroup: String?,
    add: (CFDictionary) -> OSStatus
  ) -> OSStatus {
    let deletion = SecItemDelete(baseQuery(service: service, accessGroup: accessGroup) as CFDictionary)
    guard deletion == errSecSuccess || deletion == errSecItemNotFound else { return deletion }
    for (communityID, privateKeyHex) in signingKeys {
      var query = baseQuery(service: service, accessGroup: accessGroup)
      query[kSecAttrAccount as String] = communityID
      query[kSecValueData as String] = Data(privateKeyHex.utf8)
      query[kSecAttrAccessible as String] = accessible
      let status = add(query as CFDictionary)
      guard status == errSecSuccess else {
        SecItemDelete(baseQuery(service: service, accessGroup: accessGroup) as CFDictionary)
        return status
      }
    }
    return errSecSuccess
  }

  private static func error(_ status: OSStatus, fallback: String) -> NSError {
    NSError(
      domain: NSOSStatusErrorDomain, code: Int(status),
      userInfo: [NSLocalizedDescriptionKey: SecCopyErrorMessageString(status, nil) ?? fallback as CFString]
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

final class BuzzLiveActivityKeyWriter {
  static let shared = BuzzLiveActivityKeyWriter()

  private let lock = NSLock()
  private var pending: (() -> OSStatus)?
  private var observer: NSObjectProtocol?

  func write(_ attempt: @escaping () -> OSStatus) {
    let previous = locked { () -> NSObjectProtocol? in
      pending = nil
      defer { observer = nil }
      return observer
    }
    if let previous { NotificationCenter.default.removeObserver(previous) }
    guard attempt() == errSecInteractionNotAllowed else { return }
    let token = NotificationCenter.default.addObserver(
      forName: UIApplication.protectedDataDidBecomeAvailableNotification, object: nil, queue: nil
    ) { [weak self] _ in self?.retry() }
    locked {
      pending = attempt
      observer = token
    }
  }

  private func retry() {
    guard let attempt = locked({ pending }) else { return }
    write(attempt)
  }

  private func locked<T>(_ body: () -> T) -> T {
    lock.lock()
    defer { lock.unlock() }
    return body()
  }
}
