import Foundation
import P256K

/// The BIP-340 signer behind the shared `NostrHTTPAuth.swift` in the watch
/// target, which does not link BuzzPushKit's vendored libsecp256k1.
enum NostrSchnorr {
  static func publicKey(secret: [UInt8]) throws -> [UInt8] {
    Array(try P256K.Schnorr.PrivateKey(dataRepresentation: secret).xonly.bytes)
  }

  static func sign(message: [UInt8], secret: [UInt8], auxiliaryRandomness: [UInt8]? = nil) throws
    -> [UInt8]
  {
    let key = try P256K.Schnorr.PrivateKey(dataRepresentation: secret)
    var message = message
    let signature: P256K.Schnorr.SchnorrSignature
    if var randomness = auxiliaryRandomness {
      signature = try key.signature(message: &message, auxiliaryRand: &randomness)
    } else {
      signature = try key.signature(message: &message, auxiliaryRand: nil)
    }
    return Array(signature.dataRepresentation)
  }

  static func verify(signature: [UInt8], message: [UInt8], publicKey: [UInt8]) -> Bool {
    guard let signature = try? P256K.Schnorr.SchnorrSignature(dataRepresentation: Data(signature))
    else { return false }
    var message = message
    return P256K.Schnorr.XonlyKey(dataRepresentation: publicKey).isValid(signature, for: &message)
  }
}
