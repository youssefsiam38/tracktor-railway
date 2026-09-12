#!/usr/bin/env bash
# shellcheck disable=SC2015
# Persistence: the owner account, vehicles and fuel logs survive recreating the container.
set -euo pipefail
REPO_ROOT=$(cd "$(dirname "$0")/.." && pwd); export REPO_ROOT
# shellcheck source=tests/lib.sh
. "$REPO_ROOT/tests/lib.sh"
umask 077
printf '%s' 'local-test-only-tracktor-password' > "$TEST_TMP/pw"

section "fresh stack"
compose down -v --remove-orphans >/dev/null 2>&1 || true
compose up -d --no-build; wait_for_code "$BASE_URL/api/health" 200 420 || die "not ready"

section "write state"
JAR="$TEST_TMP/jar"
login owner "$TEST_TMP/pw" "$JAR" || die "owner login failed"
V=$(create_vehicle "$JAR" "Persist" "Estate" "PERSIST-1"); [ -n "$V" ] || die "vehicle create failed"
add_fuel_log "$JAR" "$V" 1200 40 >/dev/null
add_fuel_log "$JAR" "$V" 1600 38 >/dev/null
assert_eq "two fuel logs stored" "2" "$(jq -r '.data | length' <<<"$(fuel_logs "$JAR" "$V")")"
pass "state written: vehicle $V"

section "recreate the container on the same volume"
compose down >/dev/null; compose up -d --no-build
wait_for_code "$BASE_URL/api/health" 200 420 || die "not ready after recreate"
assert_contains "bootstrap left the account alone" "owner bootstrap skipped" "$(compose logs --no-color tracktor)"

section "verify"
JAR2="$TEST_TMP/jar2"
login owner "$TEST_TMP/pw" "$JAR2" && pass "owner password unchanged" || die "login failed after recreate"
v=$(vehicle_json "$JAR2" "$V")
assert_eq "vehicle still present" "Persist" "$(jq -r .data.make <<<"$v")"
assert_eq "plate retained" "PERSIST-1" "$(jq -r .data.licensePlate <<<"$v")"
l=$(fuel_logs "$JAR2" "$V")
assert_eq "fuel logs retained" "2" "$(jq -r '.data | length' <<<"$l")"
assert_eq "vehicle list retained" "1" "$(jq -r '.data | length' <<<"$(vehicles "$JAR2")")"
assert_eq "registration still closed" "403" "$(register_code "intruder" "intruder-password-long")"
add_fuel_log "$JAR2" "$V" 2000 42 >/dev/null
assert_eq "still writable after recreate" "3" "$(jq -r '.data | length' <<<"$(fuel_logs "$JAR2" "$V")")"
summary
