import Foundation
import Security

public enum BuzzSecureStorageWriter {
  public static let service = "flutter_secure_storage_service"

  public static func query(key: String) -> [String: Any] {
    [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: key,
      kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlocked,
      kSecAttrSynchronizable as String: false,
    ]
  }

  public static func write(
    key: String,
    value: String,
    update: (CFDictionary, CFDictionary) -> OSStatus = SecItemUpdate,
    add: (CFDictionary) -> OSStatus = { SecItemAdd($0, nil) }
  ) -> OSStatus {
    let match = query(key: key)
    let data = Data(value.utf8)
    let status = update(match as CFDictionary, [kSecValueData as String: data] as CFDictionary)
    guard status == errSecItemNotFound else { return status }
    var item = match
    item[kSecValueData as String] = data
    return add(item as CFDictionary)
  }
}
