# syntax=docker/dockerfile:1.7
#
# FG-058: forge-rooted Debian sid (unstable) slim base. Companion to
# FG-042's debian-slim-trixie — same shape, rolling-release lineage.
#
# Rationale: trixie occasionally ships CVE-exposed legacy-ABI packages
# that Debian explicitly won't fix (e.g. libxml2.so.2's 2.9.14 bucket
# — the trigger for FG-058). For CVEs that sid DOES fix at the `.so.2`
# SONAME (e.g. curl, openssl rolling point releases), having a Forge-
# rooted sid pre-builder on-hand makes the escape-hatch story a 30-min
# FG instead of apt-source gymnastics in a derivative Dockerfile.
#
# Consumer policy: default is still trixie (memory/design-decisions.md
# § "Exception — Debian sid"). Reach for this only when a specific
# trixie package is stuck unfixed AND sid's version is compatible with
# the downstream consumer's ABI requirements.
#
# Expected consumer count TODAY: zero. First real consumer will land
# in a future FG that picks this up as its FROM.
#
# Literal FROM (not ARG-indirected) so FG-042's upstream-grep invariant
# in `scripts/verify-no-upstream-drift.sh` can cheaply catch future
# drift (e.g. a new image FROMing debian:sid-slim directly instead of
# going through this pre-builder).

FROM debian:sid-slim

ARG GIT_SHA=unknown
ARG BUILD_TIMESTAMP=unknown

LABEL org.opencontainers.image.source="https://github.com/bboortz/forge"
LABEL org.opencontainers.image.licenses="Apache-2.0"
LABEL org.opencontainers.image.description="Forge-rooted Debian sid (unstable) slim base — apt-upgraded + CA certs; escape-hatch pre-builder for CVEs that trixie leaves unfixed."
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
