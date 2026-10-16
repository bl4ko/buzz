import Foundation

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

public enum BuzzLiveActivityRegistrationError: Error, Equatable {
  case notEnrolled
  case invalidOrigin
  case rejected(status: Int)
  case invalidResponse
}

public final class BuzzLiveActivityRegistrar {
  public static let maximumOrigins = 16

  private let gatewayBaseURL: URL
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
    self.gatewayBaseURL = try BuzzPushTranscript.canonicalGatewayOrigin(gatewayBaseURL).url
    self.session = session
    self.appAttest = appAttest
    self.now = now
  }

  public func registerStart(token: Data?, origins: [String]) async throws {
    let startToken = token.map(Self.hex)
    let hashes =
      startToken == nil
      ? []
      : Array(Set(origins.compactMap(BuzzLiveActivityOrigin.hashHex)).sorted().prefix(Self.maximumOrigins))
    let installation = try installation()
    let challenge = try await driver.challenge()
    let clientData = try BuzzPushTranscript.liveActivity(
      gatewayOrigin: gatewayBaseURL,
      challengeId: challenge.id,
      challenge: challenge.value,
      installationHandle: installation.handle,
      startToken: startToken,
      origins: hashes
    )
    let assertion = try await appAttest.assertion(keyId: installation.keyId, clientData: clientData)
    try await post(
      route: "v1/installations/live-activity",
      body: StartRequest(
        challengeId: challenge.id.uuidString.lowercased(),
        challenge: challenge.value,
        installationHandle: installation.handle.uuidString.lowercased(),
        startToken: startToken,
        origins: hashes,
        assertion: assertion
      )
    )
  }

  public func setUpdateToken(origin: String, token: Data?) async throws {
    guard let originHash = BuzzLiveActivityOrigin.hashHex(origin) else {
      throw BuzzLiveActivityRegistrationError.invalidOrigin
    }
    let updateToken = token.map(Self.hex)
    let installation = try installation()
    let challenge = try await driver.challenge()
    let clientData = try BuzzPushTranscript.liveActivityUpdate(
      gatewayOrigin: gatewayBaseURL,
      challengeId: challenge.id,
      challenge: challenge.value,
      installationHandle: installation.handle,
      originHash: originHash,
      updateToken: updateToken
    )
    let assertion = try await appAttest.assertion(keyId: installation.keyId, clientData: clientData)
    try await post(
      route: "v1/installations/live-activity/update-token",
      body: UpdateRequest(
        challengeId: challenge.id.uuidString.lowercased(),
        challenge: challenge.value,
        installationHandle: installation.handle.uuidString.lowercased(),
        originHash: originHash,
        updateToken: updateToken,
        assertion: assertion
      )
    )
  }

  private func installation() throws -> (handle: UUID, keyId: String) {
    let nowSeconds = Int64(now().timeIntervalSince1970)
    let record = try driver.endpointGrants().filter { record in
      guard record.appProfile == BuzzDevPushEnrollmentDriver.appProfile,
        record.expiresAt > nowSeconds,
        let handle = record.gatewayInstallationHandle,
        let uuid = UUID(uuidString: handle)
      else { return false }
      return handle == uuid.uuidString.lowercased()
    }.max { $0.expiresAt < $1.expiresAt }
    guard let record, let handle = record.gatewayInstallationHandle.flatMap(UUID.init(uuidString:)) else {
      throw BuzzLiveActivityRegistrationError.notEnrolled
    }
    return (handle, record.appAttestKeyId)
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
