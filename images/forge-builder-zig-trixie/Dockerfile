# syntax=docker/dockerfile:1.7
#
# FG-072: shared builder-base image for every Forge-native from-Zig-source
# image. Sibling of FG-025's forge-builder-python-trixie, FG-046's
# forge-builder-go-trixie, and FG-048's forge-builder-node-trixie.
#
# Dogfoods zig-slim-trixie (FG-072's new pre-builder) per the FG-065
# arch.language-family-image-pair invariant — every language family ships
# a <lang>-slim-trixie + forge-builder-<lang>-trixie pair, with the
# builder FROMing the pre-builder.
#
# Pre-bakes:
#   - Debian trixie (via debian-slim-trixie ← zig-slim-trixie chain)
#   - apt-upgrade applied (trixie-security included)
#   - ca-certificates
#   - git + curl + jq (for upstream release resolution + source clone)
#   - syft (dpkg + source-dir cataloger) via mirror/syft (FG-066)
#   - Zig toolchain from zig-slim-trixie (currently 0.17.1 — matches
#     hc's Zig toolchain; see ZIG_VERSION ARG in images/zig-slim-
#     trixie/Dockerfile)
#
# Daily cron (build.yml) rebuilds `zig-slim-trixie` first (publish-pre-
# builders tier) → this image rebuilds in publish-builders tier → every
# downstream Zig-source derivative picks up the fresh toolchain within
# 24h. Bumping the Zig version is a two-line update in zig-slim-trixie's
# Dockerfile (ZIG_VERSION + ZIG_SHA256) — all forge-rooted consumers
# inherit via the chain.
#
# Current consumers (post-FG-072): zero. Pair lands ahead of the first
# Zig source build (hc migration into forge — tracked as a follow-up FG).

ARG ZIG_SLIM_REF=ghcr.io/bboortz/pre-builder/zig-slim-trixie:latest
# FG-066: syft via forge-signed mirror (previously docker.io/anchore/syft).
ARG SYFT_REF=ghcr.io/bboortz/mirror/syft:latest

# --- Stage 0: syft source (forge mirror) -------------------------------------
FROM ${SYFT_REF} AS syft-src

# --- Stage 1: builder base (Zig + Debian) ------------------------------------
FROM ${ZIG_SLIM_REF}

ARG GIT_SHA=unknown
ARG BUILD_TIMESTAMP=unknown

LABEL org.opencontainers.image.source="https://github.com/bboortz/forge"
LABEL org.opencontainers.image.licenses="Apache-2.0"
LABEL org.opencontainers.image.description="Shared builder for Forge from-Zig-source images — Zig toolchain + apt-upgraded + CA certs + syft + git + curl + jq"
LABEL org.opencontainers.image.revision="${GIT_SHA}"
LABEL org.opencontainers.image.created="${BUILD_TIMESTAMP}"

# apt-upgrade + base build deps.
# - git: shallow-clone upstream source (hc, future Zig-based tools)
# - curl + jq: resolve latest-release tag at build time (FG-013 pattern)
# - ca-certificates: TLS verify for curl / git
# Note: build-essential/g++ are deliberately NOT installed — Zig has its
# own C/C++ compiler frontend (`zig cc`). If a specific derivative needs
# a native toolchain for a vendored C dep, it apt-installs the toolchain
# itself. Mirrors forge-builder-go-trixie's minimalism.
# hadolint ignore=DL3008
RUN set -eux; \
    apt-get update; \
    apt-get -y --no-install-recommends upgrade; \
    apt-get -y --no-install-recommends install \
      ca-certificates git curl jq; \
    rm -rf /var/lib/apt/lists/*

# syft from forge-signed mirror (FG-066).
COPY --from=syft-src /syft /usr/local/bin/syft
# Smoke the toolchain at build time so a broken image fails fast.
# pipefail set via SHELL to satisfy DL4006 on `syft version | head`.
SHELL ["/bin/bash", "-o", "pipefail", "-c"]
RUN syft version | head -1 && zig version

WORKDIR /
