# Buzz Custom

Build and publish from the Apple silicon Mac mini. Install build tools with Homebrew and JavaScript packages with `pnpm install --frozen-lockfile` in `desktop/`.

Keep `main` equal to upstream. Keep mobile and desktop huddle changes on `feat/ios-agent-huddles`. Rebase this branch onto an upstream release, run the checks, and test a huddle with Hermes before publishing. Do not change the upstream version files for a custom release.

The desktop changes use the channel member list to include external agents. External agents keep their existing runtime and relay hook. The release script inherits `BUZZ_BUILD_RELAY_RECONNECT_CMD` when it is set.

## Release

Use a clean, committed checkout and a valid `mac-mini-temp` Vault AppRole token. The version must use the current upstream desktop version plus `-bl4ko.N`. Increase `N` for each custom release of that upstream version.

```sh
node --test scripts/release-bl4ko-desktop.test.mjs
node scripts/release-bl4ko-desktop.mjs 0.5.25-bl4ko.1
```

The script runs the desktop checks, builds the app and its sidecars, signs all executables, submits the app to Apple for notarization, and attaches Apple's ticket. It creates a ZIP for installation and a signed archive for Buzz's existing updater.

Push the commit to `bl4ko/buzz`, then add `--publish` to build and publish a release. Publication uses the release bot. Enable `buzz` in the bot's [installation settings](https://github.com/settings/installations/120143384) first. The script publishes versioned assets before it updates `buzz-custom-desktop-latest/latest.json`. It rejects an equal or older update version.

The app is `Buzz Custom`, with bundle ID `xyz.bl4ko.buzz.custom`. Update files come from `bl4ko/buzz`. The first signed build needs a manual install because the earlier test build has no updater.

## Signing keys

All paths below use the Vault `kv` mount:

| Path | Fields |
| --- | --- |
| `envs/external/apple/restricted/signing/developer-id-application` | `private-key`, `certificate` (DER, base64) |
| `envs/external/tauri/restricted/signing/buzz` | `private-key`, `public-key` |
| `envs/external/apple/restricted/api-keys/appstoreconnect` | `key-id`, `issuer-id`, `private-key` |
| `envs/external/github/bl4ko/restricted/apps/bl4ko-release-bot` | `github_app_id`, `github_app_private_key` |

Keep the updater key and bundle ID unchanged across releases. The script imports the Developer ID identity into the Mac mini's login Keychain. Temporary private-key files are deleted when the script exits.

Apple requires the Account Holder to create a Developer ID certificate. Open [Apple Certificates](https://developer.apple.com/account/resources/certificates/add), choose **Developer ID Application**, select **G2** if asked, and upload the prepared [buzz-developer-id.csr](https://gist.github.com/bl4ko/ad419801532684664001b34026f55a56). The private key is already in Vault. Retrieve the issued certificate through the Apple API, check that its public key matches the stored private key, and add its base64 DER content to the same Vault secret.

## Test on the other Mac

Install the ZIP, open Buzz Custom, connect to `buzz.bl4ko.com`, and sign in as the channel owner. Open a channel that includes Hermes and start a huddle. Confirm that Hermes joins. Speak, then confirm that Hermes receives the transcript and that you hear the reply. Automated checks cover agent discovery and joining; a live call is still required to check audio.

The mobile app and the desktop app use this same source branch. The mobile app keeps its own app ID and TestFlight build. The desktop app needs its own Developer ID signing and download.
