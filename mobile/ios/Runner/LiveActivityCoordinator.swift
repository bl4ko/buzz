import ActivityKit
import BuzzPushKit
import CryptoKit
import Foundation
import os.log

@available(iOS 18.0, *)
final class LiveActivityCoordinator: @unchecked Sendable {
  private typealias Attributes = BuzzApprovalsActivityAttributes
  private static let registrationKey = "buzz.liveactivity.registration.v1"
  private static let offRegistration = "off"

  private let appGroupIdentifier: String?
  private let endpointGrantStore: BuzzPushEndpointGrantKeychainStore
  private let keychainAccessGroup: String?
  private let log = Logger(subsystem: "com.bl4ko.buzz", category: "live-activity")
  private let lock = NSLock()
  private var startToken: Data?
  private var observed: Set<String> = []
  private var refreshTask: Task<Void, Never>?
  private var started = false

  init(
    appGroupIdentifier: String?,
    endpointGrantStore: BuzzPushEndpointGrantKeychainStore,
    keychainAccessGroup: String?
  ) {
    self.appGroupIdentifier = appGroupIdentifier
    self.endpointGrantStore = endpointGrantStore
    self.keychainAccessGroup = keychainAccessGroup
  }

  private var defaults: UserDefaults? { appGroupIdentifier.flatMap(UserDefaults.init(suiteName:)) }

  func start() {
    guard locked({ () -> Bool in
      defer { started = true }
      return !started
    }) else { return }
    setStartToken(Activity<Attributes>.pushToStartToken)
    Task { [weak self] in
      for await token in Activity<Attributes>.pushToStartTokenUpdates {
        self?.setStartToken(token)
      }
    }
    Task { [weak self] in
      try? await Task.sleep(nanoseconds: 3_000_000_000)
      if let token = Activity<Attributes>.pushToStartToken { self?.setStartToken(token) }
    }
    Task { [weak self] in
      for await activity in Activity<Attributes>.activityUpdates {
        self?.observe(activity)
        self?.refresh()
      }
    }
    Activity<Attributes>.activities.forEach(observe)
    refresh()
  }

  func refresh() {
    locked {
      refreshTask?.cancel()
      refreshTask = Task { [weak self] in await self?.reconcile() }
    }
  }

  private func setStartToken(_ token: Data?) {
    guard let token else { return }
    let changed = locked { () -> Bool in
      defer { startToken = token }
      return startToken != token
    }
    if changed { refresh() }
  }

  private func reconcile() async {
    let snapshot = BuzzPushStoredRelay.snapshotURL(appGroupIdentifier: appGroupIdentifier)
      .flatMap(BuzzPushStoredRelay.snapshot(at:))
    let enabled = ActivityAuthorizationInfo().areActivitiesEnabled
    let origins = enabled ? (snapshot.map(BuzzLiveActivityOrigin.origins(in:)) ?? []) : []
    if snapshot != nil || !enabled {
      await endActivities(BuzzLiveActivityInstance.activitiesToEnd(instances(), allowedOrigins: Set(origins)))
    }
    guard !Task.isCancelled else { return }
    let token = locked { startToken }
    let registration: String
    let registeredToken: Data?
    let registeredOrigins: [String]
    if origins.isEmpty {
      guard snapshot != nil || !enabled else { return }
      registration = Self.offRegistration
      registeredToken = nil
      registeredOrigins = []
    } else {
      guard let token else { return }
      registration = Self.fingerprint(token: token, origins: origins)
      registeredToken = token
      registeredOrigins = origins
    }
    guard defaults?.string(forKey: Self.registrationKey) != registration else { return }
    if registration == Self.offRegistration && defaults?.string(forKey: Self.registrationKey) == nil { return }
    do {
      try await registrar()?.registerStart(token: registeredToken, origins: registeredOrigins)
      defaults?.set(registration, forKey: Self.registrationKey)
    } catch {
      log.error("Live Activity registration failed: \(String(describing: error), privacy: .public)")
    }
  }

  private func observe(_ activity: Activity<Attributes>) {
    let isNew = locked { observed.insert(activity.id).inserted }
    guard isNew else { return }
    let origin = activity.attributes.origin
    Task { [weak self] in
      for await token in activity.pushTokenUpdates {
        await self?.setUpdateToken(origin: origin, token: token)
      }
    }
    Task { [weak self] in
      for await state in activity.activityStateUpdates where state == .ended || state == .dismissed {
        await self?.setUpdateToken(origin: origin, token: nil)
        break
      }
    }
  }

  private func setUpdateToken(origin: String, token: Data?) async {
    do {
      try await registrar()?.setUpdateToken(origin: origin, token: token)
    } catch {
      log.error("Live Activity update token failed: \(String(describing: error), privacy: .public)")
    }
  }

  private func instances() -> [BuzzLiveActivityInstance] {
    Activity<Attributes>.activities.map {
      BuzzLiveActivityInstance(id: $0.id, origin: $0.attributes.origin, askedAt: $0.content.state.askedAt)
    }
  }

  private func endActivities(_ ids: [String]) async {
    guard !ids.isEmpty else { return }
    let ending = Set(ids)
    for activity in Activity<Attributes>.activities where ending.contains(activity.id) {
      await activity.end(nil, dismissalPolicy: .immediate)
    }
  }

  private func registrar() throws -> BuzzLiveActivityRegistrar? {
    let gateway = try endpointGrantStore.records()
      .filter { $0.appProfile == BuzzDevPushEnrollmentDriver.appProfile && $0.gatewayInstallationHandle != nil }
      .max { $0.expiresAt < $1.expiresAt }?
      .gatewayOrigin
    guard let gateway, let url = URL(string: gateway) else { return nil }
    return try BuzzLiveActivityRegistrar(
      gatewayBaseURL: url,
      store: endpointGrantStore,
      appAttestKeychainAccessGroup: keychainAccessGroup
    )
  }

  private static func fingerprint(token: Data, origins: [String]) -> String {
    var hash = SHA256()
    hash.update(data: token)
    for origin in origins { hash.update(data: Data(("\n" + origin).utf8)) }
    return hash.finalize().map { String(format: "%02x", $0) }.joined()
  }

  private func locked<T>(_ body: () -> T) -> T {
    lock.lock()
    defer { lock.unlock() }
    return body()
  }

  #if DEBUG
    static func startDemoActivityIfRequested() -> Bool {
      guard ProcessInfo.processInfo.arguments.contains("-BuzzLiveActivityDemo") else { return false }
      let state = BuzzApprovalsContentState(
        askEventID: String(repeating: "ab", count: 32), caseID: "ATH-AGENT-N8N-ENV-ACCESS-001",
        ask: "Approve rotating the n8n env secret?", agent: "Zeus", channel: "agents-coordination", openCount: 3,
        askedAt: Int(Date().timeIntervalSince1970) - 240
      ).marking(ProcessInfo.processInfo.arguments.contains("-BuzzLiveActivityDemoApproving") ? .approve : nil)
      Task {
        for activity in Activity<Attributes>.activities {
          await activity.end(nil, dismissalPolicy: .immediate)
        }
        _ = try? Activity.request(
          attributes: Attributes(origin: "https://buzz.bl4ko.com"),
          content: ActivityContent(state: state, staleDate: Date().addingTimeInterval(7200), relevanceScore: 100)
        )
      }
      return true
    }
  #endif
}

enum BuzzLiveActivities {
  nonisolated(unsafe) private static var coordinator: AnyObject?

  static func start(
    appGroupIdentifier: String?,
    endpointGrantStore: BuzzPushEndpointGrantKeychainStore,
    keychainAccessGroup: String?
  ) {
    guard #available(iOS 18.0, *), coordinator == nil else { return }
    let created = LiveActivityCoordinator(
      appGroupIdentifier: appGroupIdentifier,
      endpointGrantStore: endpointGrantStore,
      keychainAccessGroup: keychainAccessGroup
    )
    coordinator = created
    #if DEBUG
      if LiveActivityCoordinator.startDemoActivityIfRequested() { return }
    #endif
    created.start()
  }

  static func refresh() {
    guard #available(iOS 18.0, *) else { return }
    (coordinator as? LiveActivityCoordinator)?.refresh()
  }
}
