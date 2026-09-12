#!/usr/bin/env bash
# shellcheck disable=SC2015
# Local smoke test. Run `docker compose build` first (CI does), or set TRACKTOR_RAILWAY_IMAGE.
set -euo pipefail
REPO_ROOT=$(cd "$(dirname "$0")/.." && pwd); export REPO_ROOT
# shellcheck source=tests/lib.sh
. "$REPO_ROOT/tests/lib.sh"
mkdir -p "$REPO_ROOT/test-output"; METRICS="$REPO_ROOT/test-output/metrics.txt"
LOCAL_PASSWORD='local-test-only-tracktor-password'
LOCAL_SECRET='local-test-only-app-secret-not-for-production'
umask 077
printf '%s' "$LOCAL_PASSWORD" > "$TEST_TMP/pw"

section "fresh stack (empty volume)"
compose down -v --remove-orphans >/dev/null 2>&1 || true
t0=$(date +%s); compose up -d --no-build
wait_for_code "$BASE_URL/api/health" 200 420 && pass "health route answers" || { compose logs --no-color tracktor | tail -40; die "never became ready"; }
cold=$(( $(date +%s) - t0 )); echo "cold_start_seconds=$cold" | tee "$METRICS"

section "first-boot bootstrap"
logs=$(compose logs --no-color tracktor)
assert_contains "app started on loopback" "starting Tracktor on 127.0.0.1:3000" "$logs"
assert_contains "waited for the app before opening up" "Tracktor is healthy; ensuring the owner account exists" "$logs"
assert_contains "owner created" "owner bootstrap complete" "$logs"
assert_contains "registration reported closed" "registration closed: yes" "$logs"
assert_not_contains "password not in logs" "$LOCAL_PASSWORD" "$logs"
assert_not_contains "app secret not in logs" "$LOCAL_SECRET" "$logs"

section "registration is closed"
# Tracktor's auth middleware bypasses everything under /api/auth, so upstream accepts new accounts
# forever. Since accounts are not scoped to data, one self-registered stranger sees every vehicle.
assert_eq "a stranger cannot register" "403" "$(register_code "intruder" "intruder-password-long")"
assert_eq "nor with the owner's name" "403" "$(register_code "owner" "another-password-entirely")"
code=$(login_code "intruder" "intruder-password-long")
[ "$code" != "200" ] && pass "the refused registration left no account behind (HTTP $code)" || fail "intruder account exists"

section "anonymous visitors are refused"
assert_eq "vehicle list refused" "401" "$(http_code "$BASE_URL/api/vehicles")"
assert_eq "dashboard refused" "401" "$(http_code "$BASE_URL/api/dashboard/summary")"
assert_eq "data export refused" "401" "$(http_code "$BASE_URL/api/data/export")"
assert_eq "health route stays open for the platform probe" "200" "$(http_code "$BASE_URL/api/health")"
code=$(login_code owner wrong-password-entirely)
[ "$code" != "200" ] && pass "wrong password rejected (HTTP $code)" || fail "wrong password accepted"

section "the app is not reachable except through the proxy"
assert_eq "internal port is not published" "000" "$(http_code --max-time 5 "http://127.0.0.1:3000/api/health" || true)"

section "authenticated workflow: vehicle and fuel log"
JAR="$TEST_TMP/jar"
login owner "$TEST_TMP/pw" "$JAR" && pass "owner login" || die "owner login failed"
assert_eq "vehicle list visible when signed in" "200" "$(auth_code "$JAR" "$BASE_URL/api/vehicles")"
V=$(create_vehicle "$JAR" "Smoke" "Wagon" "SMOKE-1"); [ -n "$V" ] && pass "vehicle created ($V)" || die "vehicle create failed"
v=$(vehicle_json "$JAR" "$V")
assert_eq "make stored" "Smoke" "$(jq -r .data.make <<<"$v")"
assert_eq "model stored" "Wagon" "$(jq -r .data.model <<<"$v")"
assert_eq "plate stored" "SMOKE-1" "$(jq -r .data.licensePlate <<<"$v")"
assert_eq "odometer stored" "1000" "$(jq -r .data.odometer <<<"$v")"
r=$(add_fuel_log "$JAR" "$V" 1200 40)
assert_eq "fuel log accepted" "true" "$(jq -r .success <<<"$r")"
assert_eq "litres recorded" "40" "$(jq -r .data.fuelAmount <<<"$r")"
l=$(fuel_logs "$JAR" "$V")
assert_eq "fuel log listed" "1" "$(jq -r '.data | length' <<<"$l")"
assert_eq "odometer on the log" "1200" "$(jq -r '.data[0].odometer' <<<"$l")"

section "graceful shutdown (SIGTERM)"
t1=$(date +%s); compose stop -t 30 tracktor; dur=$(( $(date +%s)-t1 ))
code=$(docker inspect --format '{{.State.ExitCode}}' "$(compose ps -a -q tracktor)")
[ "$dur" -lt 30 ] && pass "stopped in ${dur}s without SIGKILL" || fail "stop took ${dur}s"
case "$code" in 0|143) pass "exit status after SIGTERM is $code" ;; *) fail "unexpected exit status $code" ;; esac
compose start tracktor; wait_for_code "$BASE_URL/api/health" 200 300 && pass "restarted" || die "did not restart"
assert_contains "bootstrap is idempotent" "owner bootstrap skipped" "$(compose logs --no-color tracktor)"

section "fail-fast validation"
img=$(compose config --images | head -1)
run_img() { docker run --rm "$@" "$img" >"$TEST_TMP/ff.log" 2>&1; }
if run_img; then fail "should fail without an owner password"; else pass "exits without TRACKTOR_OWNER_PASSWORD"; fi
assert_contains "explains the claim risk" "would claim the instance" "$(cat "$TEST_TMP/ff.log")"
if run_img -e TRACKTOR_OWNER_PASSWORD=short; then fail "should reject a short password"; else pass "rejects a short password"; fi
assert_contains "states the length rule" "at least 12 characters" "$(cat "$TEST_TMP/ff.log")"
if run_img -e "TRACKTOR_OWNER_PASSWORD=$LOCAL_PASSWORD" -e HOST=0.0.0.0; then fail "should refuse to unbind from loopback"; else pass "refuses a non-loopback HOST"; fi
assert_contains "explains the loopback rule" "every request passes the proxy" "$(cat "$TEST_TMP/ff.log")"
if run_img -e "TRACKTOR_OWNER_PASSWORD=$LOCAL_PASSWORD" -e TRACKTOR_DISABLE_AUTH=true; then fail "should refuse to disable auth"; else pass "refuses TRACKTOR_DISABLE_AUTH=true"; fi
assert_contains "explains what disabling auth does" "publishes your vehicle records" "$(cat "$TEST_TMP/ff.log")"
if run_img -e "TRACKTOR_OWNER_PASSWORD=$LOCAL_PASSWORD" -e PORT=3000; then fail "should refuse a port collision"; else pass "refuses a port collision with the app"; fi
# upstream's image sets PORT to the app's own port; if that leaked through, every bare run would
# hit the collision above instead of the check under test
assert_eq "the image ships a public PORT default that does not collide" "8080" "$(docker run --rm --entrypoint sh "$img" -c 'echo "$PORT"')"
assert_contains "explains the collision" "cannot share a port" "$(cat "$TEST_TMP/ff.log")"
assert_not_contains "no secret echoed" "$LOCAL_PASSWORD" "$(cat "$TEST_TMP/ff.log")"

section "the opt-out is deliberate and loud"
docker rm -f trk-open >/dev/null 2>&1 || true
docker run -d --name trk-open -e TRACKTOR_ALLOW_REGISTRATION=true -e "TRACKTOR_OWNER_PASSWORD=$LOCAL_PASSWORD" \
  -e PORT=8090 -p 127.0.0.1:8090:8090 "$img" >/dev/null
for _ in $(seq 1 80); do [ "$(http_code --max-time 5 "http://127.0.0.1:8090/api/health" || true)" = "200" ] && break; sleep 3; done
assert_eq "open instance accepts registration" "201" "$(http_code -X POST "http://127.0.0.1:8090/api/auth/register" -H 'Content-Type: application/json' --data '{"username":"second","password":"second-password-long"}')"
assert_contains "and says so in the log" "Anyone who reaches this URL can create an account" "$(docker logs trk-open 2>&1)"
docker rm -f trk-open >/dev/null

section "image metadata"
assert_eq "architecture" "amd64" "$(docker image inspect "$img" --format '{{.Architecture}}')"
labels=$(docker image inspect "$img" --format '{{json .Config.Labels}}')
for l in org.opencontainers.image.source org.opencontainers.image.revision org.opencontainers.image.version io.tracktor-railway.upstream.version io.tracktor-railway.caddy.version; do
  assert_contains "label $l" "\"$l\"" "$labels"
done
assert_contains "upstream licence shipped" "MIT License" "$(compose exec -T tracktor head -1 /usr/share/licenses/tracktor-railway/TRACKTOR-LICENSE | tr -d '\r')"
assert_contains "Caddy licence shipped" "Apache License" "$(compose exec -T tracktor sed -n '2p' /usr/share/licenses/tracktor-railway/CADDY-LICENSE | tr -d '\r')"

section "metrics"
{ echo "image_bytes=$(docker image inspect "$img" --format '{{.Size}}')"
  docker stats --no-stream --format '{{.Name}} mem={{.MemUsage}}' | grep tracktor-railway-test | sed 's/^/mem_/'; } | tee -a "$METRICS"
summary
