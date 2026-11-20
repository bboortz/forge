# syntax=docker/dockerfile:1.7
#
# FG-075: slim Python foundation — public API surface for external consumers
# (homelab bots, Beaconry, future adopters). Dual duty:
#   (a) Final runtime for slim Python apps — operator pulls this, overlays
#       their code + pip install, runs it.
#   (b) Builder stage for consumers who want a scratch runtime — multi-stage
#       build FROMs this, then COPY --from=builder /install into a
#       base/python-scratch-trixie overlay.
#
# Composition on top of pre-builder/python-slim-trixie (apt-upgraded + CA
# + dumb-init):
#   - /hc baked in (bboortz/healthy's static Zig healthcheck binary; no libc,
#     no heap). Enables docker-native HEALTHCHECK without requiring consumers
#     to pull it separately.
#   - USER 65532 (distroless nonroot parity). Consumers who need root can
#     override with `USER 0`.
#   - ENTRYPOINT ["python3"] — clean Python entry.
#
# Why not FROM python:3.14-slim-trixie directly:
#   - Keeps the forge-rooted single-upstream-consumer invariant (FG-042).
#   - Inherits pre-builder/python-slim-trixie's apt-upgrade + CA + dumb-init.
#
# Why not include syft:
#   - Tier semantic: base/* is runtime, not builder. Consumers who want SBOM
#     can `COPY --from=ghcr.io/bboortz/mirror/syft /syft /usr/local/bin/syft`
#     (mirror/* is public API for tool passthroughs).

ARG PYTHON_SLIM_REF=ghcr.io/bboortz/pre-builder/python-slim-trixie:latest
ARG HC_REF=ghcr.io/bboortz/hc:0.1.0

# --- Stage 0: hc binary source (FG-031 pattern) ------------------------------
FROM ${HC_REF} AS hc

# --- Stage 1: runtime --------------------------------------------------------
FROM ${PYTHON_SLIM_REF} AS runtime

ARG GIT_SHA=unknown
ARG BUILD_TIMESTAMP=unknown

LABEL org.opencontainers.image.source="https://github.com/bboortz/forge"
LABEL org.opencontainers.image.licenses="Apache-2.0"
LABEL org.opencontainers.image.description="Slim Python foundation (public API) — pre-builder/python-slim-trixie + /hc + nonroot uid + python3 entrypoint. Serves as both final runtime and builder stage for consumer scratch overlays."
LABEL org.opencontainers.image.revision="${GIT_SHA}"
LABEL org.opencontainers.image.created="${BUILD_TIMESTAMP}"

COPY --from=hc /hc /hc

# Nonroot baseline. Consumers who need root can override with `USER 0` or
# `USER root`. Matches distroless convention; aligns with homelab's
# nonroot-first deployment.
USER 65532

ENTRYPOINT ["python3"]
