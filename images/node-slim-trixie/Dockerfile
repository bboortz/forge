# syntax=docker/dockerfile:1.7
#
# FG-061: forge-rooted Node.js 24 LTS runtime slim base. Published
# pre-builder; every Forge Node runtime image FROMs this instead of
# `node:24-trixie-slim` directly, so apt-upgrade state is uniform
# across the fleet + version bumps happen in one place.
#
# Current consumers (post-FG-061):
#   - uptime-kuma-slim-trixie (runtime; migrated from direct upstream)
#
# Future consumers (FG-062 onward):
#   - psitransfer-slim-trixie
#   - possibly mattermost-slim-trixie / rocket-chat-slim-trixie (IDEAS)
#
# Note on toolchain exemption: `forge-builder-node-trixie` ALSO FROMs
# `node:24-trixie-slim` but as a BUILDER-stage toolchain base — same
# shape as `forge-builder-go-trixie` FROMing `golang:1.27-trixie`
# directly. That's a documented dedicated-toolchain exemption to FG-042's
# single-upstream-consumer rule. `verify-no-upstream-drift.sh` counts
# both this pre-builder + the builder image when matching `node:24-
# trixie-slim` — _EXPECTED is set to 5 total (4 slim pre-builders +
# this one). The builder doesn't count because its FROM is
# ARG-indirected (`FROM ${NODE_BASE}`); only this image uses the
# literal `FROM node:24-trixie-slim` form that the grep matches.
#
# Daily cron rebuilds this first so a fresh apt-upgrade propagates
# atomically to every downstream Node consumer within 24h.
#
# Literal FROM (not ARG-indirected) so FG-042's upstream-grep invariant
# in `scripts/verify-no-upstream-drift.sh` can catch future drift.
# Mirrors debian-slim-trixie / python-slim-trixie convention.

FROM node:24-trixie-slim

ARG GIT_SHA=unknown
ARG BUILD_TIMESTAMP=unknown

LABEL org.opencontainers.image.source="https://github.com/bboortz/forge"
LABEL org.opencontainers.image.licenses="Apache-2.0"
LABEL org.opencontainers.image.description="Forge-rooted Node.js 24 LTS runtime slim base — apt-upgraded + CA certs + dumb-init, for every Forge Node consumer to FROM instead of node:24-trixie-slim directly"
LABEL org.opencontainers.image.revision="${GIT_SHA}"
LABEL org.opencontainers.image.created="${BUILD_TIMESTAMP}"

COPY sid-pins/ /etc/apt/preferences.d/

# ca-certificates for outbound HTTPS, dumb-init for proper PID 1 signal
# forwarding (upstream node convention).
# hadolint ignore=DL3005,DL3008
RUN set -eux; \
    apt-get update; \
    apt-get -y --no-install-recommends upgrade; \
    apt-get -y --no-install-recommends install ca-certificates dumb-init; \
    rm -rf /var/lib/apt/lists/*

WORKDIR /
