# Bl4uzz

Build, sign, upload, and retain Bl4uzz builds on the Apple silicon Mac mini. Deliver all macOS and iPhone builds and updates through Apple TestFlight. Do not use ZIP builds, local installation, or GitHub releases for client delivery. Use GitHub only for source code and rebasing the fork onto upstream. Keep GitHub Actions disabled for `bl4ko/buzz`.

Install build tools with Homebrew and JavaScript packages with `pnpm install --frozen-lockfile` in `desktop/`.

Keep custom changes on fork `main`. Rebase it onto `origin/main` after upstream updates, run the checks, and test the huddle with Hermes. Push the rebased `main` to `bl4ko/buzz` with `--force-with-lease`. Do not change the upstream version files for a custom build.

The desktop changes use the channel member list to include external agents. External agents keep the existing runtime relay hook. The release script inherits `BUZZ_BUILD_RELAY_RECONNECT_CMD` when set.

## Mac TestFlight

Build and upload the desktop app locally:

```sh
node --test scripts/release-bl4ko-macos-testflight.test.mjs
node scripts/release-bl4ko-macos-testflight.mjs <build-number> --upload
```

Increase the numeric build number for each upload. Use a clean, committed checkout. The script stores the signed app, PKG, and source commit in `../buzz-builds/macos-testflight/<upstream-version>/<build>/`. Omit `--upload` only to prepare the signed package before TestFlight upload. Run the same command with `--upload` to upload an existing package from the same source commit.

Mac and iPhone TestFlight builds use the same app `6817066676` (`Bl4uzz`) and bundle ID `com.bl4ko.buzz`, an App Store provisioning profile, and the shared App Store Connect API key. The Mac App Distribution and Mac Installer Distribution keys are in Vault at `envs/external/apple/restricted/signing/mac-app-distribution` and `mac-installer-distribution`. These are different from the Developer ID certificate used for ZIP builds.

The TestFlight configuration enables App Sandbox and disables Tauri private macOS APIs. Child binaries inherit the sandbox. File access is limited to the app container and files selected by the user. Test local agent tools and project access before relying on this build for local development.

After upload, check that Apple reports the build as `VALID`, add it to the existing internal `core` TestFlight group, and check that the group can install it. Keep access to all future builds disabled. Upload success alone does not mean the build is available to testers.

## Signing keys

All paths below use the Vault `kv` mount:

| Path | Fields |
| --- | --- |
| `envs/external/apple/restricted/signing/mac-app-distribution` | `private-key`, `certificate` (DER, base64), `certificate-id` |
| `envs/external/apple/restricted/signing/mac-installer-distribution` | `private-key`, `certificate` (DER, base64), `certificate-id` |
| `envs/external/apple/restricted/api-keys/appstoreconnect` | `key-id`, `issuer-id`, `private-key` |

Keep the bundle ID unchanged across releases. The script uses temporary signing Keychains with random passwords and Apple's WWDR G3 intermediate certificate. The Keychains and temporary private-key files are deleted when the script exits.

## Live relay and mobile

The live relay at `buzz.bl4ko.com` is managed through GitOps. Source changes alone do not deploy it.

Build mobile releases locally. Buzz uses its own iOS App IDs and provisioning profiles. Apple TestFlight delivery is separate from GitHub. See the Buzz skill for the mobile signing and TestFlight procedure.

## Test on the other Mac

Install the current Bl4uzz build through TestFlight, connect to `buzz.bl4ko.com`, and sign in as the channel owner. Open a channel that includes Hermes and start a huddle. Confirm that Hermes joins. Speak, then confirm that Hermes receives the transcript and that you hear the reply. Automated checks cover agent discovery and joining; a live call is still required to check audio.
