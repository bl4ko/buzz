import CryptoKit
import DeviceCheck
import Foundation

#if canImport(Security)
  import Security
#endif

protocol BuzzSimulatorAppAttestKeyStoring: Sendable {
  func save(_ key: Data, keyId: String) throws
  func key(_ keyId: String) throws -> Data?
  func nextCounter(_ keyId: String) throws -> UInt32
}

enum BuzzSimulatorAppAttestError: Error {
  case unknownKey
  case keychain(OSStatus)
}

struct BuzzSimulatorAppAttestService: BuzzDCAppAttestServicing {
  static let format = "buzz-ios-simulator"

  let appID: String
  let store: BuzzSimulatorAppAttestKeyStoring

  var isSupported: Bool { true }

  func generateKey() async throws -> String {
    let key = P256.Signing.PrivateKey()
    let keyId = Data(SHA256.hash(data: key.publicKey.x963Representation)).base64EncodedString()
    try store.save(key.rawRepresentation, keyId: keyId)
    return keyId
  }

  func attestKey(_ keyId: String, clientDataHash: Data) async throws -> Data {
    let key = try signingKey(keyId)
    let object = [
      "fmt": Self.format,
      "publicKey": key.publicKey.x963Representation.base64EncodedString(),
      "signature": try key.signature(for: clientDataHash).derRepresentation.base64EncodedString(),
    ]
    return try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
  }

  func generateAssertion(_ keyId: String, clientDataHash: Data) async throws -> Data {
    let key = try signingKey(keyId)
    var authenticatorData = Data(SHA256.hash(data: Data(appID.utf8)))
    authenticatorData.append(0)
    withUnsafeBytes(of: try store.nextCounter(keyId).bigEndian) { authenticatorData.append(contentsOf: $0) }
    let nonce = Data(SHA256.hash(data: authenticatorData + clientDataHash))
    let signature = try key.signature(for: nonce).derRepresentation
    var cbor = Data([0xA2])
    for (name, value) in [("authenticatorData", authenticatorData), ("signature", signature)] {
      cbor.append(0x60 | UInt8(name.utf8.count))
      cbor.append(contentsOf: name.utf8)
      cbor.append(contentsOf: [0x58, UInt8(value.count)])
      cbor.append(value)
    }
    return cbor
  }

  private func signingKey(_ keyId: String) throws -> P256.Signing.PrivateKey {
    guard let raw = try store.key(keyId) else { throw BuzzSimulatorAppAttestError.unknownKey }
    return try P256.Signing.PrivateKey(rawRepresentation: raw)
  }
}

#if canImport(Security)
  struct BuzzSimulatorAppAttestKeychainStore: BuzzSimulatorAppAttestKeyStoring {
    private static let service = "buzz.push.app-attest.simulator"
    private static let lock = NSLock()

    func save(_ key: Data, keyId: String) throws {
      let item: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: Self.service,
        kSecAttrAccount as String: keyId,
        kSecValueData as String: key,
        kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
      ]
      let status = SecItemAdd(item as CFDictionary, nil)
      guard status == errSecSuccess else { throw BuzzSimulatorAppAttestError.keychain(status) }
    }

    func key(_ keyId: String) throws -> Data? {
      let query: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: Self.service,
        kSecAttrAccount as String: keyId,
        kSecReturnData as String: true,
        kSecMatchLimit as String: kSecMatchLimitOne,
      ]
      var result: CFTypeRef?
      let status = SecItemCopyMatching(query as CFDictionary, &result)
      if status == errSecItemNotFound { return nil }
      guard status == errSecSuccess else { throw BuzzSimulatorAppAttestError.keychain(status) }
      return result as? Data
    }

    func nextCounter(_ keyId: String) throws -> UInt32 {
      Self.lock.lock()
      defer { Self.lock.unlock() }
      let name = "\(Self.service).counter.\(keyId)"
      let next = UInt32(UserDefaults.standard.integer(forKey: name)) + 1
      UserDefaults.standard.set(Int(next), forKey: name)
      return next
    }
  }
#endif

extension BuzzDCAppAttestProvider {
  static var platformService: BuzzDCAppAttestServicing {
    #if targetEnvironment(simulator)
      BuzzSimulatorAppAttestService(
        appID: "simulator." + (Bundle.main.bundleIdentifier ?? ""),
        store: BuzzSimulatorAppAttestKeychainStore()
      )
    #else
      DCAppAttestService.shared
    #endif
  }
}
