import Foundation

public final class BuzzPushPresentedEventStore: @unchecked Sendable {
  public static let fileName = "push-presented-events.json"
  public static let maximumEventIDs = 200
  static let maximumFileBytes = 64 * 1024
  private static let lock = NSLock()

  private let fileURL: URL

  public init(containerURL: URL) {
    fileURL = containerURL.appendingPathComponent(Self.fileName)
  }

  public convenience init?(appGroupIdentifier: String?) {
    guard let appGroupIdentifier,
      let container = FileManager.default.containerURL(
        forSecurityApplicationGroupIdentifier: appGroupIdentifier
      )
    else { return nil }
    self.init(containerURL: container)
  }

  public func claim(_ orderedEventIDs: [String]) -> String? {
    Self.lock.lock()
    defer { Self.lock.unlock() }
    var presented = load()
    guard let claimed = orderedEventIDs.first(where: { !presented.contains($0) }) else {
      return nil
    }
    presented.append(claimed)
    save(Array(presented.suffix(Self.maximumEventIDs)))
    return claimed
  }

  private func load() -> [String] {
    guard let values = try? fileURL.resourceValues(forKeys: [.fileSizeKey]),
      let size = values.fileSize, size <= Self.maximumFileBytes,
      let data = try? Data(contentsOf: fileURL),
      let ids = try? JSONDecoder().decode([String].self, from: data)
    else { return [] }
    return ids
  }

  private func save(_ ids: [String]) {
    guard let data = try? JSONEncoder().encode(ids) else { return }
    try? data.write(to: fileURL, options: [.atomic])
    #if os(iOS)
      try? FileManager.default.setAttributes(
        [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
        ofItemAtPath: fileURL.path
      )
    #endif
  }
}
