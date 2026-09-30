# Buzz Custom

Build, sign, install, and retain Buzz builds on the Apple silicon Mac mini. Use GitHub only for source code and rebasing the fork onto upstream. Keep GitHub Actions disabled for `bl4ko/buzz`.

Install build tools with Homebrew and JavaScript packages with `pnpm install --frozen-lockfile` in `desktop/`.

Keep custom changes on fork `main`. Rebase it onto `origin/main` after upstream updates, run the checks, and test the huddle with Hermes. Push the rebased `main` to `bl4ko/buzz` with `--force-with-lease`. Do not change the upstream version files for a custom build.

The desktop changes use the channel member list to include external agents. External agents keep the existing runtime relay hook. The release script inherits `BUZZ_BUILD_RELAY_RECONNECT_CMD` when set.

## Local release

Use a clean, committed checkout and a valid `mac-mini-temp` Vault AppRole token. The version must use the current upstream desktop version plus `-bl4ko.N`. Increase `N` for each local build of that upstream version.

```sh
node --test scripts/release-bl4ko-desktop.test.mjs
node scripts/release-bl4ko-desktop.mjs 0.5.25-bl4ko.2
```

The script runs the desktop checks, builds the app and its sidecars, signs all executables, submits the app to Apple for notarization, and attaches Apple's ticket. It stores the app, installation ZIP, and source commit in `../buzz-builds/desktop/<version>/`. It rejects an existing version folder.

If Apple is still processing, the script saves the submission ID in `notarization.json`. Check the same build again without rebuilding:

```sh
node scripts/release-bl4ko-desktop.mjs 0.5.25-bl4ko.2 --resume
```

Install the app after the script prints `Ready` and the Apple ticket and Gatekeeper checks pass.

The app is `Buzz Custom`, with bundle ID `xyz.bl4ko.buzz.custom`. It has no automatic updater. Install each new local build manually. The script has no GitHub publication option and needs no release bot or updater key.

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
