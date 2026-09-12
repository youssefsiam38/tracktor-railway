# Railway template configuration

The published template. Reproduce it from this file if it ever has to be rebuilt.

| | |
|---|---|
| Name | Tracktor |
| Code | `tracktor` |
| Category | Other |
| Image | `ghcr.io/youssefsiam38/tracktor-railway:<version>` |
| Icon | `assets/icon.png` |
| Overview markdown | `marketplace/OVERVIEW.md` (Railway enforces its section headings) |

## Service `tracktor` — public

| Field | Value |
|---|---|
| Source | `ghcr.io/youssefsiam38/tracktor-railway:<version>` |
| Port | 8080 |
| Domain | generated, target port 8080 |
| Healthcheck | `/api/health` |
| Volume | `/data` |
| Restart policy | on failure, 10 retries |

| Variable | Value |
|---|---|
| `TRACKTOR_OWNER_USERNAME` | `owner` |
| `TRACKTOR_OWNER_PASSWORD` | `${{secret(24)}}` |
| `APP_SECRET` | `${{secret(64, "abcdef0123456789")}}` |
| `CORS_ORIGINS` | `https://${{RAILWAY_PUBLIC_DOMAIN}}` |
| `HTTP_MODE` | `https` |
| `PORT` | `8080` |
| `TZ` | `UTC` |

## Notes

- Every variable has a value or a generator, so `railway deploy -t tracktor` works without a TTY.
- **The healthcheck path must be `/api/health`.** `/` redirects to the login page and the rest of
  the API answers 401, neither of which Railway treats as healthy.
- **`PORT` and the domain's target port must match.** Railway runs its healthcheck against the
  value of `PORT`, defaulting to 8080. A service that serves the public domain perfectly still
  fails to deploy if nothing listens on `PORT`.
- Do not add `HOST`. The image pins the app to loopback and the wrapper refuses to start if that is
  overridden, because every request must pass the proxy that closes registration.
- Do not add `TRACKTOR_DISABLE_AUTH`. The wrapper refuses it.
- The volume mount path must be `/data`, which is where the image's `DB_PATH`, `UPLOADS_DIR` and
  `LOG_DIR` all point.
- There is no second service and nothing on the private network.
