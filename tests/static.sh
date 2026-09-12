#!/usr/bin/env bash
# shellcheck disable=SC2015
# Static validation: shell syntax, shellcheck, compose config, Dockerfile pins.
set -euo pipefail
REPO_ROOT=$(cd "$(dirname "$0")/.." && pwd); export REPO_ROOT
cd "$REPO_ROOT"
# shellcheck source=tests/lib.sh
. "$REPO_ROOT/tests/lib.sh"

section "shell syntax"
for f in scripts/*.sh; do
  if sh -n "$f" 2>/dev/null; then pass "parses: $f"; else fail "syntax error: $f"; fi
done
for f in tests/*.sh; do
  if bash -n "$f" 2>/dev/null; then pass "parses: $f"; else fail "syntax error: $f"; fi
done

section "shellcheck"
if command -v shellcheck >/dev/null; then
  if shellcheck -s sh scripts/*.sh; then pass "shellcheck scripts"; else fail "shellcheck scripts"; fi
  if shellcheck -x -s bash tests/*.sh; then pass "shellcheck tests"; else fail "shellcheck tests"; fi
else
  echo "  SKIP  shellcheck not installed"
fi

section "compose"
if docker compose -f compose.yaml config >/dev/null; then pass "compose config"; else fail "compose config"; fi

section "dockerfile pins"
df=$(cat Dockerfile)
assert_contains "Tracktor pinned by tag and digest" 'ghcr.io/javedh-dev/tracktor:2.1.0@sha256:' "$df"
assert_contains "Caddy pinned by tag and digest" 'caddy:2.10-alpine@sha256:' "$df"
assert_contains "entrypoint is the wrapper" 'ENTRYPOINT \["/usr/local/bin/tracktor-railway-entrypoint"\]' "$df"
assert_contains "app bound to loopback in the image" 'HOST=127.0.0.1' "$df"
assert_contains "session cookies marked secure" 'HTTP_MODE=https' "$df"
# The upstream image sets PORT to the app's own port. Left alone it collides with the internal
# listener and the wrapper refuses to start, so the image must replace it with a public default.
baked_port=$(docker run --rm --entrypoint sh "$(grep -oE 'tracktor-railway:[a-z0-9.-]+' compose.yaml | head -1)" -c 'echo "$PORT"' 2>/dev/null || echo "")
if [ -z "$baked_port" ]; then
  echo "  SKIP  image not built; cannot check the baked PORT"
else
  internal=$(grep -oE 'TRACKTOR_INTERNAL_PORT=[0-9]+' Dockerfile | head -1 | cut -d= -f2)
  if [ "$baked_port" = "$internal" ]; then fail "baked PORT ($baked_port) collides with TRACKTOR_INTERNAL_PORT"; else pass "baked PORT ($baked_port) differs from the internal port ($internal)"; fi
fi

section "the front door cannot be configured away"
ep=$(cat scripts/entrypoint.sh)
assert_contains "refuses a non-loopback HOST" 'binds Tracktor to loopback on purpose' "$ep"
assert_contains "requires an owner password" 'missing required variable: TRACKTOR_OWNER_PASSWORD' "$ep"
assert_contains "refuses to disable authentication" 'TRACKTOR_DISABLE_AUTH=true removes' "$ep"
assert_contains "blocks the permanently-open registration route" 'handle /api/auth/register' "$ep"
assert_contains "the generated config is validated before use" 'caddy validate' "$ep"
assert_contains "the owner exists before the door opens" 'opening the public listener' "$ep"
bs=$(cat scripts/bootstrap-owner.mjs)
assert_contains "bootstrap is idempotent" 'already exists' "$bs"
if node --check scripts/bootstrap-owner.mjs 2>/dev/null; then pass "bootstrap-owner.mjs parses"; else fail "bootstrap-owner.mjs syntax"; fi

section "workflows"
# a stale image-override name from a copied workflow makes CI test the wrong image, and the failure
# looks like a missing local build rather than a configuration mistake
override=$(grep -oE '[A-Z_]*_RAILWAY_IMAGE' compose.yaml | head -1)
for wf in .github/workflows/*.yml; do
  if grep -q 'candidate' "$wf" && ! grep -q "$override" "$wf"; then
    fail "$wf tests a candidate image but never sets $override"
  else
    pass "image override name matches compose in $wf"
  fi
done
for wf in .github/workflows/*.yml; do
  if grep -qE 'uses: .*@[0-9a-f]{40}' "$wf" && ! grep -qE 'uses: .*@v[0-9]+\s*$' "$wf"; then
    pass "actions pinned by SHA in $wf"
  else
    fail "unpinned action in $wf"
  fi
done

section "no tracked secrets"
if git rev-parse --git-dir >/dev/null 2>&1; then
  if git grep -nIE '(BEGIN [A-Z ]*PRIVATE KEY|ghp_[A-Za-z0-9]{20,}|xox[baprs]-)' -- . >/dev/null 2>&1; then
    fail "credential pattern in tracked files"
  else
    pass "no credential patterns in tracked files"
  fi
  if git ls-files --error-unmatch .env >/dev/null 2>&1; then fail ".env is tracked"; else pass ".env not tracked"; fi
else
  echo "  SKIP  not a git checkout"
fi
summary
