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

  private let queue = DispatchQueue(label: "com.bl4ko.buzz.live-activity-keys")
  private var pending: (() -> OSStatus)?
  private var observers: [NSObjectProtocol] = []

  private init() {
    observers = [UIApplication.protectedDataDidBecomeAvailableNotification, UIApplication.didBecomeActiveNotification]
      .map { name in
        NotificationCenter.default.addObserver(forName: name, object: nil, queue: nil) { [weak self] _ in
          self?.retry()
        }
      }
  }

  func write(_ attempt: @escaping () -> OSStatus) {
    queue.sync { run(attempt) }
  }

  private func retry() {
    queue.sync {
      guard let attempt = pending else { return }
      run(attempt)
    }
  }

  private func run(_ attempt: @escaping () -> OSStatus) {
    pending = attempt() == errSecInteractionNotAllowed ? attempt : nil
  }
}
