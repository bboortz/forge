# syntax=docker/dockerfile:1.7
#
# FG-079: forge-rooted Alpine 3.x pre-builder. Parallel to FG-042's
# debian-slim-trixie / ubuntu-slim-noble but on apk + musl instead of
# apt + glibc. First-precedent Alpine OS family in Forge.
#
# Consumers (post-FG-079): base/alpine-3 (public API); future ham-rigctld-
# alpine-3 + nginx-scratch-alpine + any Alpine-musl runtime.
#
# Shell + apk kept (image.has-shell contract — this IS a slim-tier base).
# Floats on alpine:3 upstream so daily cron picks up 3.21.N → 3.22.N
# patch releases automatically. A major-version bump to Alpine 4 would
# spawn a sibling pre-builder/alpine-4 in a separate FG.

# Literal FROM (not ARG-indirected) so FG-042's upstream-grep invariant
# can cheaply catch future drift. Pin is alpine:3 (floating major) —
# never alpine:latest (hadolint DL3007 + silent major bumps).
FROM alpine:3

ARG GIT_SHA=unknown
ARG BUILD_TIMESTAMP=unknown

LABEL org.opencontainers.image.source="https://github.com/bboortz/forge"
LABEL org.opencontainers.image.licenses="Apache-2.0"
LABEL org.opencontainers.image.description="Forge-rooted Alpine 3.x pre-builder — apk-upgraded + CA certs + dumb-init, published for every Alpine consumer to FROM instead of alpine:3 directly (FG-079)"
LABEL org.opencontainers.image.revision="${GIT_SHA}"
LABEL org.opencontainers.image.created="${BUILD_TIMESTAMP}"

# apk upgrade + install the forge-standard bundle (ca-certificates +
# dumb-init). Alpine's apk is single-command for both upgrade + install.
# --no-cache keeps the apk indexes out of the final image (parallel to
# Debian pre-builders' apt lists cleanup).
# hadolint ignore=DL3018
RUN set -eux; \
    apk upgrade --no-cache; \
    apk add --no-cache ca-certificates dumb-init; \
    update-ca-certificates
