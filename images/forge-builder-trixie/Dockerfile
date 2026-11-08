# syntax=docker/dockerfile:1.7
#
# FG-025: shared builder stage for every Forge-native scratch image.
# Pre-bakes apt-get upgrade + ca-certificates + syft so each scratch
# derivative's Dockerfile doesn't re-run this ~30-60s of work.
#
# Daily cron (build.yml) rebuilds this first so a fresh apt-upgrade
# propagates to all derivatives within 24h.
#
# Not a runtime image — not FROM scratch. Intended as a builder base
# only: `FROM ghcr.io/bboortz/forge-builder-trixie:<tag> AS builder`.

ARG DEBIAN_BASE=python:3.13-slim-trixie

FROM ${DEBIAN_BASE}

ARG GIT_SHA=unknown
ARG BUILD_TIMESTAMP=unknown

LABEL org.opencontainers.image.source="https://github.com/bboortz/forge"
LABEL org.opencontainers.image.licenses="Apache-2.0"
LABEL org.opencontainers.image.description="Shared builder for Forge scratch images — apt-upgraded + CA certs + syft"
LABEL org.opencontainers.image.revision="${GIT_SHA}"
LABEL org.opencontainers.image.created="${BUILD_TIMESTAMP}"

# hadolint ignore=DL3005,DL3008
RUN set -eux; \
    apt-get update; \
    apt-get -y --no-install-recommends upgrade; \
    apt-get -y --no-install-recommends install ca-certificates curl; \
    rm -rf /var/lib/apt/lists/*

# Install syft so every scratch derivative's builder stage can emit an
# embedded SBOM (FG-020) without re-downloading the tool per build.
# Retry wrapper: GitHub's releases/download/* CDN flaps 504 periodically
# (observed 2026-11-08). 10 attempts, capped at 60s backoff each.
ARG SYFT_VERSION=v1.57.0
# hadolint ignore=DL4006
RUN set -eux; \
    for attempt in 1 2 3 4 5 6 7 8 9 10; do \
      if curl -sSfL --max-time 60 "https://raw.githubusercontent.com/anchore/syft/main/install.sh" \
         | sh -s -- -b /usr/local/bin "${SYFT_VERSION}" \
         && [ -x /usr/local/bin/syft ]; then \
        break; \
      fi; \
      if [ "${attempt}" = "10" ]; then \
        echo "syft install failed after 10 attempts" >&2; exit 1; \
      fi; \
      delay=$((attempt * 6)); [ "${delay}" -gt 60 ] && delay=60; \
      echo "syft install attempt ${attempt}/10 failed; retrying in ${delay}s" >&2; \
      sleep "${delay}"; \
    done; \
    apt-get -y --purge --auto-remove remove curl; \
    syft version

# Explicit WORKDIR to keep subsequent derivatives from inheriting a
# surprising cwd.
WORKDIR /
