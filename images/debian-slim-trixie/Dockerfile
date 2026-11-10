# syntax=docker/dockerfile:1.7
#
# FG-042: forge-rooted Debian base — the slim equivalent of FG-025's
# forge-builder-trixie (which is python-rooted). Every Forge slim image
# that needs a plain Debian runtime FROMs this instead of Docker Hub's
# debian:trixie-slim directly.
#
# Consumers (post-FG-042): cadvisor-slim-trixie, ipmi-exporter-slim-trixie.
#
# Shell + apt kept (image.has-shell contract — this IS a slim-tier base).
# No special-purpose tooling: just apt-upgrade + ca-certificates. Any
# downstream image that wants more (freeipmi-tools, etc.) apt-installs
# it in its own RUN layer.
#
# Daily cron rebuilds this first so a fresh apt-upgrade propagates
# atomically to every downstream consumer within 24h — one of the
# three structural wins FG-042 captures (version-drift prevention).

# Literal FROM (not ARG-indirected) so FG-042's upstream-grep invariant can
# cheaply catch future drift (e.g. someone adding a third Dockerfile that
# bypasses debian-slim-trixie and FROMs debian:trixie-slim directly).
# Mirrors python-slim-trixie's convention.
FROM debian:trixie-slim

ARG GIT_SHA=unknown
ARG BUILD_TIMESTAMP=unknown

LABEL org.opencontainers.image.source="https://github.com/bboortz/forge"
LABEL org.opencontainers.image.licenses="Apache-2.0"
LABEL org.opencontainers.image.description="Forge-rooted Debian slim base — apt-upgraded + CA certs, published for every slim consumer to FROM instead of debian:trixie-slim directly"
LABEL org.opencontainers.image.revision="${GIT_SHA}"
LABEL org.opencontainers.image.created="${BUILD_TIMESTAMP}"

COPY sid-pins/ /etc/apt/preferences.d/

# hadolint ignore=DL3005,DL3008
RUN set -eux; \
    apt-get update; \
    apt-get -y --no-install-recommends upgrade; \
    apt-get -y --no-install-recommends install ca-certificates; \
    rm -rf /var/lib/apt/lists/*

WORKDIR /
