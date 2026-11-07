# syntax=docker/dockerfile:1.7
#
# FG-026: Forge-published PostgreSQL 18 (Debian-trixie-based). Preserves
# upstream `postgres:18` entrypoint — secrets-from-FILE, init.d SQL,
# shell-script maintenance hooks all work.
#
# Companion to `postgres-scratch-trixie:18` — this is the shelled variant
# consumers like homelab/nextcloud reach for when they need the full
# upstream behavior.

FROM postgres:18

ARG GIT_SHA=unknown
ARG BUILD_TIMESTAMP=unknown

LABEL org.opencontainers.image.source="https://github.com/bboortz/forge"
LABEL org.opencontainers.image.licenses="Apache-2.0"
LABEL org.opencontainers.image.description="Minimal, continuously patched PostgreSQL 18 (slim-trixie, Debian-based)"
LABEL org.opencontainers.image.revision="${GIT_SHA}"
LABEL org.opencontainers.image.created="${BUILD_TIMESTAMP}"

# sid pins live under images/postgres-slim-trixie/sid-pins/ — none at story-time.
COPY sid-pins/ /etc/apt/preferences.d/

# Upstream postgres:18 ships only `ssl-cert-snakeoil.pem` — add the Debian
# ca-certificates bundle so outbound TLS (replication, pg_restore from
# remote URLs, etc.) works without extra apt-installs in consumer Dockerfiles.
# hadolint ignore=DL3005
RUN set -eux; \
    apt-get update; \
    apt-get -y --no-install-recommends upgrade; \
    apt-get -y --no-install-recommends install ca-certificates; \
    rm -rf /var/lib/apt/lists/*
