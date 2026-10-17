import Foundation

enum WatchAvatar {
  static let paletteCount = 6

  static func initials(for name: String) -> String {
    let words = name.split { !$0.isLetter && !$0.isNumber }
    let letters = words.prefix(words.count > 1 ? 2 : 1).compactMap(\.first)
    return letters.isEmpty ? "?" : String(letters).uppercased()
  }

  static func colorIndex(for name: String) -> Int {
    var hash: UInt32 = 2_166_136_261
    for byte in name.lowercased().utf8 {
      hash = (hash ^ UInt32(byte)) &* 16_777_619
    }
    return Int(hash % UInt32(paletteCount))
  }
}

enum WatchTime {
  static func label(
    createdAt: Int, now: Date = Date(), calendar: Calendar = .current, locale: Locale = .current
  ) -> String {
    let age = Int(now.timeIntervalSince1970) - createdAt
    if age < 60 { return "now" }
    if age < 3600 { return "\(age / 60)m" }
    if age < 86_400 { return "\(age / 3600)h" }
    let formatter = DateFormatter()
    formatter.calendar = calendar
    formatter.timeZone = calendar.timeZone
    formatter.locale = locale
    formatter.setLocalizedDateFormatFromTemplate(age < 7 * 86_400 ? "EEE" : "dMMM")
    return formatter.string(from: Date(timeIntervalSince1970: TimeInterval(createdAt)))
  }
}

enum WatchUnread {
  static func newMessageIDs(_ ids: [String], lastSeen: String?, excluding: Set<String> = []) -> Set<String> {
    guard let lastSeen, let index = ids.lastIndex(of: lastSeen) else { return [] }
    return Set(ids[(index + 1)...]).subtracting(excluding)
  }
}

enum WatchKeys {
  static func draft(scope: String, channelID: String) -> String { "Bl4uzz.draft.\(scope).\(channelID)" }
  static func seen(scope: String, channelID: String) -> String { "Bl4uzz.seen.\(scope).\(channelID)" }
}

enum WatchComposer {
  static let quickReplies = ["Yes", "No", "Thanks", "I will check."]

  static func isTooLong(_ draft: String) -> Bool { draft.utf16.count > 2000 }

  static func canSend(draft: String, busy: Bool, independent: Bool, reachable: Bool) -> Bool {
    !busy && (independent || reachable)
      && !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isTooLong(draft)
  }
}

enum WatchConnection: Equatable {
  case direct, phone, unreachable
}

struct WatchHome: Equatable {
  let showsWelcome: Bool
  let showsConnect: Bool
  let showsRefresh: Bool
  let showsLoading: Bool
  let showsEmpty: Bool
  let canConnect: Bool
  let connection: WatchConnection

  init(independent: Bool, synced: Bool, reachable: Bool, busy: Bool, hasError: Bool, channelsEmpty: Bool) {
    showsWelcome = !independent && !synced
    showsConnect = !independent && !synced
    showsRefresh = !synced || hasError
    showsLoading = busy && channelsEmpty
    showsEmpty = synced && (reachable || independent) && channelsEmpty && !busy && !hasError
    canConnect = !busy && reachable
    connection = independent ? .direct : reachable ? .phone : .unreachable
  }
}
