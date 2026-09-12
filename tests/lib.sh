#!/usr/bin/env bash
# shellcheck disable=SC2015  # `cond && pass || fail` is intentional; pass/fail always succeed
# Shared helpers for tracktor-railway tests. Source this file; do not execute it.
# Secrets are never echoed. Only names, lengths, and pass/fail results are printed.

: "${BASE_URL:=http://127.0.0.1:8080}"
: "${TEST_TIMEOUT:=300}"

TEST_TMP="${TEST_TMP:-$(mktemp -d)}"
export TEST_TMP
_PASS=0; _FAIL=0

pass() { _PASS=$((_PASS+1)); printf '  PASS  %s\n' "$*"; }
fail() { _FAIL=$((_FAIL+1)); printf '  FAIL  %s\n' "$*" >&2; }
die()  { printf 'FATAL: %s\n' "$*" >&2; exit 1; }
section() { printf '\n== %s ==\n' "$*"; }
summary() { printf '\n%d passed, %d failed\n' "$_PASS" "$_FAIL"; [ "$_FAIL" -eq 0 ]; }

# here-strings, not pipes: `grep -q` exits on the first match and a pipe writer would get SIGPIPE,
# which `pipefail` reports as failure when the haystack is larger than the pipe buffer
assert_eq() { if [ "$2" = "$3" ]; then pass "$1 ($3)"; else fail "$1: expected [$2] got [$3]"; fi; }
assert_contains() { if grep -q -- "$2" <<<"$3"; then pass "$1"; else fail "$1: missing [$2]"; fi; }
assert_not_contains() { if grep -q -- "$2" <<<"$3"; then fail "$1: found forbidden [$2]"; else pass "$1"; fi; }

http_code() { curl -s -o /dev/null -w '%{http_code}' --max-time 30 "$@"; }
auth_code() { local jar=$1; shift; curl -s -o /dev/null -w '%{http_code}' --max-time 30 -b "$jar" "$@"; }

wait_for_code() {
  local url=$1 want=$2 timeout=${3:-$TEST_TIMEOUT} start code
  start=$(date +%s)
  while :; do
    code=$(http_code "$url" || true)
    [ "$code" = "$want" ] && return 0
    if [ $(( $(date +%s) - start )) -ge "$timeout" ]; then printf 'timed out waiting for %s -> %s (last %s)\n' "$url" "$want" "$code" >&2; return 1; fi
    sleep 3
  done
}

# req_json JAR TIMEOUT curl-args... -> body, retried while the response is not JSON
req_json() {
  local jar=$1 timeout=$2; shift 2
  local start body code
  start=$(date +%s)
  while :; do
    body=$(curl -s -b "$jar" -w '\n%{http_code}' --max-time 60 "$@" || true)
    code=${body##*$'\n'}; body=${body%$'\n'*}
    if jq -e . >/dev/null 2>&1 <<<"$body"; then printf '%s' "$body"; return 0; fi
    if [ $(( $(date +%s) - start )) -ge "$timeout" ]; then
      printf 'non-JSON response after %ss (HTTP %s) from: %s\n  body: %s\n' "$timeout" "$code" "$*" "$(head -c 200 <<<"$body")" >&2
      return 1
    fi
    sleep 3
  done
}

# login USERNAME PASSWORD_FILE JAR -> 0 on success
login() {
  local u=$1 pf=$2 jar=$3 code
  : > "$jar"
  code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 30 -c "$jar" -X POST "$BASE_URL/api/auth" \
    -H 'Content-Type: application/json' \
    --data "$(jq -nc --arg u "$u" --rawfile p "$pf" '{username:$u, password:($p|rtrimstr("\n"))}')" || true)
  [ "$code" = "200" ]
}
login_code() {
  http_code -X POST "$BASE_URL/api/auth" -H 'Content-Type: application/json' \
    --data "$(jq -nc --arg u "$1" --arg p "$2" '{username:$u, password:$p}')"
}
register_code() {
  http_code -X POST "$BASE_URL/api/auth/register" -H 'Content-Type: application/json' \
    --data "$(jq -nc --arg u "$1" --arg p "$2" '{username:$u, password:$p}')"
}

vehicles() { req_json "$1" 120 "$BASE_URL/api/vehicles"; }
# create_vehicle JAR MAKE MODEL PLATE -> prints the vehicle id
create_vehicle() {
  local jar=$1 id
  id=$(cat /proc/sys/kernel/random/uuid)
  req_json "$jar" 120 -X POST "$BASE_URL/api/vehicles" -H 'Content-Type: application/json' \
    --data "$(jq -nc --arg i "$id" --arg mk "$2" --arg md "$3" --arg pl "$4" \
      '{id:$i, make:$mk, model:$md, year:2020, licensePlate:$pl, vin:("VIN"+($i|gsub("-";"")|ascii_upcase)[0:14]), color:"#123456", odometer:1000}')" \
    | jq -r '.data.id // empty'
}
vehicle_json() { req_json "$1" 120 "$BASE_URL/api/vehicles/$2"; }
# add_fuel_log JAR VEHICLE_ID ODOMETER LITRES
# Every nullable column is still required in the request body, so send them all explicitly.
add_fuel_log() {
  local jar=$1 id
  id=$(cat /proc/sys/kernel/random/uuid)
  req_json "$jar" 120 -X POST "$BASE_URL/api/vehicles/$2/fuel-logs" -H 'Content-Type: application/json' \
    --data "$(jq -nc --arg i "$id" --arg v "$2" --argjson o "$3" --argjson l "$4" \
      '{id:$i, vehicleId:$v, date:"2026-01-15", odometer:$o, fuelAmount:$l, rate:2, cost:80,
        filled:true, missedLast:false, notes:"", attachment:""}')"
}
fuel_logs() { req_json "$1" 120 "$BASE_URL/api/fuel-logs?vehicleId=$2"; }
compose() { docker compose -f "$REPO_ROOT/compose.yaml" "$@"; }
