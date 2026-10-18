# Approvals Live Activity QA

Automates the Live Activity device checklist (plan Track L) in the iOS Simulator against a local relay, push gateway, and isolated test data. Items that need hardware are in [DEVICE.md](DEVICE.md).

## Commands

```
run.sh setup       keys, TLS, server and app builds, Simulator "Bl4uzz LA QA", databases
run.sh up          start relay, gateway, fake APNs, TLS proxy; seed data; first app launch
run.sh all         run checks 1-12; exits 1 if a check fails
run.sh check N...  run selected checks
run.sh status      card state and recent APNs captures
run.sh ask NAME    post an agent ask with a 30320 awaiting_owner status
run.sh fn NAME...  run one helper from lib.sh, stack.sh, or checks.sh
run.sh down        stop services and containers
run.sh clean       down, then delete the Simulator and the work folder
```

Run from the repository root, for example `qa/live-activity/run.sh setup && qa/live-activity/run.sh up && qa/live-activity/run.sh all`. Each check prints `ok` or `FAIL` per assertion and `PASS`, `FAIL`, or `SKIP`. A full run takes about 25 minutes; screenshots of key steps are in `shots/`. The work folder is `target/qa-live-activity` (`BUZZ_QA_DIR` overrides it). On the Mac mini, set `TMPDIR` and `CARGO_TARGET_DIR` to folders on the external SSD. Needs Xcode, idb, Docker, jq, uv, and the Hermit tools in `bin/`.

## Stack

- Relay with `BUZZ_PUSH_LIVE_ACTIVITY_ENABLED=true` and Postgres and Redis from `compose.yml`.
- Push gateway built with Cargo feature `qa-simulator`. It accepts the Simulator App Attest format and sends APNs requests to `BUZZ_PUSH_QA_APNS_BASE_URL`. Production images never enable this feature.
- `tools/fake-apns.mjs` records every gateway APNs request in `state/apns.jsonl` (headers, payload, token hash). It replays alert payloads with `simctl push`. It writes Live Activity payloads to a Debug Simulator-only bridge in the app, which applies them with iOS push semantics: a start needs the current push-to-start token; an update or end needs a live activity with that update token, else it is dropped. If the app is not active, the endpoint launches it and then restores the lock or Home screen.
- `app/qa_main.dart` signs the app in as the test owner. While the harness holds the device locked, it makes secure storage fail with `errSecInteractionNotAllowed` (the Simulator has no data protection).
- `tools/nostr.py` signs agent asks, statuses, and owner decisions. `tools/ocr.swift` reads the Lock Screen and Dynamic Island, which are not in the accessibility tree.

## Simulator limits

`simctl push` cannot deliver `liveactivity` pushes and does not run the Notification Service Extension. The Simulator has no passcode, so Lock Screen intents run without authentication. Check 3 is skipped; check 8 ages the card past the 30 minute start bound in the databases instead of waiting.
