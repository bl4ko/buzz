import ActivityKit
import BuzzPushKit
import Foundation
import os.log

@available(iOS 18.0, *)
final class LiveActivityCoordinator: @unchecked Sendable {
  private typealias Attributes = BuzzApprovalsActivityAttributes
  private static let registrationKey = "buzz.liveactivity.registration.v2"

  private let appGroupIdentifier: String?
  private let endpointGrantStore: BuzzPushEndpointGrantKeychainStore
  private let keychainAccessGroup: String?
  private let updateTokens: BuzzLiveActivityUpdateTokenSync
  private static let log = Logger(subsystem: "com.bl4ko.buzz", category: "live-activity")
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
    updateTokens = BuzzLiveActivityUpdateTokenSync { origin, token in
      do {
        try await Self.registrar(store: endpointGrantStore, accessGroup: keychainAccessGroup, gatewayOrigin: nil)
          .setUpdateToken(origin: origin, token: token)
      } catch {
        Self.log.error("Live Activity update token failed: \(String(describing: error), privacy: .public)")
        throw error
      }
    }
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
      let previous = refreshTask
      previous?.cancel()
      refreshTask = Task { [weak self] in
        await previous?.value
        await self?.reconcile()
      }
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
    let origins = snapshot.map(BuzzLiveActivityOrigin.origins(in:))
    if snapshot != nil || !enabled {
      let allowed = Set(enabled ? origins ?? [] : [])
      let registered = await updateTokens.registeredActivities()
      await endActivities(
        BuzzLiveActivityInstance.activitiesToEnd(instances(), allowedOrigins: allowed, registered: registered))
    }
    guard !Task.isCancelled, let records = try? endpointGrantStore.records() else { return }
    guard
      let request = BuzzLiveActivityStartPlanner.request(
        records: records,
        origins: origins,
        activitiesEnabled: enabled,
        startToken: locked { startToken },
        now: Int64(Date().timeIntervalSince1970),
        registeredFingerprint: defaults?.string(forKey: Self.registrationKey)
      )
    else { return }
    do {
      try await Self.registrar(
        store: endpointGrantStore, accessGroup: keychainAccessGroup, gatewayOrigin: request.installation.gatewayOrigin
      ).register(request)
      defaults?.set(request.fingerprint, forKey: Self.registrationKey)
    } catch {
      Self.log.error("Live Activity registration failed: \(String(describing: error), privacy: .public)")
    }
  }

  private func observe(_ activity: Activity<Attributes>) {
    let isNew = locked { observed.insert(activity.id).inserted }
    guard isNew else { return }
    let origin = activity.attributes.origin
    let id = activity.id
    let updateTokens = updateTokens
    Task {
      for await token in activity.pushTokenUpdates {
        await updateTokens.tokenChanged(origin: origin, activityID: id, token: token)
      }
    }
    Task {
      if activity.activityState == .ended || activity.activityState == .dismissed {
        await updateTokens.activityEnded(origin: origin, activityID: id)
        return
      }
      for await state in activity.activityStateUpdates where state == .ended || state == .dismissed {
        await updateTokens.activityEnded(origin: origin, activityID: id)
        break
      }
    }
  }

  private func instances() -> [BuzzLiveActivityInstance] {
    Activity<Attributes>.activities.filter { $0.activityState == .active || $0.activityState == .stale }.map {
      BuzzLiveActivityInstance(id: $0.id, origin: $0.attributes.origin, staleDate: $0.content.staleDate)
    }
  }

  private func endActivities(_ ids: [String]) async {
    guard !ids.isEmpty else { return }
    let ending = Set(ids)
    for activity in Activity<Attributes>.activities where ending.contains(activity.id) {
      await activity.end(nil, dismissalPolicy: .immediate)
    }
  }

  private static func registrar(
    store: BuzzPushEndpointGrantKeychainStore,
    accessGroup: String?,
    gatewayOrigin: String?
  ) throws -> BuzzLiveActivityRegistrar {
    let gateway =
      try gatewayOrigin
      ?? BuzzLiveActivityInstallation.current(records: store.records(), now: Int64(Date().timeIntervalSince1970))?
      .gatewayOrigin
    guard let gateway, let url = URL(string: gateway) else { throw BuzzLiveActivityRegistrationError.notEnrolled }
    return try BuzzLiveActivityRegistrar(gatewayBaseURL: url, store: store, appAttestKeychainAccessGroup: accessGroup)
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
