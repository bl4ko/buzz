import Foundation

public actor BuzzLiveActivityGatewaySync {
  public static let initialRetrySeconds: UInt64 = 2
  public static let maximumRetrySeconds: UInt64 = 300
  public static let maximumRegistrationAttempts = 5

  private enum Work: Equatable {
    case registration
    case token(String)
  }

  private enum Outcome {
    case idle
    case done
    case retry
  }

  private struct Target: Equatable {
    let activityID: String?
    let token: Data?
  }

  private struct LiveToken {
    let origin: String
    let token: Data
    let sequence: Int
  }

  private let registerStart: @Sendable (BuzzLiveActivityStartRequest) async throws -> Void
  private let setUpdateToken: @Sendable (String, Data?) async throws -> Void
  private let didRegister: @Sendable (BuzzLiveActivityStartRequest) -> Void
  private let sleep: @Sendable (UInt64) async -> Void
  private let random: @Sendable (ClosedRange<UInt64>) -> UInt64
  private var live: [String: LiveToken] = [:]
  private var ended: Set<String> = []
  private var desired: [String: Target] = [:]
  private var sent: [String: Target] = [:]
  private var registration: BuzzLiveActivityStartRequest?
  private var registrationAttempts = 0
  private var registeredFingerprint: String?
  private var queue: [Work] = []
  private var draining = false
  private var wakeup: BuzzLiveActivityWakeup?
  private var sequence = 0

  public init(
    register: @escaping @Sendable (BuzzLiveActivityStartRequest) async throws -> Void,
    setUpdateToken: @escaping @Sendable (String, Data?) async throws -> Void,
    didRegister: @escaping @Sendable (BuzzLiveActivityStartRequest) -> Void = { _ in },
    sleep: @escaping @Sendable (UInt64) async -> Void = { try? await Task.sleep(nanoseconds: $0) },
    random: @escaping @Sendable (ClosedRange<UInt64>) -> UInt64 = { UInt64.random(in: $0) }
  ) {
    registerStart = register
    self.setUpdateToken = setUpdateToken
    self.didRegister = didRegister
    self.sleep = sleep
    self.random = random
  }

  public func register(_ request: BuzzLiveActivityStartRequest?) {
    let changed = registration?.fingerprint != request?.fingerprint
    if changed { registrationAttempts = 0 }
    registration = request
    guard request != nil else { return }
    enqueue(.registration, wake: changed)
  }

  public func tokenChanged(origin: String, activityID: String, token: Data) {
    guard !ended.contains(activityID) else { return }
    sequence += 1
    live[activityID] = LiveToken(origin: origin, token: token, sequence: sequence)
    want(Target(activityID: activityID, token: token), for: origin)
  }

  public func activityEnded(origin: String, activityID: String) {
    ended.insert(activityID)
    live[activityID] = nil
    guard desired[origin]?.activityID == activityID else { return }
    let next = live.filter { $0.value.origin == origin }.max { $0.value.sequence < $1.value.sequence }
    want(Target(activityID: next?.key, token: next?.value.token), for: origin)
  }

  public func registeredActivities() -> [String: String] {
    desired.compactMapValues { $0.token == nil ? nil : $0.activityID }
  }

  private func want(_ target: Target, for origin: String) {
    let changed = desired[origin] != target
    desired[origin] = target
    enqueue(.token(origin), wake: changed)
  }

  private func enqueue(_ work: Work, wake: Bool) {
    if !queue.contains(work) {
      if work == .registration { queue.insert(work, at: 0) } else { queue.append(work) }
    }
    if wake { wakeup?.fire() }
    guard !draining else { return }
    draining = true
    Task { await drain() }
  }

  private func drain() async {
    var delay = Self.initialRetrySeconds
    while let work = queue.first {
      switch await perform(work) {
      case .idle:
        queue.removeFirst()
      case .done:
        delay = Self.initialRetrySeconds
      case .retry:
        queue.removeAll { $0 == work }
        queue.append(work)
        let nanoseconds = delay * 1_000_000_000
        await pause(random((nanoseconds / 2)...nanoseconds))
        delay = min(delay * 2, Self.maximumRetrySeconds)
      }
    }
    draining = false
  }

  private func perform(_ work: Work) async -> Outcome {
    switch work {
    case .registration:
      guard let request = registration, request.fingerprint != registeredFingerprint else { return .idle }
      registrationAttempts += 1
      do {
        try await registerStart(request)
        registeredFingerprint = request.fingerprint
        didRegister(request)
        return .done
      } catch {
        let final =
          Self.isFinal(error, clearing: false) || registrationAttempts >= Self.maximumRegistrationAttempts
        guard final else { return .retry }
        if registration?.fingerprint == request.fingerprint { registration = nil }
        return .done
      }
    case .token(let origin):
      guard let target = desired[origin], target != sent[origin] else { return .idle }
      do {
        try await setUpdateToken(origin, target.token)
        sent[origin] = target
        return .done
      } catch where Self.isFinal(error, clearing: target.token == nil) {
        sent[origin] = target
        return .done
      } catch {
        return .retry
      }
    }
  }

  private func pause(_ nanoseconds: UInt64) async {
    let wakeup = BuzzLiveActivityWakeup()
    self.wakeup = wakeup
    let sleep = sleep
    let sleeper = Task {
      await sleep(nanoseconds)
      wakeup.fire()
    }
    await wakeup.wait()
    sleeper.cancel()
    self.wakeup = nil
  }

  static func isFinal(_ error: Error, clearing: Bool) -> Bool {
    switch error as? BuzzLiveActivityRegistrationError {
    case .invalidOrigin, .unboundOrigin, .notEnrolled: return true
    case .rejected(status: 404, code: "not_found"?): return clearing
    default: return false
    }
  }
}

final class BuzzLiveActivityWakeup: @unchecked Sendable {
  private let lock = NSLock()
  private var continuation: CheckedContinuation<Void, Never>?
  private var fired = false

  func wait() async {
    await withCheckedContinuation { continuation in
      let resume = locked { () -> Bool in
        guard !fired else { return true }
        self.continuation = continuation
        return false
      }
      if resume { continuation.resume() }
    }
  }

  func fire() {
    let continuation = locked { () -> CheckedContinuation<Void, Never>? in
      fired = true
      defer { self.continuation = nil }
      return self.continuation
    }
    continuation?.resume()
  }

  private func locked<T>(_ body: () -> T) -> T {
    lock.lock()
    defer { lock.unlock() }
    return body()
  }
}
