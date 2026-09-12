# syntax=docker/dockerfile:1
#
# tracktor-railway: thin wrapper around the official Tracktor image.
#
# Tracktor has real username/password authentication, but two things make it unsafe on a public URL
# as shipped:
#
#   1. Its auth middleware bypasses every path under /api/auth, and /api/auth/register lives there,
#      so anyone can create an account at any time -- not just before the first user exists.
#   2. Accounts are not scoped to data. Every user sees every vehicle, including VIN and licence
#      plate.
#
# Together those mean a stranger who finds the URL can self-register and read or edit the whole
# garage. This wrapper creates the owner account before the public listener opens and blocks the
# registration route at the proxy. Application code is unchanged.
#
# Both images are pinned by tag AND digest. Update the image and version args together.
ARG CADDY_IMAGE=docker.io/library/caddy:2.10-alpine@sha256:4c6e91c6ed0e2fa03efd5b44747b625fec79bc9cd06ac5235a779726618e530d
ARG TRACKTOR_IMAGE=ghcr.io/javedh-dev/tracktor:2.1.0@sha256:edb439550243e0c2589daf2a72fc51805e69cbd27462fc979128a4bb66292138

FROM ${CADDY_IMAGE} AS caddy

FROM ${TRACKTOR_IMAGE}

ARG TRACKTOR_VERSION=2.1.0
ARG CADDY_VERSION=2.10.2
ARG WRAPPER_VERSION=0.0.0-dev
ARG VCS_REF=unknown
ARG BUILD_DATE=1970-01-01T00:00:00Z

# Caddy ships as a static Go binary, so the alpine-built one runs here unchanged.
COPY --from=caddy /usr/bin/caddy /usr/local/bin/caddy
COPY licenses/ /usr/share/licenses/tracktor-railway/
COPY --chmod=0755 scripts/entrypoint.sh /usr/local/bin/tracktor-railway-entrypoint
COPY scripts/bootstrap-owner.mjs /usr/local/lib/tracktor-railway/bootstrap-owner.mjs
RUN caddy version \
    && chmod 755 /usr/local/lib/tracktor-railway \
    && chmod 644 /usr/local/lib/tracktor-railway/bootstrap-owner.mjs \
    && node --check /usr/local/lib/tracktor-railway/bootstrap-owner.mjs \
    && mkdir -p /etc/tracktor-railway

# The app listens on loopback; Caddy holds the public port. The upstream image sets PORT=3000, the
# app's own port, which would collide with the internal listener here, so it is replaced with a
# public default. A platform that sets PORT overrides this, which is exactly what should happen.
ENV HOST=127.0.0.1 \
    PORT=8080 \
    TRACKTOR_INTERNAL_PORT=3000 \
    HTTP_MODE=https

LABEL org.opencontainers.image.title="tracktor-railway" \
      org.opencontainers.image.description="Community Railway wrapper for Tracktor, the vehicle maintenance and fuel logbook. Closes open registration. Not affiliated with the Tracktor project." \
      org.opencontainers.image.source="https://github.com/youssefsiam38/tracktor-railway" \
      org.opencontainers.image.url="https://github.com/youssefsiam38/tracktor-railway" \
      org.opencontainers.image.documentation="https://github.com/youssefsiam38/tracktor-railway#readme" \
      org.opencontainers.image.licenses="MIT" \
      org.opencontainers.image.version="${WRAPPER_VERSION}" \
      org.opencontainers.image.revision="${VCS_REF}" \
      org.opencontainers.image.created="${BUILD_DATE}" \
      org.opencontainers.image.base.name="ghcr.io/javedh-dev/tracktor:${TRACKTOR_VERSION}" \
      io.tracktor-railway.upstream.version="${TRACKTOR_VERSION}" \
      io.tracktor-railway.caddy.version="${CADDY_VERSION}"

EXPOSE 3000

ENTRYPOINT ["/usr/local/bin/tracktor-railway-entrypoint"]
CMD ["node", "build"]
