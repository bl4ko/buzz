import CryptoKit
import Foundation

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

public enum BuzzLiveActivityRegistrationError: Error, Equatable {
  case notEnrolled
  case invalidOrigin
  case unboundOrigin
  case rejected(status: Int)
  case invalidResponse
}

public struct BuzzLiveActivityInstallation: Equatable, Sendable {
  public let gatewayOrigin: String
  public let handle: String
  public let appAttestKeyId: String
  public let relayPubkeys: [String: String]

  public static func current(records: [BuzzPushEndpointGrantRecord], now: Int64) -> BuzzLiveActivityInstallation? {
    let live = records.filter { record in
      guard record.appProfile == BuzzDevPushEnrollmentDriver.appProfile, record.expiresAt > now,
        let handle = record.gatewayInstallationHandle, let uuid = UUID(uuidString: handle)
      else { return false }
      return handle == uuid.uuidString.lowercased()
    }
    guard
      let newest = live.max(by: {
        ($0.expiresAt, $0.gatewayOrigin, $0.gatewayInstallationHandle ?? "")
          < ($1.expiresAt, $1.gatewayOrigin, $1.gatewayInstallationHandle ?? "")
      }),
      let handle = newest.gatewayInstallationHandle
    else { return nil }
    var keys: [String: (generation: Int64, pubkey: String)] = [:]
    for record in live where record.gatewayOrigin == newest.gatewayOrigin && record.gatewayInstallationHandle == handle {
      guard let origin = BuzzLiveActivityOrigin.canonical(record.relayOrigin),
        BuzzLiveActivityOrigin.isLowercaseHex64(record.relayPubkey)
      else { continue }
      if let known = keys[origin], known.generation >= record.generation { continue }
      keys[origin] = (record.generation, record.relayPubkey)
    }
    return BuzzLiveActivityInstallation(
      gatewayOrigin: newest.gatewayOrigin, handle: handle, appAttestKeyId: newest.appAttestKeyId,
      relayPubkeys: keys.mapValues(\.pubkey))
  }

  public func originHash(_ origin: String) -> String? {
    relayPubkeys[origin].flatMap { BuzzLiveActivityOrigin.boundHashHex(origin: origin, relayPubkey: $0) }
  }
}

public struct BuzzLiveActivityStartRequest: Equatable, Sendable {
  public let installation: BuzzLiveActivityInstallation
  public let startToken: String?
  public let originHashes: [String]

  public var fingerprint: String {
    let fields = [installation.gatewayOrigin, installation.handle, startToken ?? "off"] + originHashes
    return SHA256.hash(data: Data(fields.joined(separator: "\n").utf8)).map { String(format: "%02x", $0) }.joined()
  }
}

public enum BuzzLiveActivityStartPlanner {
  public static func request(
    records: [BuzzPushEndpointGrantRecord],
    origins: [String]?,
    activitiesEnabled: Bool,
    startToken: Data?,
    now: Int64,
    registeredFingerprint: String?
  ) -> BuzzLiveActivityStartRequest? {
    guard !activitiesEnabled || origins != nil,
      let installation = BuzzLiveActivityInstallation.current(records: records, now: now)
    else { return nil }
    let wanted = activitiesEnabled ? origins ?? [] : []
    let hashes = Array(Set(wanted.compactMap(installation.originHash)).sorted().prefix(BuzzLiveActivityRegistrar.maximumOrigins))
    let request: BuzzLiveActivityStartRequest
    if hashes.isEmpty {
      guard registeredFingerprint != nil else { return nil }
      request = BuzzLiveActivityStartRequest(installation: installation, startToken: nil, originHashes: [])
    } else {
      guard let startToken else { return nil }
      request = BuzzLiveActivityStartRequest(
        installation: installation, startToken: startToken.map { String(format: "%02x", $0) }.joined(),
        originHashes: hashes)
    }
    return request.fingerprint == registeredFingerprint ? nil : request
  }
}

public final class BuzzLiveActivityRegistrar {
  public static let maximumOrigins = 16

  private let gatewayBaseURL: URL
  private let gatewayOrigin: String
  private let driver: BuzzDevPushEnrollmentDriver
  private let session: URLSession
  private let appAttest: BuzzDevAppAttesting
  private let now: () -> Date

  public convenience init(
    gatewayBaseURL: URL,
    store: BuzzPushEndpointGrantStore,
    appAttestKeychainAccessGroup: String?,
    session: URLSession = .shared
  ) throws {
    try self.init(
      gatewayBaseURL: gatewayBaseURL,
      store: store,
      session: session,
      appAttest: BuzzDCAppAttestProvider(
        keyIdStore: BuzzAppAttestKeyIdKeychainStore(accessGroup: appAttestKeychainAccessGroup)
      ),
      now: Date.init
    )
  }

  init(
    gatewayBaseURL: URL,
    store: BuzzPushEndpointGrantStore,
    session: URLSession,
    appAttest: BuzzDevAppAttesting,
    now: @escaping () -> Date
  ) throws {
    driver = try BuzzDevPushEnrollmentDriver(
      gatewayBaseURL: gatewayBaseURL,
      store: store,
      session: session,
      appAttest: appAttest,
      now: now,
      lifetimeSeconds: 2_592_000
    )
    let canonical = try BuzzPushTranscript.canonicalGatewayOrigin(gatewayBaseURL)
    self.gatewayBaseURL = canonical.url
    gatewayOrigin = canonical.text
    self.session = session
    self.appAttest = appAttest
    self.now = now
  }

  public func register(_ request: BuzzLiveActivityStartRequest) async throws {
    guard request.installation.gatewayOrigin == gatewayOrigin,
      let handle = UUID(uuidString: request.installation.handle)
    else { throw BuzzLiveActivityRegistrationError.notEnrolled }
    let challenge = try await driver.challenge()
    let clientData = try BuzzPushTranscript.liveActivity(
      gatewayOrigin: gatewayBaseURL,
      challengeId: challenge.id,
      challenge: challenge.value,
      installationHandle: handle,
      startToken: request.startToken,
      origins: request.originHashes
    )
    let assertion = try await appAttest.assertion(keyId: request.installation.appAttestKeyId, clientData: clientData)
    try await post(
      route: "v1/installations/live-activity",
      body: StartRequest(
        challengeId: challenge.id.uuidString.lowercased(),
        challenge: challenge.value,
        installationHandle: request.installation.handle,
        startToken: request.startToken,
        origins: request.originHashes,
        assertion: assertion
      )
    )
  }

  public func setUpdateToken(origin: String, token: Data?) async throws {
    guard BuzzLiveActivityOrigin.canonical(origin) == origin else {
      throw BuzzLiveActivityRegistrationError.invalidOrigin
    }
    let installation = try installation()
    guard let originHash = installation.originHash(origin), let handle = UUID(uuidString: installation.handle) else {
      throw BuzzLiveActivityRegistrationError.unboundOrigin
    }
    let updateToken = token.map(Self.hex)
    let challenge = try await driver.challenge()
    let clientData = try BuzzPushTranscript.liveActivityUpdate(
      gatewayOrigin: gatewayBaseURL,
      challengeId: challenge.id,
      challenge: challenge.value,
      installationHandle: handle,
      originHash: originHash,
      updateToken: updateToken
    )
    let assertion = try await appAttest.assertion(keyId: installation.appAttestKeyId, clientData: clientData)
    try await post(
      route: "v1/installations/live-activity/update-token",
      body: UpdateRequest(
        challengeId: challenge.id.uuidString.lowercased(),
        challenge: challenge.value,
        installationHandle: installation.handle,
        originHash: originHash,
        updateToken: updateToken,
        assertion: assertion
      )
    )
  }

  private func installation() throws -> BuzzLiveActivityInstallation {
    let records = try driver.endpointGrants()
    guard let installation = BuzzLiveActivityInstallation.current(records: records, now: Int64(now().timeIntervalSince1970))
    else { throw BuzzLiveActivityRegistrationError.notEnrolled }
    return installation
  }

  private func post<Body: Encodable>(route: String, body: Body) async throws {
    let url = route.split(separator: "/").reduce(gatewayBaseURL) { $0.appendingPathComponent(String($1)) }
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.httpBody = try JSONEncoder().encode(body)
    let (_, response) = try await session.data(for: request)
    guard let http = response as? HTTPURLResponse else {
      throw BuzzLiveActivityRegistrationError.invalidResponse
    }
    guard (200...299).contains(http.statusCode) else {
      throw BuzzLiveActivityRegistrationError.rejected(status: http.statusCode)
    }
  }

  private static func hex(_ data: Data) -> String {
    data.map { String(format: "%02x", $0) }.joined()
  }
}

private struct StartRequest: Encodable {
  let challengeId: String
  let challenge: String
  let installationHandle: String
  let startToken: String?
  let origins: [String]
  let assertion: String

  enum CodingKeys: String, CodingKey {
    case v
    case challengeId = "challenge_id"
    case challenge
    case installationHandle = "installation_handle"
    case startToken = "start_token"
    case origins
    case assertion
  }

  func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(1, forKey: .v)
    try container.encode(challengeId, forKey: .challengeId)
    try container.encode(challenge, forKey: .challenge)
    try container.encode(installationHandle, forKey: .installationHandle)
    try container.encode(startToken, forKey: .startToken)
    try container.encode(origins, forKey: .origins)
    try container.encode(assertion, forKey: .assertion)
  }
}

private struct UpdateRequest: Encodable {
  let challengeId: String
  let challenge: String
  let installationHandle: String
  let originHash: String
  let updateToken: String?
  let assertion: String

  enum CodingKeys: String, CodingKey {
    case v
    case challengeId = "challenge_id"
    case challenge
    case installationHandle = "installation_handle"
    case originHash = "origin_hash"
    case updateToken = "update_token"
    case assertion
  }

  func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(1, forKey: .v)
    try container.encode(challengeId, forKey: .challengeId)
    try container.encode(challenge, forKey: .challenge)
    try container.encode(installationHandle, forKey: .installationHandle)
    try container.encode(originHash, forKey: .originHash)
    try container.encode(updateToken, forKey: .updateToken)
    try container.encode(assertion, forKey: .assertion)
  }
}
