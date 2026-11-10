# syntax=docker/dockerfile:1.7
#
# FG-025 + FG-042: shared builder stage for every Forge-native scratch
# image. Pre-bakes apt-get upgrade + ca-certificates + syft so each
# scratch derivative's Dockerfile doesn't re-run this ~30-60s of work.
#
# FG-042: FROMs ghcr.io/bboortz/python-slim-trixie (dogfood) instead of
# python:3.14-slim-trixie upstream. Benefits: version drift between
# forge-builder-trixie and python-slim-trixie is now structurally
# impossible (one bump propagates atomically), fewer Docker Hub digest
# re-resolves per daily cron, scanner sees a single forge-signed base.
#
# Daily cron (build.yml) rebuilds this in the publish-builders tier
# (after publish-pre-builders has published python-slim-trixie). The
# apt-upgrade in python-slim-trixie flows through; we don't redo it
# here (just add syft + ca-certificates on top).
#
# Not a runtime image — not FROM scratch. Intended as a builder base
# only: `FROM ghcr.io/bboortz/forge-builder-trixie:<tag> AS builder`.

# FG-042: resolve at build time to forge-local during local builds,
# ghcr.io/bboortz/python-slim-trixie:latest in CI. See
# scripts/build-image.sh PYTHON_SLIM_REF resolution.
ARG PYTHON_SLIM_REF=ghcr.io/bboortz/python-slim-trixie:latest
# syft is pulled from Docker Hub rather than GitHub release CDN
# (observed 2026-11-08: GitHub's releases/download/* flapped 504s for
# ~6 min at a time; Docker Hub is a separate CDN and stayed up).
ARG SYFT_SRC=docker.io/anchore/syft:latest

# --- Stage 0: syft source (Docker Hub) ---------------------------------------
FROM ${SYFT_SRC} AS syft-src

# --- Stage 1: builder base (python-slim-trixie dogfood per FG-042) ----------
FROM ${PYTHON_SLIM_REF}

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
    apt-get -y --no-install-recommends install ca-certificates; \
    rm -rf /var/lib/apt/lists/*

# syft from the Docker Hub image — static Go binary at /syft in the image.
COPY --from=syft-src /syft /usr/local/bin/syft
RUN syft version

# Explicit WORKDIR to keep subsequent derivatives from inheriting a
# surprising cwd.
WORKDIR /
