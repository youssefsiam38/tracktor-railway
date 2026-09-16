#!/bin/sh
# tracktor-railway entrypoint.
#
#   1. validate variables (names only; values are never printed)
#   2. start Tracktor on loopback, create the owner account, and only then open the public port
#   3. front the app with Caddy, which refuses the permanently-open registration route
#   4. supervise both; if either exits, the container exits
set -u

# Railway colours a log line by the stream it arrived on, so routine start-up messages go to stdout
# and only failures go to stderr; otherwise the whole first boot is shown to the deployer in red.
log()  { printf '[tracktor-railway] %s\n' "$*"; }
fail() { printf '[tracktor-railway] FATAL: %s\n' "$*" >&2; exit 1; }

: "${HOST:=127.0.0.1}"
: "${TRACKTOR_INTERNAL_PORT:=3000}"
: "${TRACKTOR_OWNER_USERNAME:=owner}"
: "${APP_READY_TIMEOUT:=180}"
BOOTSTRAP=/usr/local/lib/tracktor-railway/bootstrap-owner.mjs
CADDYFILE=/etc/tracktor-railway/Caddyfile

PUBLIC_PORT="${PORT:-8080}"
case "$PUBLIC_PORT" in
  ''|*[!0-9]*) fail "PORT must be a number, got \"$PUBLIC_PORT\"" ;;
esac
if [ "$PUBLIC_PORT" = "$TRACKTOR_INTERNAL_PORT" ]; then
  fail "PORT and TRACKTOR_INTERNAL_PORT are both $PUBLIC_PORT. The public listener and the app cannot share a port; change TRACKTOR_INTERNAL_PORT."
fi

case "$HOST" in
  127.0.0.1|localhost|::1) ;;
  *) fail "HOST is \"$HOST\". This image binds Tracktor to loopback on purpose so that every request passes the proxy that closes registration. Remove the variable." ;;
esac

if [ "${TRACKTOR_DISABLE_AUTH:-false}" = "true" ]; then
  fail "TRACKTOR_DISABLE_AUTH=true removes Tracktor's login entirely, which on a public URL publishes your vehicle records to anyone. Refusing to start."
fi

[ -n "${TRACKTOR_OWNER_PASSWORD:-}" ] || fail "missing required variable: TRACKTOR_OWNER_PASSWORD. A fresh Tracktor has no accounts and its registration page is open, so the first stranger to find the URL would claim the instance."
[ "${#TRACKTOR_OWNER_PASSWORD}" -ge 12 ] || fail "TRACKTOR_OWNER_PASSWORD must be at least 12 characters"
[ "${#TRACKTOR_OWNER_USERNAME}" -ge 3 ] || fail "TRACKTOR_OWNER_USERNAME must be at least 3 characters"

if [ -z "${APP_SECRET:-}" ]; then
  log "WARNING: APP_SECRET is not set. Notification provider credentials cannot be stored until it is."
fi

# Tracktor's auth middleware bypasses everything under /api/auth, and /api/auth/register lives
# there, so the endpoint never stops accepting new accounts. Since accounts are not scoped to data,
# one self-registered stranger sees every vehicle. Close it at the proxy.
ALLOW_REG="${TRACKTOR_ALLOW_REGISTRATION:-false}"
if [ "$ALLOW_REG" = "true" ]; then
  log "WARNING: TRACKTOR_ALLOW_REGISTRATION=true. Anyone who reaches this URL can create an account, and every account sees every vehicle."
  REGISTER_BLOCK=""
else
  REGISTER_BLOCK="	handle /api/auth/register {
		respond \"Registration is closed on this deployment.\" 403
	}
"
fi

mkdir -p /etc/tracktor-railway || fail "cannot create /etc/tracktor-railway"
cat > "$CADDYFILE" <<EOF
{
	admin off
	auto_https off
	persist_config off
}
:${PUBLIC_PORT} {
${REGISTER_BLOCK}	handle {
		reverse_proxy 127.0.0.1:${TRACKTOR_INTERNAL_PORT}
	}
}
EOF
caddy validate --config "$CADDYFILE" --adapter caddyfile >/dev/null 2>&1 \
  || fail "generated Caddy configuration is invalid"

export HOST PORT="$TRACKTOR_INTERNAL_PORT"
TRACKTOR_INTERNAL_URL="http://127.0.0.1:${TRACKTOR_INTERNAL_PORT}"
export TRACKTOR_INTERNAL_URL TRACKTOR_OWNER_USERNAME

log "starting Tracktor on ${HOST}:${TRACKTOR_INTERNAL_PORT} behind the public listener on :${PUBLIC_PORT}"
docker-entrypoint.sh "$@" &
app_pid=$!

deadline=$(( $(date +%s) + APP_READY_TIMEOUT ))
until node -e "
fetch('${TRACKTOR_INTERNAL_URL}/api/health').then(r => process.exit(r.ok ? 0 : 1)).catch(() => process.exit(1));
" 2>/dev/null; do
  kill -0 "$app_pid" 2>/dev/null || fail "Tracktor exited during start-up"
  [ "$(date +%s)" -lt "$deadline" ] || fail "Tracktor did not become healthy within ${APP_READY_TIMEOUT}s"
  sleep 2
done
log "Tracktor is healthy; ensuring the owner account exists"
node "$BOOTSTRAP" || fail "owner bootstrap failed"

log "opening the public listener (registration closed: $([ "$ALLOW_REG" = "true" ] && echo no || echo yes))"
caddy run --config "$CADDYFILE" --adapter caddyfile &
caddy_pid=$!

trap 'kill -TERM "$app_pid" "$caddy_pid" 2>/dev/null' TERM INT

# BusyBox ash has no reliable `wait -n`, so poll both children and exit as soon as either does.
while :; do
  if ! kill -0 "$app_pid" 2>/dev/null; then
    wait "$app_pid"; status=$?
    log "Tracktor exited with status ${status}; shutting down"
    break
  fi
  if ! kill -0 "$caddy_pid" 2>/dev/null; then
    wait "$caddy_pid"; status=$?
    log "the public listener exited with status ${status}; shutting down"
    break
  fi
  sleep 1
done
kill -TERM "$app_pid" "$caddy_pid" 2>/dev/null
exit "$status"
