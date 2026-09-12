# Security

## Reporting

Problems in **this wrapper** (entrypoint, bootstrap, proxy rules, template configuration): open an
issue at https://github.com/youssefsiam38/tracktor-railway/issues. If the problem is exploitable,
use GitHub's private vulnerability reporting on that repository instead of a public issue.

Problems in **Tracktor itself**: report upstream at https://github.com/javedh-dev/tracktor/issues.

## The two upstream facts this template works around

**1. Registration never closes.** Tracktor's auth middleware bypasses every path beginning with
`/api/auth`, and `/api/auth/register` is one of them. The endpoint therefore accepts new accounts
for the life of the instance, not only while it has none. Confirmed against the stock image: a
second registration after the first user exists returns HTTP 201.

**2. Accounts are not scoped to data.** There is no per-user ownership of vehicles. Confirmed the
same way: a freshly registered second account listed the first account's vehicle, including its VIN
and licence plate.

On a home network those combine into a mild annoyance. On a public URL they mean anyone who finds
the address can enrol themselves and read or change your records.

This template responds by claiming the instance before it is reachable and by refusing the
registration route at the proxy.

## What is exposed

| Surface | Anonymous access |
|---|---|
| the web interface and the whole `/api` surface | refused, HTTP 401 |
| `/api/auth/register` | refused, HTTP 403, unless `TRACKTOR_ALLOW_REGISTRATION=true` |
| `/api/health` | open; upstream returns a timestamp and a fixed message |
| Tracktor's own listener on port 3000 | loopback only, never published |

## First-run account claim

A fresh Tracktor has no accounts and shows a registration form to whoever arrives first. The wrapper
creates your account inside the container before the public listener opens, so the window is never
open. The bootstrap is idempotent: once the account exists it is never touched again, so
`TRACKTOR_OWNER_PASSWORD` becomes a stale variable and changing your password in the app sticks.

## Adding other people

Set `TRACKTOR_ALLOW_REGISTRATION=true`, let them sign up, then set it back. The wrapper logs a
warning on every boot while it is open, and the smoke test asserts both the warning and the open
route. Remember that Tracktor does not separate users from each other: anyone you let in sees every
vehicle, every fuel log and every document.

## Secrets

- `TRACKTOR_OWNER_PASSWORD` and `APP_SECRET` are generated per deployment by the template.
- The wrapper prints variable **names**, lengths and outcomes — never values. The test suite asserts
  that neither the password nor the application secret appears in the container log.
- `APP_SECRET` encrypts stored notification-provider credentials. Changing it after you have
  configured a provider makes those credentials unreadable.
- The values in `compose.yaml` are labelled local-test-only and exist so the suite can assert they
  never appear in logs. They are not secrets and must not be reused.

## Transport and cookies

Railway terminates TLS at the edge and forwards to Caddy, which proxies to Tracktor over loopback.
`HTTP_MODE=https` makes Tracktor mark its session cookie `Secure`; the public smoke test asserts the
flag is present on a real deployment. `CORS_ORIGINS` is pinned to the deployment's own domain rather
than upstream's default of `*`.

## Third-party calls made by the application

Tracktor makes no outbound calls of its own unless you configure a notification provider.

## Updates

Both base images are pinned by tag **and** digest; the workflow publishes multi-arch images and the
release notes record the digest. See [MAINTENANCE.md](MAINTENANCE.md).
