# syntax=docker/dockerfile:1.7
#
# FG-046: shared builder-base image for every Forge-native from-Go-source
# image. Sibling to FG-025's forge-builder-trixie (Debian-base + syft).
# Pre-bakes:
#   - apt-get upgrade applied (trixie-security included)
#   - ca-certificates
#   - git + curl + jq (for upstream release resolution + source clone)
#   - syft (dpkg + go module cataloger)
#   - Go toolchain from golang:X-trixie (currently 1.27 — the newest
#     Debian-trixie-based official Go image)
#
# Daily cron (build.yml) rebuilds this first; derivatives pull it as a
# FROM reference. Bumping the Go major version is a single `GO_BASE` ARG
# update + a rebuild — all from-Go-source derivatives inherit the new
# stdlib without each needing their own Dockerfile change.
#
# Why this exists: Debian trixie's Go toolchain (go1.24.x) accumulates
# stdlib CVEs over its release lifetime. Downstream Debian-packaged Go
# binaries (prometheus-ipmi-exporter, prometheus-alertmanager, prometheus,
# prometheus-node-exporter) ship a vulnerable stdlib until Debian bumps
# their toolchain and rebuilds — which can lag by months. Building from
# source against a newer Go eliminates the lag.

ARG GO_BASE=golang:1.27-trixie
# syft via Docker Hub (not GitHub releases CDN — FG-025 observed GH flap).
ARG SYFT_SRC=docker.io/anchore/syft:latest

# --- Stage 0: syft source (Docker Hub) ---------------------------------------
FROM ${SYFT_SRC} AS syft-src

# --- Stage 1: builder base (Go + Debian) -------------------------------------
FROM ${GO_BASE}

ARG GIT_SHA=unknown
ARG BUILD_TIMESTAMP=unknown

LABEL org.opencontainers.image.source="https://github.com/bboortz/forge"
LABEL org.opencontainers.image.licenses="Apache-2.0"
LABEL org.opencontainers.image.description="Shared builder for Forge from-Go-source images — Go toolchain + apt-upgraded + CA certs + syft + git + jq"
LABEL org.opencontainers.image.revision="${GIT_SHA}"
LABEL org.opencontainers.image.created="${BUILD_TIMESTAMP}"

# apt-upgrade + base build deps.
# - git: shallow-clone upstream source
# - curl + jq: resolve latest-release tag at build time (FG-013 pattern)
# - ca-certificates: TLS verify for curl / git / go mod download
# Note: build-essential/g++ are deliberately NOT installed — if a specific
# derivative needs CGO, it apt-installs the toolchain itself. CGO is off
# for most Go images; forge-builder-go-trixie stays minimal.
# hadolint ignore=DL3008
RUN set -eux; \
    apt-get update; \
    apt-get -y --no-install-recommends upgrade; \
    apt-get -y --no-install-recommends install \
      ca-certificates git curl jq; \
    rm -rf /var/lib/apt/lists/*

# syft from Docker Hub.
COPY --from=syft-src /syft /usr/local/bin/syft
# Smoke the toolchain at build time so a broken image fails fast.
# pipefail set via SHELL to satisfy DL4006 on `syft version | head`.
SHELL ["/bin/bash", "-o", "pipefail", "-c"]
RUN syft version | head -1 && go version

WORKDIR /
