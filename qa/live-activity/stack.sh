keys_and_tls() {
  "$REPO/bin/node" "$HERE/tools/keys.mjs" "$STATE/keys" relay owner agent member
  [ -f "$STATE/tls/leaf.pem" ] && return
  (
    cd "$STATE/tls" || exit 1
    umask 077
    openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:P-256 -nodes -keyout ca.key -out ca.pem -days 30 \
      -subj "/CN=Buzz LA QA CA" -addext "basicConstraints=critical,CA:TRUE" -addext "keyUsage=critical,keyCertSign,cRLSign" \
      -addext "subjectKeyIdentifier=hash" 2>/dev/null
    openssl req -newkey ec -pkeyopt ec_paramgen_curve:P-256 -nodes -keyout leaf.key -out leaf.csr -subj "/CN=localhost" 2>/dev/null
    printf '%s\n' subjectAltName=DNS:localhost,IP:127.0.0.1,IP:::1 extendedKeyUsage=serverAuth basicConstraints=CA:FALSE \
      keyUsage=critical,digitalSignature subjectKeyIdentifier=hash authorityKeyIdentifier=keyid >leaf.ext
    openssl x509 -req -in leaf.csr -CA ca.pem -CAkey ca.key -CAcreateserial -out leaf.pem -days 30 -extfile leaf.ext 2>/dev/null
    rm -f leaf.csr ca.srl leaf.ext
    chmod 644 ca.pem leaf.pem
  )
  openssl rand -base64 32 | tr -d '\n' >"$STATE/keys/grant.b64"
  openssl rand -base64 32 | tr -d '\n' >"$STATE/keys/token.b64"
}

build_tools() {
  xcrun swiftc -O -o "$BIN/ocr" "$HERE/tools/ocr.swift"
}

build_servers() {
  log "building relay and push gateway (qa-simulator)"
  (
    cd "$REPO" || exit 1
    . ./bin/activate-hermit >/dev/null 2>&1
    cargo build -p buzz-relay >"$LOGS/cargo-relay.log" 2>&1
    cp "$TARGET/debug/buzz-relay" "$BIN/buzz-relay"
    cargo build -p buzz-push-gateway --features qa-simulator >"$LOGS/cargo-gateway.log" 2>&1
    cp "$TARGET/debug/buzz-push-gateway" "$BIN/buzz-push-gateway"
  )
}

build_app() {
  log "building the iOS app for the Simulator"
  local entry=$REPO/mobile/lib/qa_live_activity_main.dart
  cp "$HERE/app/qa_main.dart" "$entry"
  trap 'rm -f "$entry"' RETURN
  (
    cd "$REPO" || exit 1
    . ./bin/activate-hermit >/dev/null 2>&1
    cd mobile
    flutter pub get --offline >"$LOGS/pub.log" 2>&1
    flutter build ios --config-only --debug --simulator --no-pub -t lib/qa_live_activity_main.dart \
      --dart-define=QA_RELAY="$RELAY_WS" \
      --dart-define=QA_PUB="$(key owner pub)" \
      --dart-define=QA_NSEC="$(key owner nsec)" \
      --dart-define=BUZZ_PUSH_GATEWAY_URL="$GATEWAY_HTTPS" >"$LOGS/flutter-config.log" 2>&1
    cd ios
    xcrun xcodebuild -workspace Runner.xcworkspace -scheme Runner -configuration Debug \
      -destination "platform=iOS Simulator,id=$(phone)" ARCHS=arm64 ONLY_ACTIVE_ARCH=YES \
      -derivedDataPath "$QA_DIR/derived" -onlyUsePackageVersionsFromResolvedFile -skipPackagePluginValidation \
      build >"$LOGS/xcodebuild.log" 2>&1
  ) || die "app build failed, see $LOGS"
  git -C "$REPO" checkout -- mobile/ios/Podfile.lock 2>/dev/null || true
  git -C "$REPO" clean -fdq -- mobile/ios/Runner.xcodeproj/project.xcworkspace/xcshareddata/swiftpm
}

simulator() {
  local udid
  udid=$(phone)
  if [ -z "$udid" ]; then
    udid=$(xcrun simctl create "$SIM_NAME" com.apple.CoreSimulator.SimDeviceType.iPhone-17-Pro com.apple.CoreSimulator.SimRuntime.iOS-26-5)
  fi
  xcrun simctl boot "$udid" 2>/dev/null || true
  xcrun simctl bootstatus "$udid" -b >/dev/null
  xcrun simctl keychain "$udid" add-root-cert "$STATE/tls/ca.pem"
  xcrun simctl spawn "$udid" notifyutil -s com.apple.BiometricKit.enrollmentChanged 1
  xcrun simctl spawn "$udid" notifyutil -p com.apple.BiometricKit.enrollmentChanged
}

install_app() {
  local udid
  udid=$(phone)
  for _ in 1 2 3; do
    xcrun simctl install "$udid" "$QA_DIR/derived/Build/Products/Debug-iphonesimulator/Buzz.app" && return
    sleep 10
  done
  die "install failed"
}

databases() {
  "${COMPOSE[@]}" up -d --wait >/dev/null
  if ! psql_relay -c "SELECT 1 FROM pg_roles WHERE rolname = 'push_runtime'" | grep -q 1; then
    psql_relay -c "CREATE ROLE push_runtime LOGIN PASSWORD 'push_dev'" -c "CREATE DATABASE push"
  fi
  DATABASE_URL=postgres://buzz:buzz_dev@127.0.0.1:15480/push BUZZ_PUSH_RUNTIME_DATABASE_ROLE=push_runtime \
    "$BIN/buzz-push-gateway" --migrate-only >>"$LOGS/gateway.log" 2>&1
}

start_services() {
  local udid fixtures=$REPO/crates/buzz-push-gateway/tests/fixtures
  udid=$(phone)
  start_bg apns "$REPO/bin/node" "$HERE/tools/fake-apns.mjs" "$PORT_APNS" "$STATE/apns.jsonl" "$udid" "$BUNDLE" "$STATE/posture"
  start_bg gateway env \
    DATABASE_URL=postgres://push_runtime:push_dev@127.0.0.1:15480/push \
    BUZZ_PUSH_BIND_ADDR=127.0.0.1:$PORT_GATEWAY BUZZ_PUSH_HEALTH_ADDR=127.0.0.1:$PORT_GATEWAY_HEALTH \
    BUZZ_PUSH_GRANT_KEYS="qa-grant:$(cat "$STATE/keys/grant.b64")" \
    BUZZ_PUSH_TOKEN_KEYS="qa-token:$(cat "$STATE/keys/token.b64")" \
    BUZZ_PUSH_MAX_GRANT_LIFETIME_SECONDS=2592000 \
    BUZZ_PUSH_APP_ATTEST_ROOT_CERT_PATH="$fixtures/apple-app-attestation-root.pem" \
    BUZZ_PUSH_APP_ATTEST_ENVIRONMENT=simulator \
    BUZZ_PUSH_DOGFOOD_APP_ATTEST_APP_ID="simulator.$BUNDLE" \
    BUZZ_PUSH_DOGFOOD_APNS_CERT_PATH="$fixtures/apns-test-identity.pem" \
    BUZZ_PUSH_DOGFOOD_APNS_TOPIC="$BUNDLE" \
    BUZZ_PUSH_DOGFOOD_APNS_ENVIRONMENT=sandbox \
    BUZZ_PUSH_DOGFOOD_APNS_AUTH_KEY_PATH="$fixtures/apns-test-auth-key.p8" \
    BUZZ_PUSH_DOGFOOD_APNS_AUTH_KEY_ID=QAKEY00001 \
    BUZZ_PUSH_DOGFOOD_APNS_TEAM_ID=QATEAM0001 \
    BUZZ_PUSH_QA_APNS_BASE_URL=http://127.0.0.1:$PORT_APNS \
    RUST_LOG=info "$BIN/buzz-push-gateway"
  mkdir -p "$STATE/repos"
  start_bg relay env \
    DATABASE_URL=postgres://buzz:buzz_dev@127.0.0.1:15480/buzz REDIS_URL=redis://127.0.0.1:16430 \
    BUZZ_BIND_ADDR=127.0.0.1:$PORT_RELAY RELAY_URL="$RELAY_WS" \
    BUZZ_HEALTH_PORT=$PORT_RELAY_HEALTH BUZZ_METRICS_PORT=$PORT_RELAY_METRICS \
    BUZZ_RELAY_PRIVATE_KEY="$(key relay key)" RELAY_OWNER_PUBKEY="$(key owner pub)" \
    BUZZ_PUSH_ENABLED=true BUZZ_PUSH_LIVE_ACTIVITY_ENABLED=true \
    BUZZ_PUSH_GATEWAY_DELIVERY_URL=http://127.0.0.1:$PORT_GATEWAY/v1/deliveries/apns \
    BUZZ_REQUIRE_AUTH_TOKEN=false BUZZ_REQUIRE_RELAY_MEMBERSHIP=false BUZZ_GIT_CONFORMANCE_PROBE=false \
    BUZZ_GIT_REPO_PATH="$STATE/repos" BUZZ_MEDIA_BASE_URL="$RELAY_HTTPS/media" \
    BUZZ_RATE_LIMIT_HUMAN_MESSAGES_PER_MIN=100000 BUZZ_RATE_LIMIT_HUMAN_API_CALLS_PER_MIN=100000 \
    BUZZ_RATE_LIMIT_HUMAN_WS_EVENTS_PER_SEC=10000 BUZZ_AUTO_MIGRATE=true RUST_LOG=info \
    "$BIN/buzz-relay"
  start_bg proxy "$REPO/bin/node" "$HERE/tools/tls-proxy.mjs" "$STATE/tls" "$PORT_RELAY_TLS:$PORT_RELAY" "$PORT_GATEWAY_TLS:$PORT_GATEWAY"
  wait_for 120 curl -fsS -o /dev/null --cacert "$STATE/tls/ca.pem" -H 'Accept: application/nostr+json' "$RELAY_HTTPS/" ||
    die "relay did not start, see $LOGS/relay.log"
  wait_for 30 curl -fsS -o /dev/null "http://127.0.0.1:$PORT_GATEWAY_HEALTH/_readiness" ||
    die "gateway did not start, see $LOGS/gateway.log"
}

stop_services() {
  for name in proxy relay gateway apns; do stop_bg "$name"; done
}

seed() {
  [ -f "$STATE/seed.env" ] && return
  log "seeding identities and channels"
  local channel other owner agent
  owner=$(key owner pub)
  agent=$(key agent pub)
  nostr event owner 0 '[]' '{"name":"QA Owner","display_name":"QA Owner"}' >/dev/null
  nostr event agent 0 '[]' '{"name":"QA Agent","display_name":"QA Agent"}' >/dev/null
  nostr event member 0 '[]' '{"name":"QA Member","display_name":"QA Member"}' >/dev/null
  channel=$(uuidgen | tr 'A-Z' 'a-z')
  other=$(uuidgen | tr 'A-Z' 'a-z')
  for pair in "$channel:tasks-test" "$other:general"; do
    nostr event owner 9007 "[[\"h\",\"${pair%%:*}\"],[\"name\",\"${pair#*:}\"],[\"channel_type\",\"stream\"],[\"visibility\",\"open\"]]" >/dev/null
    for member in "$agent" "$(key member pub)"; do
      nostr event owner 9000 "[[\"h\",\"${pair%%:*}\"],[\"p\",\"$member\"]]" >/dev/null
    done
  done
  for member in "$agent" "$(key member pub)"; do
    nostr event owner 9030 "[[\"p\",\"$member\"]]" >/dev/null
  done
  psql_relay -c "UPDATE users SET agent_owner_pubkey = decode('$owner', 'hex') WHERE pubkey = decode('$agent', 'hex')"
  printf 'CHANNEL=%s\nOTHER=%s\n' "$channel" "$other" >"$STATE/seed.env"
}

first_launch() {
  open_app
  if wait_for 20 ax_has "Would Like to Send You Notifications"; then
    tap_ax_exact "Allow"
  fi
  wait_for 60 start_registered 1 || die "the app did not register push-to-start with the gateway"
}
