import Foundation

public actor BuzzLiveActivityUpdateTokenSync {
  public static let initialRetrySeconds: UInt64 = 2
  public static let maximumRetrySeconds: UInt64 = 300

  private struct Target: Equatable {
    let activityID: String?
    let token: Data?
  }

  private struct LiveToken {
    let origin: String
    let token: Data
    let sequence: Int
  }

  private let send: @Sendable (String, Data?) async throws -> Void
  private let sleep: @Sendable (UInt64) async -> Void
  private var live: [String: LiveToken] = [:]
  private var ended: Set<String> = []
  private var desired: [String: Target] = [:]
  private var sent: [String: Target] = [:]
  private var draining: Set<String> = []
  private var wakeups: [String: BuzzLiveActivityWakeup] = [:]
  private var sequence = 0

  public init(
    send: @escaping @Sendable (String, Data?) async throws -> Void,
    sleep: @escaping @Sendable (UInt64) async -> Void = { try? await Task.sleep(nanoseconds: $0 * 1_000_000_000) }
  ) {
    self.send = send
    self.sleep = sleep
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
    desired[origin] = target
    wakeups[origin]?.fire()
    guard draining.insert(origin).inserted else { return }
    Task { await drain(origin) }
  }

  private func drain(_ origin: String) async {
    var delay = Self.initialRetrySeconds
    while let target = desired[origin], target != sent[origin] {
      do {
        try await send(origin, target.token)
        sent[origin] = target
        delay = Self.initialRetrySeconds
      } catch where Self.isFinal(error, clearing: target.token == nil) {
        sent[origin] = target
      } catch {
        await pause(origin, seconds: delay)
        delay = min(delay * 2, Self.maximumRetrySeconds)
      }
    }
    draining.remove(origin)
  }

  private func pause(_ origin: String, seconds: UInt64) async {
    let wakeup = BuzzLiveActivityWakeup()
    wakeups[origin] = wakeup
    let sleep = sleep
    let sleeper = Task {
      await sleep(seconds)
      wakeup.fire()
    }
    await wakeup.wait()
    sleeper.cancel()
    wakeups[origin] = nil
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
