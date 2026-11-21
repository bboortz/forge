# syntax=docker/dockerfile:1.7
#
# FG-077: Node slim foundation — public API surface for external consumers
# who want a slim Node runtime (uptime-kuma-slim; future Node service apps).
#
# Dual duty:
#   (a) Final runtime for slim Node apps — operator pulls this + overlays
#       their code (with USER 0 if npm install is needed at build time).
#   (b) Builder stage for consumers who want a scratch runtime via
#       base/scratch-trixie overlay.
#
# Composition on top of pre-builder/node-slim-trixie (apt-upgraded + CA +
# dumb-init):
#   - /hc baked in.
#   - USER 65532 (nonroot baseline — override to USER 0 in consumers that
#     need npm install at build time, same pattern as python-slim).
#   - ENTRYPOINT ["node"] — parallel to base/python-slim-trixie's python3
#     entrypoint; `docker run <image> script.js` Just Works.
#
# Chain depth note (FG-042): this image sits at hop 4 (debian:trixie-slim →
# node:24-trixie-slim → pre-builder/node-slim-trixie → base/node-slim-trixie),
# bringing the Node consumer chain to **5 hops at cap** (e.g.
# uptime-kuma-slim-trixie's final runtime). Any future Node scratch runtime
# would need chain-depth restructuring.

ARG NODE_SLIM_REF=ghcr.io/bboortz/pre-builder/node-slim-trixie:latest
ARG HC_REF=ghcr.io/bboortz/hc:0.1.0

FROM ${HC_REF} AS hc

FROM ${NODE_SLIM_REF} AS runtime

ARG GIT_SHA=unknown
ARG BUILD_TIMESTAMP=unknown

LABEL org.opencontainers.image.source="https://github.com/bboortz/forge"
LABEL org.opencontainers.image.licenses="Apache-2.0"
LABEL org.opencontainers.image.description="Slim Node 24 LTS foundation (public API) — pre-builder/node-slim-trixie + /hc + nonroot uid + node entrypoint. Final runtime for slim Node apps + builder stage for consumer scratch overlays."
LABEL org.opencontainers.image.revision="${GIT_SHA}"
LABEL org.opencontainers.image.created="${BUILD_TIMESTAMP}"

COPY --from=hc /hc /hc

USER 65532

ENTRYPOINT ["node"]
