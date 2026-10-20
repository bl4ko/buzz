import Foundation

public enum BuzzStoredIdentityRecovery {
  public static func communities(
    snapshot: PushLeaseSnapshot?,
    privateKey: (String) -> String?
  ) -> [[String: String]] {
    (snapshot?.communities ?? []).compactMap { community in
      guard let pubkey = community.pubkey, !pubkey.isEmpty,
        let key = privateKey(community.id), BuzzLiveActivityOrigin.isLowercaseHex64(key)
      else { return nil }
      return [
        "id": community.id,
        "name": community.name,
        "relayUrl": community.relayUrl,
        "pubkey": pubkey,
        "privateKey": key,
      ]
    }
  }
}
