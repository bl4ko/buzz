import CryptoKit
import XCTest

@testable import BuzzPushKit

final class BuzzSimulatorAppAttestTests: XCTestCase {
  private let clientDataHash = Data(SHA256.hash(data: Data("transcript".utf8)))

  func testAttestationSignsClientDataWithTheKeyNamedByKeyId() async throws {
    let service = BuzzSimulatorAppAttestService(appID: "simulator.app", store: MemoryStore())
    let keyId = try await service.generateKey()
    XCTAssertEqual(Data(base64Encoded: keyId)?.count, 32)

    let object = try await service.attestKey(keyId, clientDataHash: clientDataHash)
    let fields = try XCTUnwrap(JSONSerialization.jsonObject(with: object) as? [String: String])
    XCTAssertEqual(Set(fields.keys), ["fmt", "publicKey", "signature"])
    XCTAssertEqual(fields["fmt"], "buzz-ios-simulator")
    let publicKeyData = try XCTUnwrap(Data(base64Encoded: fields["publicKey"] ?? ""))
    XCTAssertEqual(Data(SHA256.hash(data: publicKeyData)).base64EncodedString(), keyId)
    let publicKey = try P256.Signing.PublicKey(x963Representation: publicKeyData)
    let signature = try P256.Signing.ECDSASignature(
      derRepresentation: try XCTUnwrap(Data(base64Encoded: fields["signature"] ?? "")))
    XCTAssertTrue(publicKey.isValidSignature(signature, for: clientDataHash))
  }

  func testAssertionUsesTheAppAttestLayoutAndAnIncreasingCounter() async throws {
    let service = BuzzSimulatorAppAttestService(appID: "simulator.app", store: MemoryStore())
    let keyId = try await service.generateKey()
    let attestation = try await service.attestKey(keyId, clientDataHash: clientDataHash)
    let fields = try XCTUnwrap(JSONSerialization.jsonObject(with: attestation) as? [String: String])
    let publicKey = try P256.Signing.PublicKey(
      x963Representation: try XCTUnwrap(Data(base64Encoded: fields["publicKey"] ?? "")))

    var counters: [UInt32] = []
    for _ in 0..<2 {
      let cbor = try await service.generateAssertion(keyId, clientDataHash: clientDataHash)
      XCTAssertEqual(cbor.first, 0xA2)
      let authenticatorData = try XCTUnwrap(Self.bytes(after: "authenticatorData", in: cbor))
      let signature = try XCTUnwrap(Self.bytes(after: "signature", in: cbor))
      XCTAssertEqual(authenticatorData.count, 37)
      XCTAssertEqual(authenticatorData.prefix(32), Data(SHA256.hash(data: Data("simulator.app".utf8))))
      counters.append(authenticatorData.suffix(4).reduce(0) { $0 << 8 | UInt32($1) })
      let nonce = Data(SHA256.hash(data: authenticatorData + clientDataHash))
      XCTAssertTrue(
        publicKey.isValidSignature(try P256.Signing.ECDSASignature(derRepresentation: signature), for: nonce))
    }
    XCTAssertEqual(counters, [1, 2])
  }

  func testUnknownKeyIsRejected() async {
    let service = BuzzSimulatorAppAttestService(appID: "simulator.app", store: MemoryStore())
    do {
      _ = try await service.generateAssertion("missing", clientDataHash: clientDataHash)
      XCTFail("expected an error")
    } catch {}
  }

  private static func bytes(after name: String, in cbor: Data) -> Data? {
    let key = Data([0x60 | UInt8(name.utf8.count)]) + Data(name.utf8)
    guard let range = cbor.range(of: key), cbor.count > range.upperBound + 1,
      cbor[range.upperBound] == 0x58
    else { return nil }
    let start = range.upperBound + 2
    let length = Int(cbor[range.upperBound + 1])
    return cbor.count >= start + length ? cbor.subdata(in: start..<start + length) : nil
  }
}

private final class MemoryStore: BuzzSimulatorAppAttestKeyStoring, @unchecked Sendable {
  private var keys: [String: Data] = [:]
  private var counters: [String: UInt32] = [:]

  func save(_ key: Data, keyId: String) throws { keys[keyId] = key }
  func key(_ keyId: String) throws -> Data? { keys[keyId] }
  func nextCounter(_ keyId: String) throws -> UInt32 {
    counters[keyId, default: 0] += 1
    return counters[keyId, default: 0]
  }
}
