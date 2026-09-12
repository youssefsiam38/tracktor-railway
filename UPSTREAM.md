# Upstream provenance

## Tracktor

| | |
|---|---|
| Project | [Tracktor](https://github.com/javedh-dev/tracktor) |
| Version deployed | 2.1.0 |
| Licence | MIT |
| Image | `ghcr.io/javedh-dev/tracktor:2.1.0` |
| Digest | `sha256:edb439550243e0c2589daf2a72fc51805e69cbd27462fc979128a4bb66292138` |
| Source for the tag | https://github.com/javedh-dev/tracktor/tree/2.1.0 |
| Platforms | linux/amd64, linux/arm64 |

## Caddy

| | |
|---|---|
| Project | [Caddy](https://github.com/caddyserver/caddy) |
| Version | 2.10.2 |
| Licence | Apache-2.0 |
| Image | `docker.io/library/caddy:2.10-alpine` |
| Digest | `sha256:4c6e91c6ed0e2fa03efd5b44747b625fec79bc9cd06ac5235a779726618e530d` |

Only the `caddy` binary is copied out of that image, in a build stage. It is a static Go binary, so
it runs unchanged on Tracktor's Alpine base.

## What this repository changes

Nothing in the application. The wrapper image is `FROM ghcr.io/javedh-dev/tracktor` plus:

| Added | Path | Why |
|---|---|---|
| Caddy binary | `/usr/local/bin/caddy` | refuses the registration route upstream leaves permanently open |
| entrypoint | `/usr/local/bin/tracktor-railway-entrypoint` | validation, config generation, readiness wait, supervision |
| bootstrap | `/usr/local/lib/tracktor-railway/bootstrap-owner.mjs` | claims the instance before it is reachable |
| licences | `/usr/share/licenses/tracktor-railway/` | MIT and Apache-2.0 texts shipped with the binary |
| `HOST=127.0.0.1`, `PORT=8080`, `TRACKTOR_INTERNAL_PORT=3000`, `HTTP_MODE=https` | env | keeps the app off the public interface, avoids the inherited port collision, marks cookies secure |
| OCI labels | image metadata | source, revision, version, upstream version, Caddy version |

No patches, no forks, no rebuilt assets.

## Licence obligations

Tracktor is MIT and Caddy is Apache-2.0. Both are permissive: redistributing the image requires
preserving their licence texts and notices, which the image does at
`/usr/share/licenses/tracktor-railway/`. The wrapper's own code is MIT.

## Bumping the upstream version

1. Find the new release at https://github.com/javedh-dev/tracktor/releases and read it for schema or
   configuration changes.
2. Resolve the new digest:
   ```bash
   docker buildx imagetools inspect ghcr.io/javedh-dev/tracktor:X.Y.Z --format '{{.Manifest.Digest}}'
   ```
3. Update `TRACKTOR_IMAGE` and `TRACKTOR_VERSION` in `Dockerfile`, plus the version tables in
   `README.md` and this file.
4. `tests/static.sh && docker compose build && tests/smoke.sh && tests/persistence.sh`.
5. Follow [MAINTENANCE.md](MAINTENANCE.md) to release and to update the template image.

**Check the auth middleware every time.** The whole reason this wrapper exists is
`BYPASS_PATHS` in `src/server/middlewares/auth.ts` covering `/api/auth`, and the absence of per-user
data scoping. If upstream closes registration after the first user, or scopes vehicles to accounts,
the proxy rule becomes unnecessary and the template should be simplified rather than left in place.
