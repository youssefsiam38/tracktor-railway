#!/usr/bin/env bash
# shellcheck disable=SC2015
# Public smoke test against a deployed instance.
#   tests/railway-smoke.sh https://your-app.up.railway.app
# Optional: OWNER_USERNAME=owner OWNER_PASSWORD_FILE=/path/to/file
#   STATE_OUT=/path/state.json (create a vehicle) / STATE_IN=/path/state.json (verify after redeploy)
set -euo pipefail
REPO_ROOT=$(cd "$(dirname "$0")/.." && pwd); export REPO_ROOT
BASE_URL=${1:?usage: railway-smoke.sh https://domain}; BASE_URL=${BASE_URL%/}; export BASE_URL
# shellcheck source=tests/lib.sh
. "$REPO_ROOT/tests/lib.sh"
host=${BASE_URL#https://}

section "TLS and routing"
# Railway's edge serves 404 for a few seconds while a deployment takes over, so wait rather than
# racing the cutover when this runs straight after a deploy.
wait_for_code "$BASE_URL/api/health" 200 180 || true
assert_eq "health route answers over https" "200" "$(http_code "$BASE_URL/api/health")"
assert_contains "valid certificate" "SSL certificate verify ok" "$(curl -sv -o /dev/null "$BASE_URL/api/health" 2>&1 || true)"
assert_contains "http -> https" "https://$host" "$(curl -s -o /dev/null -w '%{http_code} %{redirect_url}' --max-time 20 "http://$host/api/health")"

section "registration is closed"
assert_eq "a stranger cannot register" "403" "$(register_code "intruder" "intruder-password-long")"
assert_eq "nor with the owner's name" "403" "$(register_code "${OWNER_USERNAME:-owner}" "another-password-entirely")"
code=$(login_code "intruder" "intruder-password-long")
[ "$code" != "200" ] && pass "the refused registration left no account behind (HTTP $code)" || fail "intruder account exists"

section "anonymous visitors are refused"
assert_eq "vehicle list refused" "401" "$(http_code "$BASE_URL/api/vehicles")"
assert_eq "dashboard refused" "401" "$(http_code "$BASE_URL/api/dashboard/summary")"
assert_eq "data export refused" "401" "$(http_code "$BASE_URL/api/data/export")"
code=$(login_code "${OWNER_USERNAME:-owner}" wrong-password-entirely)
[ "$code" != "200" ] && pass "wrong password rejected (HTTP $code)" || fail "wrong password accepted"

if [ -n "${OWNER_PASSWORD_FILE:-}" ]; then
  section "signed in through the public domain"
  JAR="$TEST_TMP/jar"
  login "${OWNER_USERNAME:-owner}" "$OWNER_PASSWORD_FILE" "$JAR" && pass "sign in with the generated password" || die "login failed"
  assert_eq "vehicle list visible" "200" "$(auth_code "$JAR" "$BASE_URL/api/vehicles")"
  assert_contains "session cookie is marked secure" "Secure" "$(grep -i session "$JAR" || echo "")"

  if [ -n "${STATE_OUT:-}" ]; then
    section "create a vehicle"
    V=$(create_vehicle "$JAR" "Railway" "Estate" "RAILWAY-1"); [ -n "$V" ] && pass "vehicle created ($V)" || die "vehicle create failed"
    add_fuel_log "$JAR" "$V" 1200 40 >/dev/null
    assert_eq "fuel log stored" "1" "$(jq -r '.data | length' <<<"$(fuel_logs "$JAR" "$V")")"
    jq -n --arg v "$V" '{vehicle:$v, make:"Railway", logs:1}' > "$STATE_OUT"
    pass "state written"
  fi

  if [ -n "${STATE_IN:-}" ]; then
    section "verify state after redeploy"
    V=$(jq -r .vehicle "$STATE_IN")
    v=$(vehicle_json "$JAR" "$V")
    assert_eq "vehicle still present" "$(jq -r .make "$STATE_IN")" "$(jq -r .data.make <<<"$v")"
    assert_eq "fuel logs retained" "$(jq -r .logs "$STATE_IN")" "$(jq -r '.data | length' <<<"$(fuel_logs "$JAR" "$V")")"
    add_fuel_log "$JAR" "$V" 1900 39 >/dev/null
    assert_eq "still writable" "2" "$(jq -r '.data | length' <<<"$(fuel_logs "$JAR" "$V")")"
  fi
fi
summary
