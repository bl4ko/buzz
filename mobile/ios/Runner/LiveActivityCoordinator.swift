import ActivityKit
import BuzzPushKit
import CryptoKit
import Foundation
import UIKit
import os.log

@available(iOS 18.0, *)
final class LiveActivityCoordinator: @unchecked Sendable {
  private typealias Attributes = BuzzApprovalsActivityAttributes
  private static let registrationKey = "buzz.liveactivity.registration.v2"

  private let appGroupIdentifier: String?
  private let endpointGrantStore: BuzzPushEndpointGrantKeychainStore
  private let keychainAccessGroup: String?
  private let gateway: BuzzLiveActivityGatewaySync
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
    let registrationKey = Self.registrationKey
    gateway = BuzzLiveActivityGatewaySync(
      register: { request in
        do {
          try await Self.registrar(
            store: endpointGrantStore, accessGroup: keychainAccessGroup,
            gatewayOrigin: request.installation.gatewayOrigin
          ).register(request)
        } catch {
          Self.log.error("Live Activity registration failed: \(String(describing: error), privacy: .public)")
          throw error
        }
      },
      setUpdateToken: { origin, token in
        do {
          try await Self.registrar(store: endpointGrantStore, accessGroup: keychainAccessGroup, gatewayOrigin: nil)
            .setUpdateToken(origin: origin, token: token)
        } catch {
          Self.log.error("Live Activity update token failed: \(String(describing: error), privacy: .public)")
          throw error
        }
      },
      didRegister: { request in
        appGroupIdentifier.flatMap(UserDefaults.init(suiteName:))?.set(request.fingerprint, forKey: registrationKey)
        BuzzLiveActivities.refresh()
      })
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
      let registered = await gateway.registeredActivities()
      await endActivities(
        BuzzLiveActivityInstance.activitiesToEnd(instances(), allowedOrigins: allowed, registered: registered))
    }
    guard !Task.isCancelled, let records = try? endpointGrantStore.records() else { return }
    await gateway.register(
      BuzzLiveActivityStartPlanner.request(
        records: records,
        origins: origins,
        activitiesEnabled: enabled,
        startToken: locked { startToken },
        now: Int64(Date().timeIntervalSince1970),
        registeredFingerprint: defaults?.string(forKey: Self.registrationKey)
      ))
  }

  private func observe(_ activity: Activity<Attributes>) {
    let isNew = locked { observed.insert(activity.id).inserted }
    guard isNew else { return }
    let origin = activity.attributes.origin
    let id = activity.id
    let gateway = gateway
    Task {
      for await token in activity.pushTokenUpdates {
        await gateway.tokenChanged(origin: origin, activityID: id, token: token)
      }
    }
    Task {
      if activity.activityState == .ended || activity.activityState == .dismissed {
        await gateway.activityEnded(origin: origin, activityID: id)
        return
      }
      for await state in activity.activityStateUpdates where state == .ended || state == .dismissed {
        await gateway.activityEnded(origin: origin, activityID: id)
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
    #if DEBUG && targetEnvironment(simulator)
      QaLiveActivityBridge.start()
    #endif
    created.start()
  }

  static func refresh() {
    guard #available(iOS 18.0, *) else { return }
    (coordinator as? LiveActivityCoordinator)?.refresh()
  }
}

#if DEBUG && targetEnvironment(simulator)
  @available(iOS 18.0, *)
  actor QaLiveActivityBridge {
    private typealias Attributes = BuzzApprovalsActivityAttributes
    static let shared = QaLiveActivityBridge()
    private static let notification = "com.bl4ko.buzz.qa.live-activity" as CFString

    nonisolated static func start() {
      CFNotificationCenterAddObserver(
        CFNotificationCenterGetDarwinNotifyCenter(), nil, { _, _, _, _, _ in QaLiveActivityBridge.poke() },
        notification, nil, .deliverImmediately)
      NotificationCenter.default.addObserver(
        forName: UIApplication.didBecomeActiveNotification, object: nil, queue: nil
      ) { _ in poke() }
      poke()
    }

    nonisolated static func poke() {
      Task { @MainActor in
        guard UIApplication.shared.applicationState == .active else { return }
        await shared.drain()
      }
    }

    private let folder = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
      .appendingPathComponent("QaLiveActivity")

    private func drain() async {
      let inbox = folder.appendingPathComponent("inbox")
      let names = ((try? FileManager.default.contentsOfDirectory(atPath: inbox.path)) ?? []).filter { $0.hasSuffix(".json") }.sorted()
      for name in names {
        let file = inbox.appendingPathComponent(name)
        guard let data = try? Data(contentsOf: file) else { continue }
        try? FileManager.default.removeItem(at: file)
        let result = await apply(data)
        var line = (try? JSONSerialization.data(withJSONObject: ["file": name, "result": result])) ?? Data()
        line.append(0x0A)
        let log = folder.appendingPathComponent("applied.jsonl")
        if let handle = try? FileHandle(forWritingTo: log) {
          handle.seekToEndOfFile()
          handle.write(line)
          try? handle.close()
        } else {
          try? line.write(to: log)
        }
      }
    }

    private func apply(_ data: Data) async -> String {
      guard let message = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
        let token = message["token"] as? String, let aps = message["aps"] as? [String: Any],
        let event = aps["event"] as? String
      else { return "invalid" }
      let decode = { (value: Any?) -> BuzzApprovalsContentState? in
        value.flatMap { try? JSONSerialization.data(withJSONObject: $0) }
          .flatMap { try? JSONDecoder().decode(BuzzApprovalsContentState.self, from: $0) }
      }
      let date = { (key: String) in (aps[key] as? Double).map(Date.init(timeIntervalSince1970:)) }
      let fingerprint = { (token: Data?) in token.map { SHA256.hash(data: $0).map { String(format: "%02x", $0) }.joined() } }
      if event == "start" {
        guard fingerprint(Activity<Attributes>.pushToStartToken) == token else { return "dropped:start-token" }
        guard aps["attributes-type"] as? String == "BuzzApprovalsActivityAttributes",
          let origin = (aps["attributes"] as? [String: Any])?["origin"] as? String,
          let state = decode(aps["content-state"])
        else { return "dropped:decode" }
        do {
          _ = try Activity.request(
            attributes: Attributes(origin: origin),
            content: ActivityContent(state: state, staleDate: date("stale-date"), relevanceScore: aps["relevance-score"] as? Double ?? 0),
            pushType: .token)
          return "started"
        } catch {
          return "failed:\(error)"
        }
      }
      guard
        let activity = Activity<Attributes>.activities.first(where: {
          fingerprint($0.pushToken) == token && ($0.activityState == .active || $0.activityState == .stale)
        })
      else { return "dropped:no-live-activity" }
      guard let state = decode(aps["content-state"]) else { return "dropped:decode" }
      let content = ActivityContent(state: state, staleDate: date("stale-date"), relevanceScore: aps["relevance-score"] as? Double ?? 0)
      if event == "update" {
        await activity.update(content)
        return "updated"
      }
      let dismissal = date("dismissal-date") ?? .distantFuture
      await activity.end(content, dismissalPolicy: dismissal <= Date() ? .immediate : .after(dismissal))
      return "ended"
    }
  }
#endif
