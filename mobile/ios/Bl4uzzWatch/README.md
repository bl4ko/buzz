# Bl4uzz for Apple Watch

The SwiftUI watch app is part of the iPhone app archive. Its bundle ID is `com.bl4ko.buzz.watchkitapp`. It requires watchOS 10 or later.

For independent use, open Bl4uzz on the paired iPhone and sign in to the community. On the watch, tap **Connect without iPhone**, then **Connect**. This step copies the current signing identity to the watch Keychain. After setup, the watch reads and sends through signed HTTPS requests over its own Wi-Fi or cellular connection. The paired iPhone can be unavailable. Cellular use requires a watch with cellular service.

The signing key stays in the watch Keychain with `WhenUnlockedThisDeviceOnly` access. It is not stored in preferences, application context, or logs. **Sign out of watch** removes the saved identity without signing out the iPhone. An account change, iPhone sign-out, or age restriction clears watch sign-in when the watch receives the new iPhone state. A disconnected watch cannot receive that state. To use another community, repeat setup with the iPhone.

The watch shows up to 30 joined stream or DM channels and 20 recent messages. It shows text previews with up to 300 Unicode code points. It applies the same message edits and deletions as the iPhone timeline. Text sends are confirmed only after the relay accepts the message. Failed or uncertain sends keep the draft; check the channel before you send again. Text entered during a pending send stays in the draft after confirmation. Refresh failures keep the current conversation visible. An iPhone with no loaded message history reports its relay connection failure instead of an empty conversation.

The composer appears before message history. Recent messages appear first. **Quick reply** offers four text choices. The open conversation refreshes every 15 seconds while the app is active and has no error. **Refresh** retries a failed read. Sends have a 2000 UTF-16 code-unit limit and are never retried automatically. DM sends include the other members as recipients. Stream mentions must resolve to one channel member.

Before independent setup, a reachable signed-in iPhone handles watch requests with the existing channel, message, and send providers. Open the iPhone app if the watch cannot get a reply. The watch does not support huddles, media uploads, forums, background message updates, or independent push notifications. Drafts stay on the watch, scoped to the community, identity, and channel. Account changes clear the visible channel and message data.

From the repository root:

```sh
xcodebuild -project mobile/ios/Runner.xcodeproj -scheme Bl4uzzWatch -configuration Release -destination 'generic/platform=watchOS' CODE_SIGNING_ALLOWED=NO build
cd mobile
flutter test --no-pub test/shared/watch/watch_bridge_test.dart
flutter analyze --no-pub lib/shared/watch/watch_bridge.dart test/shared/watch/watch_bridge_test.dart
cd ..
uv run --no-project mobile/test/shared/watch/check_standalone.py
cd mobile
swiftc ios/Bl4uzzWatch/WatchDraft.swift test/shared/watch/watch_draft_check.swift -o /tmp/bl4uzz-watch-draft-check
/tmp/bl4uzz-watch-draft-check
rm /tmp/bl4uzz-watch-draft-check
```

Install the watchOS component through Xcode if the build reports a missing watch simulator runtime. Even a device build needs it to compile the watch app icon.

The native relay check uses the production watch relay and shared signer sources in a temporary Swift package. Pass `--secp256k1 /path/to/swift-secp256k1` to use an existing checkout of version `0.21.1` without a download. Run a visible paired setup, independent read and send, failed send, sign-out, and reopening check in an isolated native test instance before TestFlight upload. Automated checks do not replace these steps.

Archive the `Runner` scheme for iOS to ship both platforms in one TestFlight build. Verify `Runner.app/Watch/Bl4uzz.app` is present in the archive. `Watch.xcconfig` reads the Flutter version/build and the same `AppOverrides.xcconfig` as the iPhone. Signing needs an Apple App ID and provisioning profile for the watch bundle ID under team `55S37D9HA7`; it needs no extra capabilities.
