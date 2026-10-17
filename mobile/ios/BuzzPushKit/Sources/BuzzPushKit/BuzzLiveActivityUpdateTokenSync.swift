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
      } catch BuzzLiveActivityRegistrationError.invalidOrigin {
        sent[origin] = target
      } catch {
        await sleep(delay)
        delay = min(delay * 2, Self.maximumRetrySeconds)
      }
    }
    draining.remove(origin)
  }
}
