# Bl4uzz

Build, sign, upload, and retain Bl4uzz builds on the Apple silicon Mac mini. Deliver all macOS and iPhone builds and updates through Apple TestFlight. Do not use ZIP builds, local installation, or GitHub releases for client delivery. Use GitHub only for source code and rebasing the fork onto upstream. Keep GitHub Actions disabled for `bl4ko/buzz`.

Install build tools with Homebrew and JavaScript packages with `pnpm install --frozen-lockfile` in `desktop/`.

Keep custom changes on fork `main`. Rebase it onto `origin/main` after upstream updates, run the checks, and test the huddle with Hermes. Push the rebased `main` to `bl4ko/buzz` with `--force-with-lease`. Do not change the upstream version files for a custom build.

The desktop changes use the channel member list to include external agents. External agents keep the existing runtime relay hook. The release script inherits `BUZZ_BUILD_RELAY_RECONNECT_CMD` when set.

The relay accepts the Olympus agent kinds 30190 to 30193 and 44311 only from keys in `BUZZ_OLYMPUS_OPERATOR_PUBKEYS`, and 44310 only from the relay owner. It gives them only to readers in their `p` tags ([NIP-OL](docs/nips/NIP-OL.md)).

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

## Olympus branding

The visible brand is Olympus. Keep these overrides when you rebase onto upstream:

- Icons come from `branding/olympus/` (G3 SVGs; `g3-small.svg` below 64 px; `g3-seal.svg`, the seal without the bolt, for the launch image); regenerate all app, launch, and tray assets with `branding/olympus/export.sh`.
- Mobile: the welcome bee files (`website_bee_*.dart`, `website_welcome_background.dart`) and `flapping_bee.dart` are deleted. `onboarding_wordmark.dart`, `onboarding_background.dart`, `buzz_loading_indicator.dart`, `bee_loading_mark.dart`, and `bee_refresh_indicator.dart` are rewritten on `lib/shared/olympus/`. `BuzzLoadingIndicator` picks the key-tile loader or the inline key tiles by size, so call sites stay upstream. `pairing_welcome_view.dart` wraps the wordmark, tagline, and actions for the intro (`OlympusIntro`).
- Desktop: `LandingBees.tsx` is deleted. `spinner.tsx`, `BuzzLoadingState.tsx`, and the loading gates in `App.tsx` use `src/shared/ui/olympus/`. The tray icon is in `tray_icon_olympus.rs`. The first-paint mark is `public/boot.css` with `public/olympus-boot-{dark,light}.svg`.
- Keep upstream bee assets that are now unused (`FlappingBee.tsx`, `FuzzyLogo.tsx`, `BuzzLogoAnimation.tsx`, the bee and wordmark assets in `pubspec.yaml`, `tray_bee_icon`) to avoid modify/delete conflicts.
- Community name: the relay sets its NIP-11 `name` from `BUZZ_RELAY_NAME` (live: `Olympus`). Desktop renames a community to that name while its local name is still the one derived from the relay host (`relayCommunityName.ts`).
- Desktop visible strings: tray `Open Olympus` and `Quit Olympus`, the notification fallback text, and the mobile pairing hint.
- Visible name sweep: user-visible "Buzz" text says Olympus in place (desktop UI, window title, `Info.plist`, power assertion, harness catalog hints; mobile UI, iOS permission prompts, debug display name, push fallback). Internal names, the bundle file `Bl4uzz.app`, `productName`, "Buzz shared compute", and "Buzz event" stay.
- `desktop/src/shared/constants/olympus.ts` hides Block hosted communities (settings section, hosted create and owner sign-in) and the Welcome team (no Fizz, Honey, and Pollen provisioning, no Fizz composer banner). The bee personas seed inactive; `personas.rs` deactivates them once on existing installs (`.olympus-built-in-personas-hidden` marker) and keeps their records.

## Agent harness replies

`buzz-acp` tells the agent to answer a top-level direct message in the main conversation (no `--reply-to`); a DM thread reply stays in its thread. At shutdown it waits up to 5 s for the 👀 and 💬 removals of finished turns.

## Quiet joins

Desktop join alerts skip keys whose kind 0 marks an agent: a NIP-OA owner tag or NIP-24 `"bot": true` (`personJoinAlerts`). The Hephaestus operator sets `bot` on agent, scheduler, and mirror profiles.

## Notification levels

Each channel has a level: All new messages, Mentions and DMs, or Nothing. The level is the `level` field of the channel entry in the synced encrypted channel-mutes blob (kind 30078, `d` `channel-mutes`); `muted: true` is Nothing, so older clients stay quiet. Without a level, a DM is All, a channel with a NIP-24 `bot: true` member is Mentions and DMs, and other channels are All, but top-level posts by `bot: true` keys stay quiet there. Mentions, DMs, approval requests (`notification` `approval`), and thread replies alert unless the level is Nothing; Nothing also silences mentions. Desktop: "Notify me about" in the channel menu and Settings > Notifications > Channels; the level gates dock bounce, DM, and mention alerts, not unread state. iPhone: "Notify me about" in the channel actions and details; the push lease leaves Mentions and DMs channels out of the channel subscriptions and ignores bot authors in default channels. The relay accepts every canonical UUID channel id in a lease (`h_grammar` `uuid-lowercase`).

## Master agent quick access

Desktop reads the kind 30190 state events and takes the agent with top-level `"role": "master"` (operator v1.17.0+); its kind 0 gives the name and picture. With no master, every entry point is hidden. Entry points (`src/features/master-agent/`): a pinned sidebar row above the sections (the master DM leaves the DM list), ⌘J from anywhere, "Ask <name>" in the ⌘K palette and in the message More menu. ⌘J and the menu put a quote (selected message text or the composer text; the menu also adds the `buzz://message` link) into the DM draft and never send. Buzz Term moved from ⌘J to ⌃`. Mobile has no master support yet.

## Agent change proposals

Desktop reads kind 30192 with the 30190/30191 state (`#p` = owner) and accepts it only from an author of those state events. A pending, not expired proposal shows as a card above the composer in the DM with its requester (`requester` key) and in the Agents page "Olympus agents" section: target, operation, reason as plain text, diff, age, expiry, and high-risk marks. Approve and Reject send kind 44310 (`action` approve|reject, `proposal` tag, digest; no `agent` tag). Approve of a proposal with high-risk marks needs a second confirmation and then adds `"highRisk": true`. The card shows the 44311 result and the republished phase until dismissed.
