# Third-party notices

This template deploys software written by other people. Their licences apply to what runs; the
wrapper code in this repository is MIT.

## Shipped inside the wrapper image

| Component | Version | Licence | Source |
|---|---|---|---|
| Tracktor | 2.1.0 | MIT | https://github.com/javedh-dev/tracktor/tree/2.1.0 |
| Caddy | 2.10.2 | Apache-2.0 | https://github.com/caddyserver/caddy |

The licence texts are in [`licenses/`](licenses) and inside the image at
`/usr/share/licenses/tracktor-railway/`.

Tracktor bundles its own npm dependencies (SvelteKit, Drizzle, better-sqlite3 and others) under
their respective licences; they are unchanged from the upstream image and their metadata ships with
it. Caddy is distributed as a single static binary that embeds its own Go dependencies, likewise
unchanged.

## Licence obligations

Both licences are permissive and require preserving the copyright notice and licence text, which
the image does. Neither has a network clause, so running the service creates no additional
obligation.

## Trademarks and artwork

The marketplace card uses Tracktor's own icon; see [`assets/README.md`](assets/README.md). This
template is not affiliated with, endorsed by, or supported by the Tracktor project.

## This repository

MIT — see [LICENSE](LICENSE). It contains no upstream source code.
