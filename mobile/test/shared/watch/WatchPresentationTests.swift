import Foundation
import XCTest
@testable import WatchCheck

final class WatchPresentationTests: XCTestCase {
  func testInitialsUseTheFirstTwoWords() {
    XCTAssertEqual(WatchAvatar.initials(for: "Mia Novak"), "MN")
    XCTAssertEqual(WatchAvatar.initials(for: "zeus"), "Z")
    XCTAssertEqual(WatchAvatar.initials(for: "  Alex   de Rivera "), "AD")
    XCTAssertEqual(WatchAvatar.initials(for: "Mia Novak, Zeus"), "MN")
    XCTAssertEqual(WatchAvatar.initials(for: "40d34674"), "4")
    XCTAssertEqual(WatchAvatar.initials(for: "élodie"), "É")
    XCTAssertEqual(WatchAvatar.initials(for: ""), "?")
    XCTAssertEqual(WatchAvatar.initials(for: " , "), "?")
  }

  func testAvatarColorIsStableAndInRange() {
    let names = ["Mia Novak", "Zeus", "Argus", "Hermes", "Alex Rivera", "40d34674", ""]
    for name in names {
      let index = WatchAvatar.colorIndex(for: name)
      XCTAssertTrue((0..<WatchAvatar.paletteCount).contains(index))
      XCTAssertEqual(index, WatchAvatar.colorIndex(for: name))
      XCTAssertEqual(index, WatchAvatar.colorIndex(for: name.uppercased()))
    }
    XCTAssertEqual(WatchAvatar.colorIndex(for: "Zeus"), 0)
    XCTAssertEqual(WatchAvatar.colorIndex(for: "Argus"), 5)
    XCTAssertGreaterThan(Set(names.map(WatchAvatar.colorIndex(for:))).count, 2)
  }

  func testRelativeTimeLabels() {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    let locale = Locale(identifier: "en_US_POSIX")
    let now = Date(timeIntervalSince1970: 1_792_231_800)
    let at = { (ago: Int) in WatchTime.label(createdAt: Int(now.timeIntervalSince1970) - ago, now: now, calendar: calendar, locale: locale) }
    XCTAssertEqual(at(0), "now")
    XCTAssertEqual(at(59), "now")
    XCTAssertEqual(at(-120), "now")
    XCTAssertEqual(at(60), "1m")
    XCTAssertEqual(at(3599), "59m")
    XCTAssertEqual(at(3600), "1h")
    XCTAssertEqual(at(86_399), "23h")
    XCTAssertEqual(at(86_400), "Fri")
    XCTAssertEqual(at(6 * 86_400), "Sun")
    XCTAssertEqual(at(7 * 86_400), "Oct 10")
  }

  func testNewMessagesFollowTheLastSeenMessage() {
    let ids = ["a", "b", "c", "d"]
    XCTAssertEqual(WatchUnread.newMessageIDs(ids, lastSeen: "b"), ["c", "d"])
    XCTAssertEqual(WatchUnread.newMessageIDs(ids, lastSeen: "d"), [])
    XCTAssertEqual(WatchUnread.newMessageIDs(ids, lastSeen: nil), [])
    XCTAssertEqual(WatchUnread.newMessageIDs(ids, lastSeen: "gone"), [])
    XCTAssertEqual(WatchUnread.newMessageIDs([], lastSeen: "a"), [])
    XCTAssertEqual(WatchUnread.newMessageIDs(ids, lastSeen: "b", excluding: ["d"]), ["c"])
  }

  func testStorageKeysKeepTheExistingDraftFormat() {
    XCTAssertEqual(WatchKeys.draft(scope: "community:abc", channelID: "c1"), "Bl4uzz.draft.community:abc.c1")
    XCTAssertEqual(WatchKeys.seen(scope: "community:abc", channelID: "c1"), "Bl4uzz.seen.community:abc.c1")
  }

  func testComposerSendRules() {
    XCTAssertTrue(WatchComposer.canSend(draft: "Thanks", busy: false, independent: true, reachable: false))
    XCTAssertTrue(WatchComposer.canSend(draft: "Thanks", busy: false, independent: false, reachable: true))
    XCTAssertFalse(WatchComposer.canSend(draft: "Thanks", busy: false, independent: false, reachable: false))
    XCTAssertFalse(WatchComposer.canSend(draft: "Thanks", busy: true, independent: true, reachable: true))
    XCTAssertFalse(WatchComposer.canSend(draft: " \n ", busy: false, independent: true, reachable: true))
    XCTAssertTrue(WatchComposer.canSend(draft: String(repeating: "a", count: 2000), busy: false, independent: true, reachable: true))
    XCTAssertFalse(WatchComposer.canSend(draft: String(repeating: "🐝", count: 1001), busy: false, independent: true, reachable: true))
    XCTAssertTrue(WatchComposer.isTooLong(String(repeating: "🐝", count: 1001)))
    XCTAssertFalse(WatchComposer.isTooLong(String(repeating: "🐝", count: 1000)))
    XCTAssertEqual(WatchComposer.quickReplies, ["Yes", "No", "Thanks", "I will check."])
  }

  func testHomeHidesSetupControlsAfterSync() {
    let setup = WatchHome(independent: false, synced: false, reachable: true, busy: false, hasError: false, channelsEmpty: true)
    XCTAssertTrue(setup.showsWelcome)
    XCTAssertTrue(setup.showsConnect)
    XCTAssertTrue(setup.showsRefresh)
    XCTAssertTrue(setup.canConnect)
    XCTAssertFalse(setup.showsEmpty)
    XCTAssertEqual(setup.connection, .phone)

    let synced = WatchHome(independent: false, synced: true, reachable: true, busy: false, hasError: false, channelsEmpty: false)
    XCTAssertFalse(synced.showsWelcome)
    XCTAssertFalse(synced.showsConnect)
    XCTAssertFalse(synced.showsRefresh)
    XCTAssertFalse(synced.showsEmpty)

    let failed = WatchHome(independent: false, synced: true, reachable: true, busy: false, hasError: true, channelsEmpty: false)
    XCTAssertTrue(failed.showsRefresh)
    XCTAssertFalse(failed.showsConnect)

    let empty = WatchHome(independent: true, synced: true, reachable: false, busy: false, hasError: false, channelsEmpty: true)
    XCTAssertTrue(empty.showsEmpty)
    XCTAssertEqual(empty.connection, .direct)

    let loading = WatchHome(independent: true, synced: false, reachable: false, busy: true, hasError: false, channelsEmpty: true)
    XCTAssertFalse(loading.showsConnect)
    XCTAssertFalse(loading.showsWelcome)
    XCTAssertTrue(loading.showsRefresh)
    XCTAssertTrue(loading.showsLoading)
    XCTAssertFalse(loading.showsEmpty)

    let away = WatchHome(independent: false, synced: false, reachable: false, busy: false, hasError: false, channelsEmpty: true)
    XCTAssertEqual(away.connection, .unreachable)
    XCTAssertFalse(away.canConnect)
    XCTAssertFalse(WatchHome(independent: false, synced: false, reachable: true, busy: true, hasError: false, channelsEmpty: true).canConnect)
  }
}
