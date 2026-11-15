# syntax=docker/dockerfile:1.7
#
# FG-036 → FG-046 → FG-052: Prometheus Alertmanager FROM scratch.
#
# FG-052 (this revision): bumped v0.28.1 → v0.35.0 via dual-builder.
# Upstream v0.32+ switched to `//go:embed app/dist` which requires
# pre-built UI assets at Go build time; we build them from source in a
# Node stage (forge-builder-node-trixie) before the Go build stage.
# This image is the 2nd consumer of the FG-048 `build.from-node-and-go-source`
# CAP (prometheus-scratch-trixie being the first).
#
# ALERTMANAGER_VERSION= empty → resolved via FG-050 `build.ref-latest-
# release` CAP (GitHub Releases API) at build time.
#
# Scope: static Go binary (CGO off), ships two binaries (alertmanager +
# amtool) + both UIs embedded (classic Elm at `/`, new Mantine at `/ui/`)
# + two notification templates (default.tmpl + email.tmpl).
#
# Outbound HTTPS for every webhook receiver (Telegram, Mattermost, email
# over SMTPS, generic webhook_configs). Without ENV SSL_CERT_FILE
# re-declared (FG-009), webhooks fail with x509: certificate signed by
# unknown authority — covered by smoke_ssl_cert_env.sh.

ARG SCRATCH_BASE_REF=ghcr.io/bboortz/scratch-base-trixie:latest
# FG-046: shared Go builder base.
ARG FORGE_BUILDER_GO_REF=ghcr.io/bboortz/forge-builder-go-trixie:latest
# FG-048 + FG-052: shared Node builder base for the UI compile step.
ARG FORGE_BUILDER_NODE_REF=ghcr.io/bboortz/forge-builder-node-trixie:latest
# FG-031: /hc for docker-native HEALTHCHECK.
ARG HC_REF=ghcr.io/bboortz/hc:0.1.0
# FG-050 pattern: empty → GitHub Releases API resolve at build time.
# Pin explicitly for reproducibility, e.g. --build-arg ALERTMANAGER_VERSION=v0.35.0.
ARG ALERTMANAGER_VERSION=
# Optional GitHub API token for the 5000/hr authenticated rate limit
# (vs 60/hr unauthenticated; CI matrix publish exhausts it otherwise).
# hadolint ignore=DL3064
ARG GITHUB_TOKEN=

# --- Stage 0: baseline reference ---------------------------------------------
FROM ${SCRATCH_BASE_REF} AS scratch_base

# --- Stage 0b: hc binary source (FG-031) -------------------------------------
FROM ${HC_REF} AS hc

# --- Stage 1: UI builder (Node) ----------------------------------------------
# Builds both Elm classic UI (ui/app/) + Mantine new UI (ui/mantine-ui/)
# into ui/app/dist/, which the Go build stage embeds via -tags builtinassets.
# The Elm compiler is an npm devDependency ("elm": "0.19.1-6" in
# ui/app/package.json) — `npm ci` installs it automatically.
FROM ${FORGE_BUILDER_NODE_REF} AS ui-builder

ARG ALERTMANAGER_VERSION
# hadolint ignore=DL3064
ARG GITHUB_TOKEN

SHELL ["/bin/bash", "-o", "pipefail", "-c"]
WORKDIR /src
# hadolint ignore=DL3003
RUN set -eux; \
    TARGET_REF="${ALERTMANAGER_VERSION}"; \
    if [ -z "${TARGET_REF}" ]; then \
      TARGET_REF="$(curl -fsSL \
        ${GITHUB_TOKEN:+-H "Authorization: Bearer ${GITHUB_TOKEN}"} \
        https://api.github.com/repos/prometheus/alertmanager/releases/latest \
        | jq -r '.tag_name // empty')"; \
      [ -n "${TARGET_REF}" ] || { echo "could not resolve latest alertmanager release" >&2; exit 1; }; \
    fi; \
    echo "${TARGET_REF}" > /tmp/resolved-version; \
    git clone --depth 1 --branch "${TARGET_REF}" https://github.com/prometheus/alertmanager.git .

# Build classic Elm UI → ui/app/dist/ (contains index.html + assets/).
# hadolint ignore=DL3003
RUN set -eux; \
    cd ui/app && npm ci && npm run build

# Build Mantine UI → ui/app/dist/mantine/ (served at /ui/).
# hadolint ignore=DL3003
RUN set -eux; \
    cd ui/mantine-ui && npm ci && npm run build

# --- Stage 2: Go builder -----------------------------------------------------
FROM ${FORGE_BUILDER_GO_REF} AS builder

ARG GIT_SHA=unknown
ARG BUILD_TIMESTAMP=unknown

# Receive the already-UI-built source tree + the resolved version marker.
COPY --from=ui-builder /src /src
COPY --from=ui-builder /tmp/resolved-version /tmp/resolved-version

WORKDIR /src
SHELL ["/bin/bash", "-o", "pipefail", "-c"]
# hadolint ignore=DL3003
RUN set -eux; \
    TARGET_REF="$(cat /tmp/resolved-version)"; \
    REV="$(git rev-parse --short HEAD)"; \
    BUILD_DATE="$(date -u +%Y%m%d-%H:%M:%S)"; \
    GO_VERSION="$(go version | awk '{print $3}')"; \
    PKG="github.com/prometheus/common/version"; \
    LDFLAGS="-s -w \
      -X ${PKG}.Version=${TARGET_REF#v} \
      -X ${PKG}.Revision=${REV} \
      -X ${PKG}.Branch=HEAD \
      -X ${PKG}.BuildUser=forge@github-actions \
      -X ${PKG}.BuildDate=${BUILD_DATE} \
      -X ${PKG}.GoVersion=${GO_VERSION}"; \
    mkdir -p /out/usr/bin /out/usr/share/prometheus/alertmanager \
             /out/etc/alertmanager /out/alertmanager; \
    GOFLAGS=-mod=mod CGO_ENABLED=0 \
      go build -tags "netgo builtinassets" -ldflags "${LDFLAGS}" \
        -o /out/usr/bin/prometheus-alertmanager ./cmd/alertmanager; \
    GOFLAGS=-mod=mod CGO_ENABLED=0 \
      go build -tags "netgo builtinassets" -ldflags "${LDFLAGS}" \
        -o /out/usr/bin/amtool ./cmd/amtool; \
    cp template/default.tmpl /out/usr/share/prometheus/alertmanager/default.tmpl; \
    cp template/email.tmpl   /out/usr/share/prometheus/alertmanager/email.tmpl; \
    chown -R 65534:65534 /out/alertmanager /out/etc/alertmanager

COPY alertmanager.yml /out/etc/alertmanager/alertmanager.yml

# SBOM — Go module graph from the UI-populated source tree.
RUN syft scan dir:/src/ -o cyclonedx-json > /sbom.json

# --- Stage 3: runtime (scratch) -----------------------------------------------
FROM scratch AS runtime

ARG GIT_SHA=unknown
ARG BUILD_TIMESTAMP=unknown

LABEL org.opencontainers.image.source="https://github.com/bboortz/forge"
LABEL org.opencontainers.image.licenses="Apache-2.0"
LABEL org.opencontainers.image.description="Minimal, continuously patched Prometheus Alertmanager base image (FROM scratch runtime; built from Go source via forge-builder-node-trixie + forge-builder-go-trixie; both Elm classic UI + Mantine UI embedded via -tags builtinassets). FG-052: v0.35 bump with floating :latest tag."
LABEL org.opencontainers.image.revision="${GIT_SHA}"
LABEL org.opencontainers.image.created="${BUILD_TIMESTAMP}"

# hadolint ignore=DL3067
COPY --from=scratch_base / /
COPY --from=builder /out /
COPY --from=builder /sbom.json /sbom.json
COPY --from=builder /tmp/resolved-version /tmp/resolved-version
# FG-031: /hc for HEALTHCHECK.
COPY --from=hc /hc /hc

# FG-009: re-declare SSL_CERT_FILE so Telegram / Mattermost / email
# webhooks resolve the baseline CA bundle.
ENV PATH=/usr/bin \
    SSL_CERT_FILE=/etc/ssl/certs/ca-certificates.crt \
    SSL_CERT_DIR=/etc/ssl/certs

# uid 65534 (nobody) — matches upstream prom/alertmanager for silences
# volume compat.
USER 65534:65534
WORKDIR /alertmanager
EXPOSE 9093

# FG-031: self-healthcheck via /hc against /-/healthy.
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
  CMD ["/hc", "-t", "3", "http://127.0.0.1:9093/-/healthy"]

ENTRYPOINT ["/usr/bin/prometheus-alertmanager"]
CMD ["--config.file=/etc/alertmanager/alertmanager.yml", \
     "--storage.path=/alertmanager", \
     "--web.listen-address=:9093"]
