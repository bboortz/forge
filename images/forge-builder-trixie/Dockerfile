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
# syft is pulled from Docker Hub rather than GitHub release CDN
# (observed 2026-11-08: GitHub's releases/download/* flapped 504s for
# ~6 min at a time; Docker Hub is a separate CDN and stayed up).
ARG SYFT_SRC=docker.io/anchore/syft:latest

# --- Stage 0: syft source (Docker Hub) ---------------------------------------
FROM ${SYFT_SRC} AS syft-src

# --- Stage 1: builder base (Debian) ------------------------------------------
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
    apt-get -y --no-install-recommends install ca-certificates; \
    rm -rf /var/lib/apt/lists/*

# syft from the Docker Hub image — static Go binary at /syft in the image.
COPY --from=syft-src /syft /usr/local/bin/syft
RUN syft version

# Explicit WORKDIR to keep subsequent derivatives from inheriting a
# surprising cwd.
WORKDIR /
