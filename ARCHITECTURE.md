# Architecture

## Service graph

```
                internet
                   │  https
                   ▼
   ┌───────────────────────────────────┐
   │  tracktor  (public)               │
   │                                   │
   │   Caddy  :$PORT                   │  403 on /api/auth/register
   │     │  reverse proxy              │
   │     ▼                             │
   │   Tracktor  127.0.0.1:3000        │  SvelteKit, own sessions
   │   volume /data                    │  SQLite + uploads + logs
   └───────────────────────────────────┘
```

One service, one volume. Tracktor keeps the database, uploads and logs under `/data`, which suits
Railway's one-volume-per-service model.

## Why a wrapper image

Tracktor has proper authentication: usernames, bcrypt password hashes, and session cookies. Two
things still make it unsafe on a public URL as shipped.

**Registration never closes.** The auth middleware decides what needs a session like this:

```ts
const BYPASS_PATHS = ['/api/auth', '/api/health', '/api/config/branding'];
```

`/api/auth/register` starts with `/api/auth`, so it is bypassed — not only while the instance has no
users, but forever. `createUser` rejects a duplicate username and nothing else. Verified against the
stock image: registering a second account after the first one exists returns 201.

**Accounts are not scoped to data.** Every user sees every vehicle. Verified the same way: a second
account listed the first account's vehicle, with its VIN and licence plate.

Put together, a stranger who finds a public Tracktor can sign themselves up and read or edit the
whole garage. The wrapper closes both halves of that:

1. Validate variables. Names, lengths and outcomes are printed; values never are.
2. Refuse configurations that would undo the guards:
   - a `HOST` that is not loopback, which would let requests reach the app without passing the proxy;
   - `TRACKTOR_DISABLE_AUTH=true`, which removes logins altogether;
   - a missing or short `TRACKTOR_OWNER_PASSWORD`;
   - a `PORT` that collides with the app's internal port.
3. Start Tracktor on loopback and wait for its health route.
4. Create the owner account through Tracktor's own registration endpoint, so the instance is claimed
   before anyone outside can reach it. Idempotent: an existing account is left alone, which is what
   makes changing your password in the app safe.
5. Open the public listener, with `/api/auth/register` answering 403 unless
   `TRACKTOR_ALLOW_REGISTRATION=true`.
6. Supervise both processes. If either exits, the container exits and Railway restarts it.

Application code is untouched. The image adds Caddy, an entrypoint, a bootstrap script, the licence
files and OCI labels on top of the upstream image.

## Why a proxy rather than a patch

Blocking one route at the proxy leaves the application binary exactly as upstream published it, so
an upstream bump is a digest change rather than a re-patch. It is also observable: the route returns
a plain 403 with a readable message, and the smoke test asserts it.

The alternative, editing the middleware's bypass list, would mean maintaining a fork of a moving
target for a single-line policy difference.

## Boot sequence

```
entrypoint ─► validate variables
              write and validate the Caddyfile
           ─► start Tracktor on 127.0.0.1:3000
              poll /api/health until it answers
           ─► create the owner account (first boot only)
           ─► start Caddy on :$PORT, registration route closed
              poll both children; either exit brings the container down
```

## Ports

| Port | Bound to | Purpose |
|---|---|---|
| `$PORT` (8080 by default) | all interfaces | Caddy, the only thing the outside world talks to |
| `3000` | 127.0.0.1 | Tracktor itself, unreachable from outside the container |

The upstream image sets `PORT=3000`, its own listening port. Left alone that collides with the
internal listener here, so the wrapper image replaces it with a public default of 8080; a platform
that sets `PORT` overrides it, which is exactly what should happen. This matters on Railway for a
second reason: the healthcheck is probed against the value of `PORT`, defaulting to 8080, while
public traffic goes to the domain's target port, so the two must agree.

## Cookies and origins

`HTTP_MODE=https` is baked into the image so Tracktor marks its session cookie `Secure`, which is
correct behind Railway's TLS termination. The template also pins `CORS_ORIGINS` to the deployment's
own domain; upstream defaults to `*`.

## Health and readiness

The healthcheck is `GET /api/health` through the public port. That route is unauthenticated
upstream and is not proxied away, so the platform probe works without credentials. It passes only
after Caddy is listening, and Caddy starts only after the owner account exists, so a passing
healthcheck implies a claimed, protected instance.
