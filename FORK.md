# Buzz Custom

Build, sign, install, and retain Buzz builds on the Apple silicon Mac mini. Use GitHub only for source code and rebasing the fork onto upstream. Keep GitHub Actions disabled for `bl4ko/buzz`.

Install build tools with Homebrew and JavaScript packages with `pnpm install --frozen-lockfile` in `desktop/`.

Keep custom changes on fork `main`. Rebase it onto `origin/main` after upstream updates, run the checks, and test the huddle with Hermes. Push the rebased `main` to `bl4ko/buzz` with `--force-with-lease`. Do not change the upstream version files for a custom build.

The desktop changes use the channel member list to include external agents. External agents keep the existing runtime relay hook. The release script inherits `BUZZ_BUILD_RELAY_RECONNECT_CMD` when set.

## Local release

Use a clean, committed checkout and a valid `mac-mini-temp` Vault AppRole token. The version must use the current upstream desktop version plus `-bl4ko.N`. Increase `N` for each local build of that upstream version.

```sh
node --test scripts/release-bl4ko-desktop.test.mjs
node scripts/release-bl4ko-desktop.mjs 0.5.25-bl4ko.3
```

The script runs the desktop checks, builds the app and its sidecars, signs all executables, and checks the signatures. It stores the app, installation ZIP, and source commit in `../buzz-builds/desktop/<version>/`. It rejects an existing version folder. Install the app after the script prints `Ready for local use`.

For distribution to other Macs, add `--notarize` to the build command. The script submits the app to Apple and attaches Apple's ticket when processing is complete. If processing is pending, it saves the submission ID in `notarization.json`. Check that build again without rebuilding:

```sh
node scripts/release-bl4ko-desktop.mjs 0.5.25-bl4ko.2 --resume
```

Local use does not require Apple notarization. For a notarized distribution build, wait until the script prints `Ready` and the Apple ticket and Gatekeeper checks pass.

The app is `Buzz Custom`, with bundle ID `xyz.bl4ko.buzz.custom`. It has no automatic updater. Install each new local build manually. The script has no GitHub publication option and needs no release bot or updater key.

## Mac TestFlight

Build and upload the desktop app locally:

```sh
node --test scripts/release-bl4ko-macos-testflight.test.mjs
node scripts/release-bl4ko-macos-testflight.mjs 4 --upload
```

Increase the numeric build number for each upload. Use a clean, committed checkout. The script stores the signed app, PKG, and source commit in `../buzz-builds/macos-testflight/<upstream-version>/<build>/`. Omit `--upload` to prepare the signed package first. Run the same command with `--upload` to upload an existing package from the same source commit.

Mac TestFlight uses app `6818075298` (`Buzz Desktop`), bundle ID `xyz.bl4ko.buzz.custom`, an App Store provisioning profile, and the shared App Store Connect API key. The Mac App Distribution and Mac Installer Distribution keys are in Vault at `envs/external/apple/restricted/signing/mac-app-distribution` and `mac-installer-distribution`. These are different from the Developer ID certificate used for ZIP builds.

The TestFlight configuration enables App Sandbox and disables Tauri private macOS APIs. Child binaries inherit the sandbox. File access is limited to the app container and files selected by the user. Test local agent tools and project access before relying on this build for local development. The direct ZIP build keeps its existing configuration.

After upload, check that Apple reports the build as `VALID`, add it to an internal TestFlight group, and check that the group can install it. Upload success alone does not mean the build is available to testers.

## Signing keys

All paths below use the Vault `kv` mount:

| Path | Fields |
| --- | --- |
| `envs/external/apple/restricted/signing/developer-id-application` | `private-key`, `certificate` (DER, base64) |
| `envs/external/apple/restricted/api-keys/appstoreconnect` | `key-id`, `issuer-id`, `private-key` |

Keep the bundle ID unchanged across releases. The script uses a temporary signing Keychain with a random password and Apple's G2 intermediate certificate. The Keychain and temporary private-key files are deleted when the script exits.

Apple requires the Account Holder to create a Developer ID Application certificate. Use the G2 certificate authority and a CSR for the private key stored in Vault. Store the issued DER certificate as base64 in the same Vault secret after checking that it matches the private key.

## Live relay and mobile

The live relay at `buzz.bl4ko.com` is managed through GitOps. Source changes alone do not deploy it.

Build mobile releases locally. Buzz uses its own iOS App IDs and provisioning profiles. Apple TestFlight delivery is separate from GitHub. See the Buzz skill for the mobile signing and TestFlight procedure.

## Test on the other Mac

Install the ZIP, open Buzz Custom, connect to `buzz.bl4ko.com`, and sign in as the channel owner. Open a channel that includes Hermes and start a huddle. Confirm that Hermes joins. Speak, then confirm that Hermes receives the transcript and that you hear the reply. Automated checks cover agent discovery and joining; a live call is still required to check audio.
