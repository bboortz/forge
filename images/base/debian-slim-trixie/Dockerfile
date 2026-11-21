# syntax=docker/dockerfile:1.7
#
# FG-077: Debian slim foundation — public API surface for external consumers
# who want a plain Debian runtime (homelab apt-based apps, cadvisor, ipmi).
#
# Dual duty:
#   (a) Final runtime for slim Debian apps — operator pulls this + apt-installs
#       their payload (with a USER 0 override at the top of the derived
#       Dockerfile so apt-get works).
#   (b) Builder stage for consumers who want a scratch runtime via
#       base/scratch-trixie overlay.
#
# Composition on top of pre-builder/debian-slim-trixie (apt-upgraded + CA +
# dumb-init):
#   - /hc baked in (bboortz/healthy static Zig healthcheck binary). Enables
#     docker-native HEALTHCHECK without pulling it separately.
#   - USER 65532 (distroless nonroot parity). Consumers who need root — all
#     4 FG-077 consumers — override with USER 0 in their Dockerfile.
#   - No ENTRYPOINT — Debian ships /bin/sh as the default; consumers set
#     their own ENTRYPOINT/CMD.

ARG DEBIAN_SLIM_REF=ghcr.io/bboortz/pre-builder/debian-slim-trixie:latest
ARG HC_REF=ghcr.io/bboortz/hc:0.1.0

# --- Stage 0: hc binary source (FG-031 pattern) ------------------------------
FROM ${HC_REF} AS hc

# --- Stage 1: runtime --------------------------------------------------------
FROM ${DEBIAN_SLIM_REF} AS runtime

ARG GIT_SHA=unknown
ARG BUILD_TIMESTAMP=unknown

LABEL org.opencontainers.image.source="https://github.com/bboortz/forge"
LABEL org.opencontainers.image.licenses="Apache-2.0"
LABEL org.opencontainers.image.description="Slim Debian foundation (public API) — pre-builder/debian-slim-trixie + /hc + nonroot uid. Final runtime for apt-based consumers + builder stage for scratch overlays."
LABEL org.opencontainers.image.revision="${GIT_SHA}"
LABEL org.opencontainers.image.created="${BUILD_TIMESTAMP}"

COPY --from=hc /hc /hc

# Nonroot baseline. Consumers that need apt or root-equivalent access
# override with `USER 0` at the top of their Dockerfile.
USER 65532
