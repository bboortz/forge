# syntax=docker/dockerfile:1.7
#
# FG-077: Ubuntu 24.04 (noble) slim foundation — public API surface for
# external consumers that need Ubuntu-specific libraries (libicu74 — see
# memory/design-decisions.md § Ubuntu exception).
#
# Dual duty:
#   (a) Final runtime for Ubuntu-based apps (GitHub Actions self-hosted
#       runner — the FG-051 driver for Ubuntu support).
#   (b) Builder stage for Ubuntu-based scratch overlays if that pattern ever
#       appears (no current consumer).
#
# Composition on top of pre-builder/ubuntu-slim-noble (apt-upgraded + CA +
# dumb-init):
#   - /hc baked in.
#   - USER 65532 default (consumers override to USER 0 as needed — the FG-051
#     github-runner image needs USER 0 because the runner startup requires
#     root).
#   - No ENTRYPOINT — Ubuntu ships /bin/sh as the default.

ARG UBUNTU_SLIM_NOBLE_REF=ghcr.io/bboortz/pre-builder/ubuntu-slim-noble:latest
ARG HC_REF=ghcr.io/bboortz/hc:0.1.0

FROM ${HC_REF} AS hc

FROM ${UBUNTU_SLIM_NOBLE_REF} AS runtime

ARG GIT_SHA=unknown
ARG BUILD_TIMESTAMP=unknown

LABEL org.opencontainers.image.source="https://github.com/bboortz/forge"
LABEL org.opencontainers.image.licenses="Apache-2.0"
LABEL org.opencontainers.image.description="Slim Ubuntu noble foundation (public API) — pre-builder/ubuntu-slim-noble + /hc + nonroot uid. Final runtime for Ubuntu-library-dependent consumers (libicu74) + builder-stage base for future scratch overlays."
LABEL org.opencontainers.image.revision="${GIT_SHA}"
LABEL org.opencontainers.image.created="${BUILD_TIMESTAMP}"

COPY --from=hc /hc /hc

USER 65532
