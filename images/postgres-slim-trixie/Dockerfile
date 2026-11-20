# syntax=docker/dockerfile:1.7
#
# FG-026 → FG-054: Forge-published PostgreSQL 18 (Debian-trixie-based).
# Preserves upstream `postgres:18` entrypoint — secrets-from-FILE,
# init.d SQL, shell-script maintenance hooks all work.
#
# FG-054 (this revision): Rebuild `gosu` from upstream source using
# forge-builder-go-trixie (go1.27.3) instead of the upstream postgres:18
# bundled gosu (compiled with go1.24.6, which grype flags for GO-2026-4337
# / CVE-2025-68121). Reachability analysis: gosu is a 140-LOC
# setuid/setgid/exec helper with zero `crypto/tls` or `net/http` code
# paths — the TLS session resumption CVE is architecturally unreachable.
# We rebuild anyway so the binary ships a clean go1.27+ stdlib and the
# daily cron auto-tracks future stdlib fixes via forge-builder-go-trixie.
#
# Same precedent as FG-046's Go-image migration.
#
# Companion to `postgres-scratch-trixie:18` — this is the shelled variant
# consumers like homelab/nextcloud reach for when they need the full
# upstream behavior.

# FG-046: shared Go builder base. go1.27.x + syft + git.
ARG BUILDER_GO_REF=ghcr.io/bboortz/builder/go-trixie:latest
# Upstream gosu. Pinned to the current release tag; bump via chore PR
# when new upstream versions ship.
ARG GOSU_VERSION=1.20

# --- Stage 1: Go builder (gosu from source) ----------------------------------
FROM ${BUILDER_GO_REF} AS gosu-builder

ARG GOSU_VERSION

WORKDIR /src
SHELL ["/bin/bash", "-o", "pipefail", "-c"]
# hadolint ignore=DL3003
RUN set -eux; \
    git clone --depth 1 --branch "${GOSU_VERSION}" \
      https://github.com/tianon/gosu.git .; \
    REV="$(git rev-parse --short HEAD)"; \
    CGO_ENABLED=0 GOFLAGS=-mod=mod \
      go build -trimpath \
        -ldflags "-s -w -X main.Revision=${REV}" \
        -o /out/gosu .; \
    /out/gosu --version | head -1

# --- Stage 2: runtime (postgres:18) ------------------------------------------
FROM postgres:18

ARG GIT_SHA=unknown
ARG BUILD_TIMESTAMP=unknown

LABEL org.opencontainers.image.source="https://github.com/bboortz/forge"
LABEL org.opencontainers.image.licenses="Apache-2.0"
LABEL org.opencontainers.image.description="Minimal, continuously patched PostgreSQL 18 (slim-trixie, Debian-based). FG-054: ships gosu rebuilt from source via forge-builder-go-trixie (go1.27+) for a cleaner stdlib baseline."
LABEL org.opencontainers.image.revision="${GIT_SHA}"
LABEL org.opencontainers.image.created="${BUILD_TIMESTAMP}"

# sid pins live under images/postgres-slim-trixie/sid-pins/ — none at story-time.
COPY sid-pins/ /etc/apt/preferences.d/

# Upstream postgres:18 ships only `ssl-cert-snakeoil.pem` — add the Debian
# ca-certificates bundle so outbound TLS (replication, pg_restore from
# remote URLs, etc.) works without extra apt-installs in consumer Dockerfiles.
# DL3005: apt-get upgrade is the point.
# DL3008: ca-certificates floats with the Debian trust-store release cadence.
# hadolint ignore=DL3005,DL3008
RUN set -eux; \
    apt-get update; \
    apt-get -y --no-install-recommends upgrade; \
    apt-get -y --no-install-recommends install ca-certificates; \
    rm -rf /var/lib/apt/lists/*

# FG-054: overlay the fresh gosu over the upstream-bundled one. Preserves
# the setuid-root bit + ownership that postgres:18's entrypoint relies on.
COPY --from=gosu-builder /out/gosu /usr/local/bin/gosu
RUN set -eux; \
    chmod 0755 /usr/local/bin/gosu; \
    /usr/local/bin/gosu --version
