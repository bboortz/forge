# syntax=docker/dockerfile:1.7
#
# FG-051: Forge's first Ubuntu-based image. Pre-builder for any image
# needing a library that Ubuntu ships but Debian trixie doesn't (today:
# libicu74 for the GitHub Actions runner's .NET 6 runtime; upstream
# installdependencies.sh only tries libicu70 and below). Published in
# the publish-pre-builders CI tier alongside debian-slim-trixie +
# python-slim-trixie.
#
# Ubuntu 24.04 "noble" (LTS until April 2029) picked for current-LTS
# stability + widest libicu74 availability. Adding Ubuntu as a Forge
# base family is a precedent-setting decision — see
# memory/design-decisions.md for the rationale.
#
# Literal FROM (not ARG-indirected) so FG-042's upstream-single-consumer
# grep-invariant can cheaply catch future drift. See
# scripts/verify-no-upstream-drift.sh (ubuntu:24.04 must appear in exactly
# 1 Dockerfile total — this one).

FROM ubuntu:24.04

ARG GIT_SHA=unknown
ARG BUILD_TIMESTAMP=unknown

LABEL org.opencontainers.image.source="https://github.com/bboortz/forge"
LABEL org.opencontainers.image.licenses="Apache-2.0"
LABEL org.opencontainers.image.description="Forge-rooted Ubuntu 24.04 (noble) slim base — apt-upgraded + CA certs + libicu74 preinstalled (for the GitHub Actions runner's .NET 6 runtime and any other consumer that needs it)"
LABEL org.opencontainers.image.revision="${GIT_SHA}"
LABEL org.opencontainers.image.created="${BUILD_TIMESTAMP}"

ENV DEBIAN_FRONTEND=noninteractive

# apt-upgrade + CA + libicu74.
#  - ca-certificates: TLS verify for any downstream curl / git
#  - libicu74: pre-bake so the GHA runner's installdependencies.sh (only
#    tries libicu70-72) succeeds. Keeping it in the base means multiple
#    future Ubuntu-base images don't each re-apt-install it.
# DL3008: ubuntu-security + default apt sources float within the noble
# release channel (daily cron's --pull picks up new digests).
# hadolint ignore=DL3008
RUN set -eux; \
    apt-get update; \
    apt-get -y --no-install-recommends upgrade; \
    apt-get -y --no-install-recommends install \
      ca-certificates libicu74; \
    rm -rf /var/lib/apt/lists/*
