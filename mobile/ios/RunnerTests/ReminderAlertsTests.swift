import BuzzPushKit
import UserNotifications
import XCTest

@testable import Buzz

final class ReminderAlertsTests: XCTestCase {
  private let fireAt = Date().addingTimeInterval(3600).timeIntervalSince1970.rounded(.down)

  func testRequestSchedulesAtFireTimeAndRoutesLikeAPushTap() throws {
    let request = try XCTUnwrap(
      ReminderAlerts.request(from: [
        "id": "r1",
        "fireAt": NSNumber(value: Int(fireAt)),
        "title": "Reminder",
        "body": "Ana: Ship the build",
        "communityId": "community-id",
        "channelId": "channel-id",
        "messageId": "message-id",
      ])
    )

    XCTAssertEqual(request.identifier, "buzz.reminder.r1")
    XCTAssertEqual(request.content.title, "Reminder")
    XCTAssertEqual(request.content.body, "Ana: Ship the build")
    XCTAssertEqual(request.content.sound, .default)
    let trigger = try XCTUnwrap(request.trigger as? UNCalendarNotificationTrigger)
    XCTAssertFalse(trigger.repeats)
    XCTAssertEqual(trigger.nextTriggerDate(), Date(timeIntervalSince1970: fireAt))

    var routed: [BuzzPushNavigationTarget] = []
    BuzzPushNotificationResponseCoordinator.handle(
      actionIdentifier: UNNotificationDefaultActionIdentifier,
      userInfo: request.content.userInfo,
      onTarget: { routed.append($0) },
      forwardToFlutter: { $0() },
      completion: {}
    )
    XCTAssertEqual(
      routed,
      [
        BuzzPushNavigationTarget(
          eventID: "message-id",
          communityID: "community-id",
          channelID: "channel-id"
        )
      ]
    )
  }

  func testNoteOnlyReminderHasNoNavigationTarget() throws {
    let request = try XCTUnwrap(
      ReminderAlerts.request(from: [
        "id": "r2",
        "fireAt": fireAt,
        "title": "Reminder",
        "body": "Water plants",
        "communityId": "community-id",
        "channelId": NSNull(),
        "messageId": NSNull(),
      ])
    )

    XCTAssertTrue(request.content.userInfo.isEmpty)
  }

  func testMalformedAlertIsSkipped() {
    XCTAssertNil(ReminderAlerts.request(from: ["id": "", "fireAt": fireAt, "title": "", "body": ""]))
    XCTAssertNil(ReminderAlerts.request(from: ["id": "r3", "title": "Reminder", "body": "x"]))
  }
}
