# Maintenance

## Release process

1. Update a pinned image (see [UPSTREAM.md](UPSTREAM.md)) or the wrapper scripts.
2. Run the full local suite:
   ```bash
   tests/static.sh && docker compose build && tests/smoke.sh && tests/persistence.sh
   ```
3. Commit on `main`. CI (`test.yml`) runs the same suite on every push and pull request.
4. Tag and push:
   ```bash
   git tag -a vX.Y.Z -m "tracktor-railway vX.Y.Z" && git push origin vX.Y.Z
   ```
   `publish-image.yml` builds an amd64 candidate, runs the suite against **that** image, and only
   then pushes the multi-arch image to `ghcr.io/youssefsiam38/tracktor-railway:X.Y.Z`.
5. Note the digest from the workflow summary.
6. Point the template at the new tag:
   ```bash
   npx -y @railway/cli@latest templates update tracktor --readme-file marketplace/OVERVIEW.md
   ```
   or patch the service image through the template editor. Railway's template generator rejects
   `@sha256:` references, so templates use the version tag; the tag is immutable in practice because
   releases never re-push an existing tag. The marketplace overview lives in
   `marketplace/OVERVIEW.md`; Railway validates its section headings, so keep them.
7. Write release notes recording the wrapper version, both upstream versions and the image digest.

## What to watch

| Thing | Where | Why |
|---|---|---|
| Tracktor releases | https://github.com/javedh-dev/tracktor/releases | schema changes, and above all whether registration and per-user scoping are fixed |
| `src/server/middlewares/auth.ts` | upstream | `BYPASS_PATHS` covering `/api/auth` is the reason the proxy rule exists |
| Caddy releases | https://github.com/caddyserver/caddy/releases | the proxy enforces the registration policy; keep it current |
| Railway template deploys | Railway dashboard | deploy failures show up as template health |

## Breaking-change checklist

Before releasing an upstream bump:

- [ ] Is `/api/auth/register` still reachable without a session? If upstream fixed it, drop the
      proxy rule rather than keeping a redundant one.
- [ ] Are vehicles now scoped to the account that created them? That changes the advice about who
      you let register.
- [ ] Does `/api/health` still exist and still answer without a session? The readiness wait and the
      platform healthcheck both depend on it.
- [ ] Does the registration endpoint still return 201 on success and 400 with "already exists"? The
      bootstrap reads both.
- [ ] Do the vehicle and fuel-log request bodies still require every nullable field? The test
      helpers send them all explicitly because upstream rejects omissions.
- [ ] `tests/railway-smoke.sh` green against a staging deploy, including the persistence run with
      `STATE_OUT` / `STATE_IN` across a redeploy.

## Rolling back

Templates pin a version tag, so a bad release is undone by pointing the template back at the
previous tag and redeploying. Data lives in `/data` and is untouched by an image rollback, provided
the newer version did not migrate the database forward.

## If this repository is abandoned

The template is a thin wrapper: fork it, change the GHCR path in the workflow and the template, and
publish your own. Nothing here depends on this account.
