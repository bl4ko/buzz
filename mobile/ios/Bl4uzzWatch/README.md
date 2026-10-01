# Bl4uzz for Apple Watch

The SwiftUI companion is part of the iPhone app archive. Its bundle ID is `com.bl4ko.buzz.watchkitapp`. The iPhone keeps the identity key and uses the existing channel, message, and send providers for each watch request.

The watch shows up to 30 joined stream or DM channels and 20 recent messages. It shows text previews with up to 300 Unicode code points. It applies the same message edits and deletions as the iPhone timeline. Text sends are confirmed only after the relay accepts the message. Failed or uncertain sends keep the draft; check the channel before you send again. Text entered during a pending send stays in the draft after confirmation. Refresh failures keep the current conversation visible. An iPhone with no loaded message history reports its relay connection failure instead of an empty conversation.

The watch requires watchOS 10 or later and a reachable paired iPhone with Bl4uzz signed in. Open the iPhone app if the watch cannot get a reply. The watch does not support huddles, media uploads, forums, or direct relay connections. Drafts stay on the watch, scoped to the community, identity, and channel. Account changes clear the visible channel and message data.

From the repository root:

```sh
xcodebuild -project mobile/ios/Runner.xcodeproj -scheme Bl4uzzWatch -configuration Release -destination 'generic/platform=watchOS' CODE_SIGNING_ALLOWED=NO build
cd mobile
flutter test --no-pub test/shared/watch/watch_bridge_test.dart
flutter analyze --no-pub lib/shared/watch/watch_bridge.dart test/shared/watch/watch_bridge_test.dart
swiftc ios/Bl4uzzWatch/WatchDraft.swift test/shared/watch/watch_draft_check.swift -o /tmp/bl4uzz-watch-draft-check
/tmp/bl4uzz-watch-draft-check
rm /tmp/bl4uzz-watch-draft-check
```

Install the watchOS component through Xcode if the build reports a missing watch simulator runtime. Even a device build needs it to compile the watch app icon.

Archive the `Runner` scheme for iOS to ship both platforms in one TestFlight build. Verify `Runner.app/Watch/Bl4uzz.app` is present in the archive. `Watch.xcconfig` reads the Flutter version/build and the same `AppOverrides.xcconfig` as the iPhone. Signing needs an Apple App ID and provisioning profile for the watch bundle ID under team `55S37D9HA7`; it needs no extra capabilities.
