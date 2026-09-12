# Tracktor on Railway

A logbook for your cars. **Tracktor** records fuel fill-ups, servicing, insurance and registration
dates, and the running cost of every vehicle you own, then shows you mileage and spending over time.
This repository is a **community-maintained Railway template** for
[Tracktor](https://github.com/javedh-dev/tracktor). It is **not affiliated with the Tracktor
project**.

<!-- DEPLOY_BUTTON_START -->
[![Deploy on Railway](https://railway.com/button.svg)](https://railway.com/deploy/tracktor)

Template page: https://railway.com/deploy/tracktor
<!-- DEPLOY_BUTTON_END -->

> **Read this before deploying.** Tracktor has a real login, but its registration page never closes:
> the auth middleware skips every path under `/api/auth`, and `/api/auth/register` is one of them.
> Accounts are also not scoped to data, so any account sees every vehicle, including VIN and licence
> plate. On a public URL that means a stranger can sign themselves up and read your whole garage.
> This template creates your account before the service is reachable and blocks the registration
> route. See [SECURITY.md](SECURITY.md).

> **Licence.** Tracktor is **MIT** and so is the wrapper in this repository. The image also carries
> Caddy, which is Apache-2.0. See [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).

## What you get

| Service | Source | Public | Volume |
|---|---|---|---|
| `tracktor` | `ghcr.io/youssefsiam38/tracktor-railway:<version>` wrapping `ghcr.io/javedh-dev/tracktor:2.1.0` | yes | `/data` — SQLite database, uploads, logs |

| Component | Version |
|---|---|
| Tracktor | 2.1.0 |
| Caddy (the proxy that closes registration) | 2.10.2 |
| Wrapper | v1.0.0 — `ghcr.io/youssefsiam38/tracktor-railway:1.0.0` ([releases](https://github.com/youssefsiam38/tracktor-railway/releases)) |

One service, one volume, no external database. Why a wrapper:
[ARCHITECTURE.md](ARCHITECTURE.md).

## First run

1. Click **Deploy on Railway**. Nothing has to be filled in: your password and the application
   secret are generated.
2. Read `TRACKTOR_OWNER_PASSWORD` in the Railway dashboard under the `tracktor` service's Variables
   tab, clicking it to reveal.
3. Open the service's public URL and sign in as `owner` with that password.
4. Change the password in the app under your profile. The wrapper notices and leaves it alone from
   then on.
5. Add a vehicle, then start logging fill-ups and servicing.

To let someone else in, set `TRACKTOR_ALLOW_REGISTRATION=true`, have them sign up, then set it back
to `false`. Remember that every account sees every vehicle.

## Environment variables

| Variable | Required | Set by template | Description |
|---|---|---|---|
| `TRACKTOR_OWNER_PASSWORD` | yes | generated `${{secret(24)}}` | Wrapper: password for the account created on first start. At least 12 characters. Ignored once the account exists. |
| `TRACKTOR_OWNER_USERNAME` | no | `owner` | Wrapper: username for that account. |
| `TRACKTOR_ALLOW_REGISTRATION` | no | unset | Set `true` to reopen the registration page. Anyone who reaches the URL can then create an account, and every account sees every vehicle. |
| `APP_SECRET` | no | generated `${{secret(64, "abcdef0123456789")}}` | Encrypts stored notification credentials. Required before you can configure a notification provider. |
| `PORT` | no | `8080` | Port the proxy listens on. Railway probes its healthcheck here, so keep it equal to the domain's target port. |
| `TRACKTOR_INTERNAL_PORT` | no | `3000` | Loopback port the app itself listens on. Never exposed. |
| `HTTP_MODE` | no | `https` | Marks the session cookie `Secure`. Leave it as `https` behind Railway's TLS. |
| `CORS_ORIGINS` | no | `https://${{RAILWAY_PUBLIC_DOMAIN}}` | Browser origins allowed to call the API. Upstream defaults to `*`; the template pins it to your own domain. |
| `DB_PATH`, `UPLOADS_DIR`, `LOG_DIR` | no | image defaults under `/data` | Must stay inside the volume. |
| `TZ` | no | `UTC` | Timezone used for dates. |
| `LOG_LEVEL` | no | `info` | `error`, `warn`, `info`, `http`, `verbose`, `debug`, `silly`. |
| `HOST` | no | **refused** | The wrapper pins the app to loopback and refuses to start if you try to move it. |
| `TRACKTOR_DISABLE_AUTH` | no | **refused** | Upstream's switch to turn off logins entirely. Refused, because on a public URL it publishes your records. |

Everything else in Tracktor's
[environment documentation](https://github.com/javedh-dev/tracktor/blob/main/docs/environment.md)
works as usual.

## Persistent paths

| Path | Contents | Backup |
|---|---|---|
| `/data` | `tracktor.db`, `uploads/`, `logs/` | `railway volume files download` |

## Local development

```bash
docker compose build
docker compose up -d
```

Then open http://127.0.0.1:8080 and sign in as `owner`. The compose file uses obvious
local-test-only secrets; do not reuse them.

Tests:

```bash
tests/static.sh       # syntax, shellcheck, pinning, the guards cannot be configured away
tests/smoke.sh        # cold start, registration closed, vehicle and fuel-log workflow, fail-fast
tests/persistence.sh  # vehicles and logs survive recreating the container
tests/railway-smoke.sh https://your-app.up.railway.app   # against a deployment
```

## Documentation

| File | Contents |
|---|---|
| [ARCHITECTURE.md](ARCHITECTURE.md) | what the wrapper does and why, boot sequence |
| [RAILWAY_TEMPLATE.md](RAILWAY_TEMPLATE.md) | exact template configuration |
| [SECURITY.md](SECURITY.md) | threat model, what is exposed, reporting |
| [UPSTREAM.md](UPSTREAM.md) | upstream provenance and how to bump it |
| [MAINTENANCE.md](MAINTENANCE.md) | release process and update checklist |
| [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) | licences of everything shipped |
| [MARKETPLACE_AUDIT.md](MARKETPLACE_AUDIT.md) | why this template was built |

## Licence

Wrapper code in this repository: MIT ([LICENSE](LICENSE)). Tracktor is MIT and Caddy is Apache-2.0;
see [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
