# syntax=docker/dockerfile:1.7
#
# FG-081: Arch Linux foundation — public API surface for external
# consumers who need a rolling-release runtime with pacman access (e.g.
# gamepad containers needing python-evdev kernel-ABI-matched).
#
# Dual duty:
#   (a) Final runtime for Arch apps — operator pulls this, pacman-installs
#       their payload (with a USER 0 override at the top of the derived
#       Dockerfile so pacman works).
#   (b) Builder stage for consumers who want a from-source build on Arch's
#       rolling toolchain.
#
# Composition on top of pre-builder/archlinux (pacman -Syu'd + CA):
#   - /hc baked in (bboortz/healthy static Zig healthcheck binary).
#   - USER 65532 (nonroot baseline — override to USER 0 in consumers that
#     need pacman at build time).
#   - No ENTRYPOINT (Arch's /bin/bash is the default).

ARG ARCHLINUX_REF=ghcr.io/bboortz/pre-builder/archlinux:latest
ARG HC_REF=ghcr.io/bboortz/hc:0.1.0

# --- Stage 0: hc binary source ----------------------------------------------
FROM ${HC_REF} AS hc

# --- Stage 1: runtime -------------------------------------------------------
FROM ${ARCHLINUX_REF} AS runtime

ARG GIT_SHA=unknown
ARG BUILD_TIMESTAMP=unknown

LABEL org.opencontainers.image.source="https://github.com/bboortz/forge"
LABEL org.opencontainers.image.licenses="Apache-2.0"
LABEL org.opencontainers.image.description="Arch Linux foundation (public API) — pre-builder/archlinux + /hc + nonroot uid. Final runtime for Arch consumers needing rolling-current packages + builder stage for future from-source on Arch's toolchain (FG-081)."
LABEL org.opencontainers.image.revision="${GIT_SHA}"
LABEL org.opencontainers.image.created="${BUILD_TIMESTAMP}"

COPY --from=hc /hc /hc

# Nonroot baseline. Consumers that need pacman or root-equivalent access
# override with `USER 0` at the top of their derived Dockerfile.
# Note: Arch's /etc/passwd has no entry at uid 65532 — this is a
# numeric-only uid. Consumers needing getpwuid() resolution should
# either add a passwd line or use `USER nobody` (uid 65534).
USER 65532
