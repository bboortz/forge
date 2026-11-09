# syntax=docker/dockerfile:1.7
#
# FG-045: Uptime Kuma 2.5.9 on debian:trixie-slim via node:22-trixie-slim.
# Built from source because uptime-kuma isn't in Debian trixie (upstream
# only ships `louislam/uptime-kuma:*`, 1.6 GB, Debian 12 bookworm base,
# includes Chromium for browser-based synthetic monitors).
#
# Forge variant deliberately drops Chromium (saves ~200 MB). HTTP/TCP/
# Push/DNS/Ping probes all still work. Browser-based monitors (Playwright)
# are out of scope — if an operator needs them, add a sibling
# `uptime-kuma-browser-slim-trixie` later.
#
# Shell + apt KEPT at runtime (slim contract — see image.has-shell CAP).
# Runs as nonroot uid 1000 (upstream's `node` user convention).

ARG NODE_BASE=node:22-trixie-slim
# FG-031: /hc for docker-native HEALTHCHECK.
ARG HC_REF=ghcr.io/bboortz/hc:0.1.0
# syft binary via Docker Hub (same precedent as forge-builder-trixie).
ARG SYFT_SRC=docker.io/anchore/syft:latest
# Track upstream's latest GitHub release. Empty default → build-time
# resolves via GitHub API (FG-013 pattern). Pin to an exact tag by passing
# --build-arg UPTIME_KUMA_VERSION=2.5.9 for reproducible local builds.
ARG UPTIME_KUMA_VERSION=

# --- Stage 0: hc source ------------------------------------------------------
FROM ${HC_REF} AS hc

# --- Stage 1: syft source ----------------------------------------------------
FROM ${SYFT_SRC} AS syft-src

# --- Stage 2: Node builder (npm ci + emit SBOM) -----------------------------
FROM ${NODE_BASE} AS builder

ARG UPTIME_KUMA_VERSION

# git + curl + jq for clone + release resolution. make/g++/python3 are
# safety-net for native-dep rebuilds (@louislam/sqlite3 ships prebuilt
# binaries for amd64 so no compile needed in practice, but keep them so
# a future dep switch doesn't fail silently).
# hadolint ignore=DL3008
RUN set -eux; \
    apt-get update; \
    apt-get -y --no-install-recommends upgrade; \
    apt-get -y --no-install-recommends install \
      git curl jq ca-certificates make g++ python3 dumb-init; \
    rm -rf /var/lib/apt/lists/*

COPY --from=syft-src /syft /usr/local/bin/syft

WORKDIR /src
# Resolve the target tag: use UPTIME_KUMA_VERSION if provided, else fetch
# upstream's latest GitHub release at build time. Shallow clone at that
# tag. Bake the resolved tag + sha into /tmp for the labels step.
# pipefail set via SHELL (DL4006); cd into /src for the clone is
# intentional (DL3003).
SHELL ["/bin/bash", "-o", "pipefail", "-c"]
# hadolint ignore=DL3003
RUN set -eux; \
    TARGET_REF="${UPTIME_KUMA_VERSION}"; \
    if [ -z "${TARGET_REF}" ]; then \
      TARGET_REF="$(curl -fsSL \
        https://api.github.com/repos/louislam/uptime-kuma/releases/latest \
        | jq -r '.tag_name // empty')"; \
      [ -n "${TARGET_REF}" ] || { echo "could not resolve latest release" >&2; exit 1; }; \
    fi; \
    echo "${TARGET_REF}" > /tmp/target-ref; \
    git clone --depth 1 --branch "${TARGET_REF}" \
      https://github.com/louislam/uptime-kuma.git .; \
    GIT_REVISION="$(git rev-parse --short HEAD)"; \
    echo "${GIT_REVISION}" > /tmp/git-revision

# Install FULL deps (incl. devDependencies) so `vite build` can run.
# PUPPETEER_SKIP_CHROMIUM_DOWNLOAD=1 is upstream's own escape hatch.
# PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD=1 handles the Playwright side.
ENV PUPPETEER_SKIP_CHROMIUM_DOWNLOAD=1 \
    PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD=1 \
    NPM_CONFIG_AUDIT=false \
    NPM_CONFIG_FUND=false
RUN set -eux; \
    npm ci

# Build the Vue SPA into /src/dist/. The server serves dist/index.html at
# :3001/ once the compile is complete.
RUN set -eux; \
    npm run build

# Prune dev deps after the frontend has been built. Shrinks node_modules
# from ~450 MB to ~250 MB.
RUN set -eux; \
    npm prune --omit=dev

# Stage overlay: just /app (uptime-kuma's single app tree).
RUN set -eux; \
    mkdir -p /out/app /out/app/data; \
    cp -a /src/. /out/app/; \
    # Drop obvious build-time cruft that doesn't belong at runtime.
    rm -rf /out/app/.git /out/app/.github /out/app/docker /out/app/test \
           /out/app/node_modules/.cache

# SBOM — dpkg (base layer) + npm (node_modules graph).
RUN syft scan dir:/src/ -o cyclonedx-json > /sbom.json

# --- Stage 3: runtime (node:22-trixie-slim) ---------------------------------
FROM ${NODE_BASE}

ARG GIT_SHA=unknown
ARG BUILD_TIMESTAMP=unknown

LABEL org.opencontainers.image.source="https://github.com/bboortz/forge"
LABEL org.opencontainers.image.licenses="MIT"
LABEL org.opencontainers.image.description="Minimal, continuously patched Uptime Kuma (slim-trixie runtime; shell + apt kept; Chromium / browser monitors deliberately excluded — use the louislam upstream image if you need those)"
LABEL org.opencontainers.image.revision="${GIT_SHA}"
LABEL org.opencontainers.image.created="${BUILD_TIMESTAMP}"
# Note: image.version here refers to Forge's variant tag ("latest").
# Upstream's resolved uptime-kuma version is baked in via the "about"
# page / server/version.json inside the shipped /app tree.

COPY sid-pins/ /etc/apt/preferences.d/

# Fresh apt-upgrade (daily cron). ca-certificates for outbound HTTPS probes.
# dumb-init for proper PID 1 signal forwarding (upstream convention).
# hadolint ignore=DL3008
RUN set -eux; \
    apt-get update; \
    apt-get -y --no-install-recommends upgrade; \
    apt-get -y --no-install-recommends install ca-certificates dumb-init; \
    rm -rf /var/lib/apt/lists/*

COPY --from=builder /out/app /app
COPY --from=builder /sbom.json /sbom.json

# FG-031: /hc from the pinned hc image.
COPY --from=hc /hc /hc

# The upstream `node` user already exists in node:22-trixie-slim (uid 1000).
# Transfer ownership of /app and /app/data.
RUN set -eux; \
    chown -R node:node /app

WORKDIR /app
# hadolint ignore=DL3002,DL3066
USER node

EXPOSE 3001

# Writable sqlite data dir (consumers typically mount a named volume here).
VOLUME ["/app/data"]

# FG-031: self-healthcheck via /hc → /api/entry-page (always 200 whether
# the setup wizard is active or the app is fully configured). GET / is
# a 302 redirect to /setup-database pre-config, so /hc default (200-only)
# would flap; /api/entry-page is an Express JSON handler that stays 200.
HEALTHCHECK --interval=30s --timeout=5s --start-period=30s --retries=5 \
  CMD ["/hc", "-t", "3", "http://127.0.0.1:3001/api/entry-page"]

ENTRYPOINT ["/usr/bin/dumb-init", "--"]
CMD ["node", "server/server.js"]
