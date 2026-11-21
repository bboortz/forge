# syntax=docker/dockerfile:1.7
#
# FG-078: psitransfer-slim-trixie — self-hosted file-share service built
# from upstream `github.com/psi-4ward/psitransfer`. Replaces the homelab-
# local `docker/psitransfer/` recipe.
#
# Chain (at FG-042 cap for Node):
#   debian:trixie-slim → node:24-trixie-slim → pre-builder/node-slim-trixie
#     → builder/node-trixie   (build stages 1+2+3)
#     → base/node-slim-trixie (runtime)
#
# Stages:
#   src       — git clone psitransfer@latest; snapshot /src/psitransfer + SHA
#   frontend  — build the Vue frontend bundle via `npm run build` in app/
#   backend   — install backend deps via `npm ci --production` at repo root
#   sbom      — syft over backend's node_modules
#   runtime   — base/node-slim-trixie + COPY artifacts from the 3 build
#               stages; VOLUME /data; USER 65532 nonroot

ARG BUILDER_NODE_REF=ghcr.io/bboortz/builder/node-trixie:latest
ARG BASE_NODE_SLIM_REF=ghcr.io/bboortz/base/node-slim-trixie:latest
ARG HC_REF=ghcr.io/bboortz/hc:0.1.0
# Pin via commit SHA for reproducibility; daily cron re-resolves `latest`
# per the FG-012 externally-sourced pattern (we clone here, not FG-012's
# `source:` block, because the rest of the Dockerfile is forge-local).
ARG PSITRANSFER_VERSION=latest

# --- Stage 0: fetch source via git clone ------------------------------------
FROM ${BUILDER_NODE_REF} AS src
# hadolint ignore=DL3002
USER 0
WORKDIR /src
# hadolint ignore=DL3059,DL3003
RUN set -eux; \
    if [ "${PSITRANSFER_VERSION:-latest}" = "latest" ]; then \
      git clone --depth=1 https://github.com/psi-4ward/psitransfer /src/psitransfer; \
    else \
      git clone https://github.com/psi-4ward/psitransfer /src/psitransfer; \
      git -C /src/psitransfer checkout "${PSITRANSFER_VERSION}"; \
    fi; \
    git -C /src/psitransfer rev-parse HEAD > /src/REVISION; \
    echo "resolved psitransfer SHA: $(cat /src/REVISION)"

# --- Stage 1: frontend build (Vue 2 bundle under public/app) ----------------
FROM ${BUILDER_NODE_REF} AS frontend
# hadolint ignore=DL3002
USER 0
WORKDIR /build
COPY --from=src /src/psitransfer /build/psitransfer
WORKDIR /build/psitransfer/app
RUN npm ci && npm run build

# --- Stage 2: backend deps install (production only) ------------------------
FROM ${BUILDER_NODE_REF} AS backend
# hadolint ignore=DL3002
USER 0
WORKDIR /build
COPY --from=src /src/psitransfer /build/psitransfer
WORKDIR /build/psitransfer
RUN npm ci --omit=dev && npm cache clean --force

# --- Stage 3: SBOM over backend node_modules + source -----------------------
FROM ${BUILDER_NODE_REF} AS sbom
# hadolint ignore=DL3002
USER 0
WORKDIR /sbom-input
COPY --from=backend /build/psitransfer/package.json /sbom-input/
COPY --from=backend /build/psitransfer/package-lock.json /sbom-input/
COPY --from=backend /build/psitransfer/node_modules /sbom-input/node_modules
RUN syft dir:/sbom-input -o cyclonedx-json > /sbom.json

# --- Stage 4: hc binary source (FG-031 pattern) -----------------------------
FROM ${HC_REF} AS hc

# --- Stage 5: runtime (base/node-slim-trixie overlay) -----------------------
FROM ${BASE_NODE_SLIM_REF} AS runtime

# FG-077: base/node-slim-trixie defaults USER 65532. Override to root for
# the layout + chown block; switch back to USER 65532 at the end so runtime
# stays nonroot.
# hadolint ignore=DL3002
USER 0

ARG GIT_SHA=unknown
ARG BUILD_TIMESTAMP=unknown

LABEL org.opencontainers.image.source="https://github.com/bboortz/forge"
LABEL org.opencontainers.image.licenses="MIT"
LABEL org.opencontainers.image.description="psitransfer (self-hosted file-share from psi-4ward/psitransfer) rebuilt on Forge's node-slim chain. Replaces homelab/docker/psitransfer/. Serves on :3000; persistent upload dir at /data; nonroot uid 65532."
LABEL org.opencontainers.image.revision="${GIT_SHA}"
LABEL org.opencontainers.image.created="${BUILD_TIMESTAMP}"

# Create /data + set ownership. The volume declaration below makes this a
# bind-mount target; initial ownership persists so nonroot can write.
RUN mkdir -p /data && chown -R 65532:65532 /data

WORKDIR /app

ENV PSITRANSFER_UPLOAD_DIR=/data NODE_ENV=production

# COPY the psitransfer runtime layout. Match upstream Dockerfile's
# `COPY *.js lib lang plugins public` pattern.
COPY --from=src --chown=65532:65532 /src/psitransfer/app.js /app/
COPY --from=src --chown=65532:65532 /src/psitransfer/cli.js /app/
COPY --from=src --chown=65532:65532 /src/psitransfer/config.js /app/
COPY --from=src --chown=65532:65532 /src/psitransfer/README.md /app/
COPY --from=src --chown=65532:65532 /src/psitransfer/lib /app/lib
COPY --from=src --chown=65532:65532 /src/psitransfer/lang /app/lang
COPY --from=src --chown=65532:65532 /src/psitransfer/plugins /app/plugins
COPY --from=src --chown=65532:65532 /src/psitransfer/public /app/public
# Overlay the compiled frontend bundle from stage 1.
COPY --from=frontend --chown=65532:65532 /build/psitransfer/public/app /app/public/app
# Backend node_modules (prod only).
COPY --from=backend --chown=65532:65532 /build/psitransfer/node_modules /app/node_modules
# SBOM from stage 3.
COPY --from=sbom /sbom.json /sbom.json
# Resolved upstream SHA + hc binary for HEALTHCHECK.
COPY --from=src /src/REVISION /app/REVISION
COPY --from=hc /hc /hc

USER 65532

EXPOSE 3000
VOLUME ["/data"]

# Docker-native HEALTHCHECK against psitransfer's HTTP listener.
HEALTHCHECK --interval=30s --timeout=5s --start-period=15s --retries=3 \
  CMD ["/hc", "-t", "3", "http://localhost:3000/"]

# base/node-slim-trixie ENTRYPOINT is ["node"]; CMD arg is app.js.
CMD ["app.js"]
