# syntax=docker/dockerfile:1.7
#
# FG-079: Alpine 3.x foundation — public API surface for external consumers
# who need a musl runtime (ham-rigctld, future nginx-scratch-alpine, any
# Alpine-compatible service).
#
# Dual duty:
#   (a) Final runtime for Alpine apps — operator pulls this, apk-installs
#       their payload (with a USER 0 override at the top of the derived
#       Dockerfile so apk works).
#   (b) Builder stage for consumers who want a scratch-musl runtime (future
#       base/scratch-alpine-3; not in scope for FG-079).
#
# Composition on top of pre-builder/alpine-3 (apk-upgraded + CA + dumb-init):
#   - /hc baked in (bboortz/healthy static Zig healthcheck binary).
#   - USER 65532 (nonroot baseline — override to USER 0 in consumers that
#     need apk at build time).
#   - No ENTRYPOINT (Alpine's busybox /bin/sh is the default).

ARG ALPINE_REF=ghcr.io/bboortz/pre-builder/alpine-3:3
ARG HC_REF=ghcr.io/bboortz/hc:0.1.0

# --- Stage 0: hc binary source ----------------------------------------------
FROM ${HC_REF} AS hc

# --- Stage 1: runtime -------------------------------------------------------
FROM ${ALPINE_REF} AS runtime

ARG GIT_SHA=unknown
ARG BUILD_TIMESTAMP=unknown

LABEL org.opencontainers.image.source="https://github.com/bboortz/forge"
LABEL org.opencontainers.image.licenses="Apache-2.0"
LABEL org.opencontainers.image.description="Alpine 3.x foundation (public API) — pre-builder/alpine-3 + /hc + nonroot uid. Final runtime for Alpine-musl consumers + builder stage for future scratch-musl overlays (FG-079)."
LABEL org.opencontainers.image.revision="${GIT_SHA}"
LABEL org.opencontainers.image.created="${BUILD_TIMESTAMP}"

COPY --from=hc /hc /hc

# Nonroot baseline. Consumers that need apk or root-equivalent access
# override with `USER 0` at the top of their derived Dockerfile.
# Note: Alpine's /etc/passwd has no entry at uid 65532 — this is a
# numeric-only uid. Consumers needing getpwuid() resolution should
# either add a passwd line or use `USER nobody` (uid 65534).
USER 65532
