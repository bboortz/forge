# syntax=docker/dockerfile:1.7
#
# FG-065: forge-rooted Go 1.27 toolchain slim base. Published pre-builder;
# `forge-builder-go-trixie` FROMs this instead of `golang:1.27-trixie`
# directly (dogfood — same shape as `forge-builder-python-trixie` FROMing
# `python-slim-trixie` per FG-042). Future Go runtime images (none today;
# Go produces static binaries so the typical scratch + overlay suffices)
# can FROM this too.
#
# Current consumers (post-FG-065):
#   - forge-builder-go-trixie (builder base; dogfood)
#
# Note: Go doesn't currently have a "slim runtime" consumer in the fleet
# (unlike node-slim-trixie which is uptime-kuma-slim-trixie's runtime).
# This image's justification is the FG-065 "every language family ships
# both a pre-builder and a builder" invariant — the builder dogfoods it.
#
# Literal FROM (not ARG-indirected) so FG-042's upstream-grep invariant
# in `scripts/verify-no-upstream-drift.sh` catches future drift.
# Mirrors debian-slim-trixie / node-slim-trixie / python-slim-trixie
# convention.

FROM golang:1.27-trixie

ARG GIT_SHA=unknown
ARG BUILD_TIMESTAMP=unknown

LABEL org.opencontainers.image.source="https://github.com/bboortz/forge"
LABEL org.opencontainers.image.licenses="Apache-2.0"
LABEL org.opencontainers.image.description="Forge-rooted Go 1.27 toolchain slim base — apt-upgraded + CA certs + dumb-init, dogfooded by forge-builder-go-trixie per FG-065 (language-family image-pair invariant)"
LABEL org.opencontainers.image.revision="${GIT_SHA}"
LABEL org.opencontainers.image.created="${BUILD_TIMESTAMP}"

COPY sid-pins/ /etc/apt/preferences.d/

# ca-certificates for outbound HTTPS (module proxy, github.com, etc.),
# dumb-init for proper PID 1 signal forwarding in downstream consumers.
# hadolint ignore=DL3005,DL3008
RUN set -eux; \
    apt-get update; \
    apt-get -y --no-install-recommends upgrade; \
    apt-get -y --no-install-recommends install ca-certificates dumb-init; \
    rm -rf /var/lib/apt/lists/*

WORKDIR /
