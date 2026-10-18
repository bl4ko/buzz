HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO=$(cd "$HERE/../.." && pwd)
QA_DIR=${BUZZ_QA_DIR:-$REPO/target/qa-live-activity}
TARGET=${CARGO_TARGET_DIR:-$REPO/target}
STATE=$QA_DIR/state
LOGS=$QA_DIR/logs
SHOTS=$QA_DIR/shots
BIN=$QA_DIR/bin
BUNDLE=xyz.block.buzz.dogfood.mobile
SIM_NAME="Bl4uzz LA QA"
PORT_RELAY=3461
PORT_GATEWAY=3462
PORT_APNS=3463
PORT_GATEWAY_HEALTH=3464
PORT_RELAY_TLS=8661
PORT_GATEWAY_TLS=8662
PORT_RELAY_HEALTH=18561
PORT_RELAY_METRICS=18661
RELAY_WS=wss://localhost:$PORT_RELAY_TLS
RELAY_HTTPS=https://localhost:$PORT_RELAY_TLS
GATEWAY_HTTPS=https://localhost:$PORT_GATEWAY_TLS
COMPOSE=(docker compose -f "$HERE/compose.yml")
export TMPDIR=${TMPDIR:-/tmp}

mkdir -p "$STATE/keys" "$STATE/tls" "$LOGS" "$SHOTS" "$BIN"
chmod 700 "$STATE/keys"

log() { printf '%s %s\n' "$(date +%H:%M:%S)" "$*" >&2; }
die() { log "error: $*"; exit 1; }
key() { tr -d '[:space:]' <"$STATE/keys/$1.$2"; }
phone() { xcrun simctl list devices -j | jq -r --arg n "$SIM_NAME" '[.devices[][] | select(.name == $n and .isAvailable)][0].udid // empty'; }

psql_relay() { "${COMPOSE[@]}" exec -T postgres psql -U buzz -d buzz -X -A -t -q -v ON_ERROR_STOP=1 "$@"; }

nostr() {
  local command=$1 who=$2
  shift 2
  QA_RELAY_HTTPS=$RELAY_HTTPS QA_CA=$STATE/tls/ca.pem uv run --quiet --no-project --python 3 \
    "$HERE/tools/nostr.py" "$command" "$STATE/keys/$who.key" "$@"
}

ask() {
  local name=$1 channel root id
  channel=$(sed -n 's/^CHANNEL=//p' "$STATE/seed.env")
  root=$(nostr event agent 9 "[[\"h\",\"$channel\"]]" "$name · in_progress" | jq -r .id)
  id=$(nostr event agent 9 "[[\"h\",\"$channel\"],[\"e\",\"$root\",\"\",\"reply\"],[\"p\",\"$(key owner pub)\"],[\"notification\",\"approval\"]]" \
    "@owner $name · awaiting_owner
Ask: Approve $name?" | jq -r .id)
  nostr event agent 30320 "[[\"d\",\"$root\"],[\"h\",\"$channel\"],[\"e\",\"$root\"],[\"status\",\"awaiting_owner\"],[\"title\",\"$name\"],[\"ask\",\"Approve $name?\",\"$id\"]]" >/dev/null
  printf '%s %s\n' "$root" "$id"
}

la_state() { psql_relay -c "SELECT result, open_count, coalesce(started_at, -1) FROM push_live_activity_state"; }

apns_log() { [ -f "$STATE/apns.jsonl" ] && jq -c '{type, topic_ok, priority, event: .payload.aps.event, open: .payload.aps["content-state"].openCount, ask: .payload.aps["content-state"].ask, replay}' "$STATE/apns.jsonl"; }

wait_for() {
  local seconds=$1
  shift
  local deadline=$((SECONDS + seconds))
  until "$@"; do
    ((SECONDS < deadline)) || return 1
    sleep 1
  done
}

start_bg() {
  local name=$1
  shift
  if [ -f "$STATE/$name.pid" ] && kill -0 "$(cat "$STATE/$name.pid")" 2>/dev/null; then return; fi
  nohup "$@" >>"$LOGS/$name.log" 2>&1 </dev/null &
  echo $! >"$STATE/$name.pid"
}

stop_bg() {
  local name=$1
  [ -f "$STATE/$name.pid" ] || return 0
  kill "$(cat "$STATE/$name.pid")" 2>/dev/null || true
  rm -f "$STATE/$name.pid"
}

udid() {
  [ -n "${UDID:-}" ] || UDID=$(phone)
  printf '%s' "$UDID"
}

app_data() { xcrun simctl get_app_container "$(udid)" "$BUNDLE" data; }

protected_data() {
  local flag
  flag="$(app_data)/Library/qa-protected-data-unavailable"
  if [ "$1" = unavailable ]; then touch "$flag"; else rm -f "$flag"; fi
}

lock_device() {
  printf locked >"$STATE/posture"
  protected_data unavailable
  idb ui button --udid "$(udid)" LOCK >/dev/null
  sleep 1.5
}

unlock_device() {
  idb ui swipe --udid "$(udid)" 200 860 200 250 --duration 0.3 >/dev/null
  protected_data available
  printf home >"$STATE/posture"
  sleep 1.5
}

go_home() {
  idb ui button --udid "$(udid)" HOME >/dev/null
  printf home >"$STATE/posture"
  sleep 1.5
}

open_app() {
  protected_data available
  printf app >"$STATE/posture"
  xcrun simctl launch "$(udid)" "$BUNDLE" >/dev/null
  sleep 2
}

kill_app() { xcrun simctl terminate "$(udid)" "$BUNDLE" >/dev/null 2>&1 || true; }

screen() {
  local tmp=/tmp/laqa-$$.png
  xcrun simctl io "$(udid)" screenshot --mask=black "$tmp" >/dev/null 2>&1
  cp "$tmp" "$TMPDIR/laqa-screen.png"
  rm -f "$tmp"
  "$BIN/ocr" "$TMPDIR/laqa-screen.png" 3
}

keep_shot() { cp "$TMPDIR/laqa-screen.png" "$SHOTS/$1.png"; }

screen_find() { screen | jq -r --arg t "$1" 'select(.text | ascii_downcase | contains($t | ascii_downcase)) | "\(.x) \(.y)"' | head -1; }

screen_has() { [ -n "$(screen_find "$1")" ]; }

wait_screen() { wait_for "${2:-20}" screen_has "$1"; }

screen_lacks() { ! screen_has "$1"; }

tap_screen() {
  local point
  point=$(screen_find "$1")
  [ -n "$point" ] || return 1
  idb ui tap --udid "$(udid)" ${point% *} ${point#* } >/dev/null
}

ax() { idb ui describe-all --udid "$(udid)" 2>/dev/null | jq -r '.[] | "\(.frame.x + .frame.width / 2 | floor) \(.frame.y + .frame.height / 2 | floor) \(.AXLabel // "" | gsub("\n"; " / "))"'; }

ax_find() { ax | awk -v t="$1" 'index($0, t) { print $1, $2; exit }'; }

ax_has() { [ -n "$(ax_find "$1")" ]; }

wait_ax() { wait_for "${2:-20}" ax_has "$1"; }

tap_ax() {
  local point
  point=$(ax_find "$1")
  [ -n "$point" ] || return 1
  idb ui tap --udid "$(udid)" ${point% *} ${point#* } >/dev/null
}

ax_find_exact() { ax | awk -v t="$1" '{ x = $1; y = $2; sub(/^[0-9-]+ [0-9-]+ /, ""); if ($0 == t) { print x, y; exit } }'; }

ax_has_exact() { [ -n "$(ax_find_exact "$1")" ]; }

tap_ax_exact() {
  local point
  point=$(ax_find_exact "$1")
  [ -n "$point" ] || return 1
  idb ui tap --udid "$(udid)" ${2:+--duration "$2"} ${point% *} ${point#* } >/dev/null
}

start_registered() { [ "$(gateway_sql "SELECT count(*) FROM push_gateway_live_activity_starts")" = "$1" ]; }

apns_mark() { [ -f "$STATE/apns.jsonl" ] && wc -l <"$STATE/apns.jsonl" | tr -d ' ' || echo 0; }

apns_after() { [ -f "$STATE/apns.jsonl" ] && tail -n +"$(($1 + 1))" "$STATE/apns.jsonl" || true; }

apns_match() { apns_after "$1" | jq -c "select($2)" | head -1 | grep -q .; }

wait_apns() { wait_for "${3:-45}" apns_match "$1" "$2"; }

apns_summary() { apns_after "$1" | jq -r '"\(.type) \(.payload.aps.event // "alert") p\(.priority) open=\(.payload.aps["content-state"].openCount // "-") ask=\(.payload.aps["content-state"].ask // "-") -> \(.replay)"'; }

owner_decisions() {
  psql_relay -c "SELECT count(*) FROM events WHERE kind = 7 AND deleted_at IS NULL AND content = '$2' \
    AND pubkey = decode('$(key owner pub)', 'hex') AND tags @> '[[\"e\",\"$1\"]]'::jsonb"
}

la_result() { psql_relay -c "SELECT result FROM push_live_activity_state LIMIT 1"; }

gateway_sql() { "${COMPOSE[@]}" exec -T postgres psql -U buzz -d push -X -A -t -q -v ON_ERROR_STOP=1 -c "$1"; }

update_token_registered() { [ "$(gateway_sql "SELECT count(*) FROM push_gateway_live_activities WHERE update_token_ciphertext IS NOT NULL")" -gt 0 ]; }

open_asks() {
  psql_relay -c "SELECT DISTINCT ON (d_tag) d_tag || ' ' || (SELECT t->>1 FROM jsonb_array_elements(tags) t WHERE t->>0 = 'h') \
    || ' ' || (SELECT t->>1 FROM jsonb_array_elements(tags) t WHERE t->>0 = 'title') || ' ' \
    || (SELECT t->>1 FROM jsonb_array_elements(tags) t WHERE t->>0 = 'status') \
    FROM events WHERE kind = 30320 AND deleted_at IS NULL ORDER BY d_tag, created_at DESC, id" | awk '$4 != "done"'
}

close_all_asks() {
  local root channel title
  while read -r root channel title _; do
    [ -n "$root" ] || continue
    nostr event owner 30320 "[[\"d\",\"$root\"],[\"h\",\"$channel\"],[\"e\",\"$root\"],[\"status\",\"done\"],[\"title\",\"$title\"]]" >/dev/null
  done < <(open_asks)
  wait_for 45 card_closed
  gateway_sql "DELETE FROM push_gateway_live_activities" >/dev/null
}

card_closed() { case "$(la_result)" in "" | ended | not_registered) return 0 ;; *) return 1 ;; esac; }
