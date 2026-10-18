#!/usr/bin/env bash
set -euo pipefail
. "$(cd "$(dirname "$0")" && pwd)/lib.sh"
. "$HERE/stack.sh"

case "${1:-}" in
  setup)
    keys_and_tls
    build_tools
    build_servers
    simulator
    build_app
    ;;
  up)
    databases
    start_services
    seed
    install_app
    first_launch
    ;;
  down)
    stop_services
    "${COMPOSE[@]}" down -v >/dev/null 2>&1 || true
    [ -n "$(phone)" ] && xcrun simctl uninstall "$(phone)" "$BUNDLE" 2>/dev/null || true
    rm -f "$STATE/seed.env" "$STATE/apns.jsonl" "$STATE/posture"
    ;;
  clean)
    "$0" down
    udid=$(phone)
    [ -n "$udid" ] && { xcrun simctl shutdown "$udid" 2>/dev/null || true; xcrun simctl delete "$udid"; }
    [[ "$QA_DIR" == */qa-live-activity ]] && rm -rf "$QA_DIR"
    ;;
  ask)
    ask "$2"
    ;;
  status)
    la_state
    apns_log | tail -"${2:-10}"
    ;;
  fn)
    . "$HERE/checks.sh"
    shift
    "$@"
    ;;
  check)
    shift
    . "$HERE/checks.sh"
    run_checks "$@"
    ;;
  all)
    . "$HERE/checks.sh"
    run_checks
    ;;
  *)
    sed -n '/^```$/,/^```$/p' "$HERE/README.md" | grep -v '^```'
    exit 2
    ;;
esac
