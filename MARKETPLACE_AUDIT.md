# Marketplace audit

Why this template was built, recorded at the time of publication.

## Gap

Searching the Railway marketplace returned nothing for vehicle maintenance or fuel logging:

| Query | Result |
|---|---|
| `tracktor` | no match |
| `vehicle`, `car`, `fuel`, `mileage` | no match |

The scan covered roughly seventy self-hosted applications. Most popular categories are already
served several times over; this one is empty.

## Why Tracktor

- Actively maintained, tagged releases, official multi-arch images on GHCR.
- MIT, so redistribution is simple and the obligations are minimal.
- Self-contained: SQLite in one directory, no companion database.
- Fits Railway's model exactly: one public HTTP service with one volume.
- Worth hosting rather than running locally, because the natural moment to record a fill-up is
  standing at the pump with a phone.

## Why it needs a template rather than a raw image

- **Registration never closes.** Upstream's auth middleware bypasses everything under `/api/auth`,
  and `/api/auth/register` is there, so the endpoint keeps accepting accounts forever. Verified
  against the stock image.
- **Accounts are not scoped to data**, so one self-registered stranger sees every vehicle, VIN and
  licence plate. Verified the same way.
- A fresh instance has no accounts at all, so the first visitor to a public URL claims it.
- The upstream image sets `PORT` to the app's own port, which collides with a proxy in front of it.
- Session cookies are not marked `Secure` unless `HTTP_MODE=https` is set, and `CORS_ORIGINS`
  defaults to `*`.

The template answers all five without asking the deployer anything.

## Category

Other — the marketplace has no personal-records or automotive category; the template is a
self-hosted personal database with a web UI.
