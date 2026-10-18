ISLAND="201 33"

title() { printf '\n== check %s: %s\n' "$CHECK" "$*"; }
note() { printf '   note: %s\n' "$*"; }
skip() {
  CHECK_RESULT=SKIP
  printf '   skip: %s\n' "$*"
}

expect() {
  local what=$1
  shift
  if "$@"; then
    printf '   ok    %s\n' "$what"
  else
    printf '   FAIL  %s\n' "$what"
    CHECK_RESULT=FAIL
  fi
}

new_ask() {
  local ids
  ids=$(ask "$1")
  ROOT=${ids% *}
  ASK=${ids#* }
}

delivered() { wait_apns "$1" ".type == \"liveactivity\" and .payload.aps.event == \"$2\" and .replay != null and $3" 45; }

apns_none() { ! apns_match "$@"; }

decisions_are() { [ "$(owner_decisions "$1" "$2")" = "$3" ]; }

wait_decisions() { wait_for 25 decisions_are "$@"; }

result_is() { [ "$(la_result)" = "$1" ]; }

screen_shows_all() {
  local text output
  output=$(screen | jq -r .text | tr 'A-Z' 'a-z')
  for text in "$@"; do
    grep -qF -- "$(printf '%s' "$text" | tr 'A-Z' 'a-z')" <<<"$output" || return 1
  done
}

wait_screen_all() { wait_for 25 screen_shows_all "$@"; }

screen_without() { ! screen_has "$1"; }

wait_screen_gone() { wait_for 25 screen_without "$1"; }

tap_word() {
  local point
  point=$(screen | jq -r --arg t "$1" 'select(.text == $t) | "\(.x) \(.y)"' | head -1)
  [ -n "$point" ] || return 1
  idb ui tap --udid "$(udid)" ${point% *} ${point#* } >/dev/null
}

consent_live_activities() {
  screen_has "allow Live Activities" || return 0
  tap_word Allow || tap_word "Always Allow"
  sleep 1
}

app_started() { ! ax_has "Starting Buzz"; }

fresh() {
  kill_app
  open_app
  wait_for 30 app_started
  close_all_asks
}

card_with() {
  fresh
  [ "${1:-}" = terminated ] && kill_app
  lock_device
  local mark
  mark=$(apns_mark)
  new_ask "$2"
  delivered "$mark" start '.replay == "started"' || return 1
  wait_for 30 update_token_registered || return 1
  consent_live_activities
  wait_screen "Approve $2?"
}

clear_card() {
  local point
  point=$(screen_find "$1")
  [ -n "$point" ] || return 1
  idb ui swipe --udid "$(udid)" 340 ${point#* } 60 ${point#* } --duration 0.5 >/dev/null
  wait_screen_gone "$1"
}

age_card() {
  psql_relay -c "UPDATE push_live_activity_state SET started_at = started_at - $1"
  gateway_sql "UPDATE push_gateway_live_activities SET started_at = started_at - make_interval(secs => $1)" >/dev/null
}

sign_in_shown() { ax_has "Scan a QR code" || ax_has "Use pairing code"; }

never_sign_in() {
  local deadline=$((SECONDS + $1))
  while ((SECONDS < deadline)); do
    sign_in_shown && return 1
    sleep 0.5
  done
}

tasks_show() { ax_has "$1 / Approve $1?"; }

open_tasks() {
  open_app
  local _
  for _ in 1 2 3; do ax_has "Back" && tap_ax "Back" && sleep 1; done
  tap_ax "tasks-test" && sleep 2
  tap_ax "Tasks" && sleep 2
}

live_activity_value() { idb ui describe-all --udid "$(udid)" 2>/dev/null | jq -r '.[] | select(.AXLabel == "Live Activities") | .AXValue'; }

tap_switch() { idb ui tap --udid "$(udid)" --api axbridge --match-key AXLabel "$1" >/dev/null 2>&1; }

live_activity_is() { [ "$(live_activity_value)" = "$1" ]; }

settings_ready() { ax_has_exact "General" || ax_has_exact "Live Activities"; }

live_activities_switch() {
  xcrun simctl terminate "$(udid)" com.apple.Preferences >/dev/null 2>&1 || true
  xcrun simctl launch "$(udid)" com.apple.Preferences >/dev/null
  wait_for 15 settings_ready || return 1
  if ! ax_has_exact "Live Activities"; then
    idb ui swipe --udid "$(udid)" 200 750 200 200 --duration 0.4 >/dev/null
    wait_for 10 ax_has_exact "Apps" && tap_ax_exact "Apps" || return 1
    wait_for 10 ax_has_exact "Buzz" && tap_ax_exact "Buzz" || return 1
    wait_for 10 ax_has_exact "Live Activities" || return 1
  fi
  live_activity_is "$1" || tap_switch "Live Activities"
  wait_for 5 live_activity_is "$1"
  local ok=$?
  xcrun simctl terminate "$(udid)" com.apple.Preferences >/dev/null 2>&1 || true
  return $ok
}

owner_done() {
  psql_relay -c "SELECT tags @> '[[\"status\",\"done\"]]'::jsonb FROM events WHERE kind = 30320 AND d_tag = '$1' \
    AND pubkey = decode('$(key owner pub)', 'hex') AND deleted_at IS NULL ORDER BY created_at DESC, id LIMIT 1" | grep -q t
}

community_id() { jq -r '.communities[0].id' "$(xcrun simctl get_app_container "$(udid)" "$BUNDLE" "group.$BUNDLE")/push-snapshot.json"; }

push_approval_notification() {
  local payload=$TMPDIR/laqa-approval.json
  jq -n --arg event "$ASK" --arg community "$(community_id)" --arg relay "$RELAY_HTTPS" --arg body "Approve $1?" '{
    aps: {alert: {title: "QA Agent", subtitle: "Approval required", body: $body}, sound: "approval.wav", category: "BUZZ_APPROVAL"},
    buzz_push_approval: {relay_url: $relay, event_id: $event, community_id: $community}
  }' >"$payload"
  xcrun simctl push "$(udid)" "$BUNDLE" "$payload" >/dev/null
}

check_1() {
  title "card appears on the Lock Screen after an ask; the approval alert is pushed"
  fresh
  lock_device
  local mark
  mark=$(apns_mark)
  new_ask C1
  expect "gateway sent push-to-start with the ask (topic, JWT, priority 10, alert)" delivered "$mark" start \
    '.topic_ok and .jwt and .priority == 10 and .payload.aps.alert.title == "Needs you" and .payload.aps["content-state"].ask == "Approve C1?" and .replay == "started"'
  expect "gateway sent the approval alert push (mutable content)" apns_match "$mark" \
    '.type == "alert" and .topic_ok and .payload.aps["mutable-content"] == 1'
  consent_live_activities
  expect "Lock Screen card shows Needs you and the ask" wait_screen_all "Needs you" "Approve C1?" "Approve" "Deny"
  keep_shot check-1
  note "the alert title, sound, and actions come from the Notification Service Extension, which simctl push does not run (DEVICE.md)"
}

check_2() {
  title "second ask: card shows the newest ask and +1 more; island shows the count; island tap opens Tasks"
  expect "card is running with an update token" card_with running C2a
  local mark
  mark=$(apns_mark)
  new_ask C2b
  expect "gateway sent an update with 2 open asks and the newest ask" delivered "$mark" update \
    '.payload.aps["content-state"].openCount == 2 and .payload.aps["content-state"].ask == "Approve C2b?" and .replay == "updated"'
  expect "Lock Screen card shows the newest ask and +1 more" wait_screen_all "Approve C2b?" "+1 more"
  keep_shot check-2-lock
  unlock_device
  go_home
  expect "Dynamic Island compact view shows 2 approvals" wait_screen "2 approvals"
  keep_shot check-2-island
  idb ui tap --udid "$(udid)" $ISLAND >/dev/null
  printf app >"$STATE/posture"
  expect "island tap opens the Tasks tab with both asks" wait_for 20 tasks_show C2b
  expect "the app is not on the sign-in screen" never_sign_in 1
  screen >/dev/null
  keep_shot check-2-tasks
  expect "Tasks tab lists the older ask too" tasks_show C2a
}

check_3() {
  title "Approve on the locked card without Face ID sends no reaction"
  skip "the Simulator has no passcode and no data protection, so a Lock Screen intent runs without authentication (DEVICE.md item 1)"
}

check_4() {
  title "Approve on the Lock Screen card: one ✅ on the shown ask; the card moves to the next ask"
  expect "card is running with an update token" card_with running C4a
  local first=$ASK mark
  mark=$(apns_mark)
  new_ask C4b
  expect "card shows the second ask" delivered "$mark" update '.replay == "updated"'
  wait_screen "Approve C4b?" >/dev/null
  xcrun simctl spawn "$(udid)" notifyutil -p com.apple.BiometricKit_Sim.pearl.match
  mark=$(apns_mark)
  expect "tap Approve on the card" tap_word Approve
  expect "relay has exactly one owner ✅ on the shown ask" wait_decisions "$ASK" ✅ 1
  expect "the other ask has no decision" decisions_are "$first" ✅ 0
  expect "gateway moved the card to the next ask" delivered "$mark" update \
    '.payload.aps["content-state"].ask == "Approve C4a?" and .payload.aps["content-state"].openCount == 1 and .replay == "updated"'
  expect "card shows the next ask without +N more" wait_screen "Approve C4a?"
  expect "card has no +N more" screen_without "+1 more"
  keep_shot check-4
  note "the Face ID prompt is not exercised; the Simulator runs the intent without authentication"
}

check_5() {
  title "Deny from the expanded Dynamic Island: ❌ on the ask; the card ends"
  expect "card is running with an update token" card_with running C5
  unlock_device
  go_home
  idb ui tap --udid "$(udid)" --duration 1.2 $ISLAND >/dev/null
  expect "expanded island shows the ask with Deny" wait_screen_all "Approve C5?" "Deny"
  keep_shot check-5-expanded
  local mark
  mark=$(apns_mark)
  expect "tap Deny in the expanded island" tap_word Deny
  expect "relay has one owner ❌ on the ask" wait_decisions "$ASK" ❌ 1
  expect "gateway ended the card" delivered "$mark" end '.replay == "ended"'
  expect "island is gone" wait_screen_gone "approval"
}

check_6() {
  title "a decision from another client ends the card"
  expect "card is running with an update token" card_with running C6
  local mark
  mark=$(apns_mark)
  nostr event owner 7 "[[\"e\",\"$ASK\"]]" ✅ >/dev/null
  expect "gateway ended the card" delivered "$mark" end '.replay == "ended"'
  expect "Lock Screen card is gone" wait_screen_gone "Approve C6?"
}

check_7() {
  title "app terminated: push-to-start shows a card; a further ask updates it"
  fresh
  kill_app
  lock_device
  local mark
  mark=$(apns_mark)
  new_ask C7a
  expect "gateway sent push-to-start and the card started" delivered "$mark" start '.replay == "started"'
  expect "the woken app registered the card's update token" wait_for 30 update_token_registered
  consent_live_activities
  expect "Lock Screen card shows the ask" wait_screen "Approve C7a?"
  kill_app
  mark=$(apns_mark)
  new_ask C7b
  expect "gateway sent an update to the running card" delivered "$mark" update \
    '.payload.aps["content-state"].openCount == 2 and .replay == "updated"'
  expect "card shows the newest ask and +1 more" wait_screen_all "Approve C7b?" "+1 more"
  keep_shot check-7
  note "emulated delivery launches the terminated app to apply an update; iOS applies updates without the app"
}

check_8() {
  title "card cleared while the app is terminated: the next ask brings a card back"
  expect "card is running with an update token" card_with terminated C8a
  kill_app
  expect "card cleared from the Lock Screen" clear_card "Approve C8a?"
  local mark
  mark=$(apns_mark)
  new_ask C8b
  expect "inside the 30 min start bound the gateway only updates (no extra push-to-start)" delivered "$mark" update 'true'
  expect "no push-to-start inside the start bound" apns_none "$mark" '.payload.aps.event == "start"'
  age_card 1860
  note "aged the card 31 min in the relay and gateway databases to pass the start bound"
  mark=$(apns_mark)
  new_ask C8c
  expect "next ask after the start bound sends a push-to-start" delivered "$mark" start '.replay == "started"'
  expect "a card shows the newest ask" wait_screen "Approve C8c?"
  keep_shot check-8
  apns_summary "$mark" | sed 's/^/   apns: /'
}

check_9() {
  title "cold start from a locked device: card body and +N more open Tasks, not sign-in"
  fresh
  kill_app
  lock_device
  local mark
  mark=$(apns_mark)
  new_ask C9a
  expect "push-to-start woke the app behind the lock" delivered "$mark" start '.replay == "started"'
  consent_live_activities
  expect "Lock Screen card shows the ask" wait_screen "Approve C9a?"
  sleep 45
  expect "tap the card body" tap_screen "Approve C9a?"
  protected_data available
  printf app >"$STATE/posture"
  expect "the app does not show the sign-in screen" never_sign_in 10
  expect "the app shows Tasks of tasks-test with the ask" wait_for 20 tasks_show C9a
  keep_shot check-9-body
  kill_app
  lock_device
  mark=$(apns_mark)
  new_ask C9b
  expect "the update cold-started the app behind the lock" delivered "$mark" update '.replay == "updated"'
  expect "Lock Screen card shows +1 more" wait_screen "+1 more"
  sleep 45
  expect "tap +1 more" tap_screen "+1 more"
  protected_data available
  printf app >"$STATE/posture"
  expect "the app does not show the sign-in screen" never_sign_in 10
  expect "the app shows Tasks with the newest ask" wait_for 20 tasks_show C9b
  note "the QA entry point emulates the locked keychain (errSecInteractionNotAllowed) because the Simulator has no data protection"
  note "each tap waits 45 s after the locked launch, longer than the Riverpod retry window (about 38 s)"
}

check_10() {
  title "approval notification action (the path a Watch action uses): Approve sends ✅"
  fresh
  local mark
  mark=$(apns_mark)
  new_ask C10
  wait_apns "$mark" '.type == "alert" and .replay == "ok"' >/dev/null
  go_home
  sleep 6
  push_approval_notification C10
  expect "approval banner is shown" wait_for 10 ax_has_exact "Notification"
  tap_ax_exact "Notification" 1.0
  expect "long press shows Approve and Deny" wait_for 10 ax_has_exact "Deny"
  keep_shot check-10
  expect "tap the Approve action" tap_ax_exact "Approve"
  expect "relay has one owner ✅ on the ask" wait_decisions "$ASK" ✅ 1
  note "the notification is pushed already resolved; on a device the Notification Service Extension resolves it"
  note "no Watch Simulator: mirrored notifications and the Smart Stack need real APNs (DEVICE.md)"
}

check_11() {
  title "Live Activities off: relay gets not_registered; the approval alert is still pushed"
  fresh
  expect "turn Live Activities off in Settings" live_activities_switch 0
  kill_app
  open_app
  expect "relaunched app removed its push-to-start registration" wait_for 30 start_registered 0
  lock_device
  local mark
  mark=$(apns_mark)
  new_ask C11
  expect "relay recorded not_registered" wait_for 30 result_is not_registered
  expect "gateway still pushed the approval alert" wait_apns "$mark" '.type == "alert"' 30
  expect "no Live Activity push was sent" apns_none "$mark" '.type == "liveactivity"'
  expect "Buzz notification is on the Lock Screen" wait_ax "BUZZ"
  expect "turn Live Activities on again" live_activities_switch 1
  kill_app
  open_app
  expect "relaunched app registered push-to-start again" wait_for 30 start_registered 1
  note "a warm return to the app after the switch does not re-register; the coordinator does not observe activityEnablementUpdates"
}

check_12() {
  title "Tasks tab Done on the iPhone publishes the owner's kind-30320 done"
  fresh
  new_ask C12
  open_tasks
  expect "Tasks tab lists the ask" wait_for 20 tasks_show C12
  expect "tap Mark C12 done" tap_ax "Mark C12 done"
  expect "relay has the owner's done status for the thread" wait_for 20 owner_done "$ROOT"
}

run_checks() {
  set +e
  local checks=("$@") failed=0 summary=()
  [ ${#checks[@]} -gt 0 ] && [ "${checks[0]}" != all ] || checks=(1 2 3 4 5 6 7 8 9 10 11 12)
  for CHECK in "${checks[@]}"; do
    CHECK_RESULT=PASS
    "check_$CHECK"
    printf '   %s\n' "$CHECK_RESULT"
    summary+=("$CHECK=$CHECK_RESULT")
    [ "$CHECK_RESULT" = FAIL ] && failed=1
  done
  printf '\nsummary: %s\n' "${summary[*]}"
  return $failed
}
