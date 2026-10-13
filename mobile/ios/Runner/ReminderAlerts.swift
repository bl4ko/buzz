import BuzzPushKit
import Flutter
import UserNotifications

final class ReminderAlerts {
  static let identifierPrefix = "buzz.reminder."

  private let channel: FlutterMethodChannel
  private let center = UNUserNotificationCenter.current()
  private var generation = 0
  private var scheduled = Set<String>()

  init(messenger: FlutterBinaryMessenger) {
    channel = FlutterMethodChannel(name: "buzz/reminder_alerts", binaryMessenger: messenger)
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self else {
        result(FlutterMethodNotImplemented)
        return
      }
      switch call.method {
      case "sync":
        guard let alerts = call.arguments as? [[String: Any]] else {
          result(
            FlutterError(code: "invalid_arguments", message: "Expected a reminder list.", details: nil)
          )
          return
        }
        self.replace(with: alerts.compactMap(Self.request(from:)), removeDelivered: false)
        result(nil)
      case "clear":
        self.replace(with: [], removeDelivered: true)
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  static func isReminder(_ notification: UNNotification) -> Bool {
    notification.request.identifier.hasPrefix(identifierPrefix)
  }

  static func request(from alert: [String: Any]) -> UNNotificationRequest? {
    guard let id = alert["id"] as? String, !id.isEmpty,
      let fireAt = (alert["fireAt"] as? NSNumber)?.doubleValue,
      let title = alert["title"] as? String,
      let body = alert["body"] as? String
    else { return nil }
    let content = UNMutableNotificationContent()
    content.title = title
    content.body = body
    content.sound = .default
    if let communityID = alert["communityId"] as? String, !communityID.isEmpty,
      let channelID = alert["channelId"] as? String, !channelID.isEmpty,
      let eventID = alert["messageId"] as? String, !eventID.isEmpty
    {
      content.userInfo = [
        BuzzPushNavigationTarget.userInfoKey: BuzzPushNavigationTarget(
          eventID: eventID,
          communityID: communityID,
          channelID: channelID
        ).userInfoValue
      ]
    }
    let components = Calendar.current.dateComponents(
      [.timeZone, .year, .month, .day, .hour, .minute, .second],
      from: Date(timeIntervalSince1970: fireAt)
    )
    return UNNotificationRequest(
      identifier: identifierPrefix + id,
      content: content,
      trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
    )
  }

  private func replace(with requests: [UNNotificationRequest], removeDelivered: Bool) {
    generation += 1
    let current = generation
    center.getNotificationSettings { settings in
      self.center.getPendingNotificationRequests { pending in
        DispatchQueue.main.async {
          guard current == self.generation else { return }
          let allowed = [.authorized, .provisional, .ephemeral].contains(settings.authorizationStatus)
          let keep = allowed ? Set(requests.map(\.identifier)) : []
          let stale = Set(pending.map(\.identifier).filter { $0.hasPrefix(Self.identifierPrefix) })
            .union(self.scheduled)
            .subtracting(keep)
          self.center.removePendingNotificationRequests(withIdentifiers: Array(stale))
          self.scheduled = keep
          if allowed {
            for request in requests {
              self.center.add(request) { error in
                if let error {
                  NSLog("Bl4uzz reminder alert scheduling failed: %@", error.localizedDescription)
                }
              }
            }
          }
          if removeDelivered { self.removeDeliveredAlerts() }
        }
      }
    }
  }

  private func removeDeliveredAlerts() {
    center.getDeliveredNotifications { delivered in
      let identifiers = delivered.filter(Self.isReminder).map(\.request.identifier)
      guard !identifiers.isEmpty else { return }
      self.center.removeDeliveredNotifications(withIdentifiers: identifiers)
    }
  }
}
