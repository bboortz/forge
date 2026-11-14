# syntax=docker/dockerfile:1.7
#
# FG-048: Prometheus server 2.53.5 FROM scratch, built from upstream Go
# source via dual-builder (same pattern ipmi-exporter-scratch-trixie
# uses for Go + C). Replaces the FG-035 Debian-packaged `prometheus`
# apt-install so the Go stdlib matches forge-builder-go-trixie's
# toolchain (go1.27.x) instead of Debian's lagging go1.24.x — eliminates
# the Debian-Go-toolchain-lag CVE class (GO-2025-3563, GO-2026-4337,
# GO-2026-6612).
#
# Stage 1 (UI builder) — FROM forge-builder-node-trixie: clones
# prometheus @ PROMETHEUS_VERSION, runs upstream's scripts/build_ui.sh
# which npm-builds the 2 workspace modules (lezer-promql, codemirror-
# promql) + the react-app. Output: web/ui/static/react/ tree populated
# with compiled SPA assets that -tags builtinassets embeds into the
# Go binary via //go:embed.
#
# Stage 2 (Go builder) — FROM forge-builder-go-trixie: COPY the full
# /src tree (including compiled UI assets) from the UI stage, then
# `go build -tags "netgo builtinassets stringlabels" -ldflags "..."`
# per upstream's .promu.yml. Produces /out/usr/bin/{prometheus,promtool}.
#
# Stage 3 (runtime scratch) — baseline + prometheus binaries + console
# templates + default prometheus.yml. **With -tags builtinassets the UI
# is embedded in the binary** — the FG-039 /usr/share/prometheus/web/
# overlay + the FG-040 cp -rL symlink-dereferencing fix become
# unnecessary and are removed in this rewrite.

ARG SCRATCH_BASE_REF=ghcr.io/bboortz/scratch-base-trixie:latest
# FG-048: dual-builder (Node for UI compile; Go for binary compile).
ARG FORGE_BUILDER_NODE_REF=ghcr.io/bboortz/forge-builder-node-trixie:latest
ARG FORGE_BUILDER_GO_REF=ghcr.io/bboortz/forge-builder-go-trixie:latest
# FG-031: /hc for docker-native HEALTHCHECK.
ARG HC_REF=ghcr.io/bboortz/hc:0.1.0
# Upstream prometheus release. Pinned to v2.53.x LTS line (operator
# stability); v3 migration is a separate story (new Mantine UI, pnpm,
# storage format changes).
ARG PROMETHEUS_VERSION=v2.53.5

# --- Stage 0: baseline reference ---------------------------------------------
FROM ${SCRATCH_BASE_REF} AS scratch_base

# --- Stage 0b: hc binary source (FG-031) -------------------------------------
FROM ${HC_REF} AS hc

# --- Stage 1: UI builder (Node) ----------------------------------------------
FROM ${FORGE_BUILDER_NODE_REF} AS ui-builder

ARG PROMETHEUS_VERSION

WORKDIR /src
# Shallow clone at the pinned release tag + run upstream's own build
# pipeline:
#   1) `cd web/ui && npm ci` — install workspace deps
#   2) `npm run build` — invokes build_ui.sh --all, which builds the
#      two UI modules (lezer-promql + codemirror-promql) AND the React
#      app, placing the compiled SPA under web/ui/static/react/
#   3) `bash scripts/compress_assets.sh` — gzips every file under
#      web/ui/static/ in place AND generates web/ui/embed.go from
#      embed.go.tmpl with the list of //go:embed directives. Without
#      step 3, `go build -tags builtinassets` fails with
#      `undefined: EmbedFS` (embed.go.tmpl alone declares no var).
# gzip/npm/git provided by forge-builder-node-trixie (corepack);
# prometheus v2.53 uses plain npm, not pnpm.
# hadolint ignore=DL3003
RUN set -eux; \
    git clone --depth 1 --branch "${PROMETHEUS_VERSION}" \
      https://github.com/prometheus/prometheus.git .; \
    (cd web/ui && npm ci && npm run build); \
    bash scripts/compress_assets.sh

# --- Stage 2: Go builder -----------------------------------------------------
FROM ${FORGE_BUILDER_GO_REF} AS builder

ARG PROMETHEUS_VERSION
ARG GIT_SHA=unknown
ARG BUILD_TIMESTAMP=unknown

WORKDIR /src
# Take the full source tree from the UI builder (including compiled UI
# assets at web/ui/static/react/ that -tags builtinassets will embed).
COPY --from=ui-builder /src /src

# Build prometheus + promtool with upstream's .promu.yml linux tags
# (netgo + builtinassets + stringlabels) and the standard LDFLAGS pattern
# injecting version metadata into github.com/prometheus/common/version.
# pipefail set via SHELL for DL4006 (go version | awk).
SHELL ["/bin/bash", "-o", "pipefail", "-c"]
# hadolint ignore=DL3003
RUN set -eux; \
    REV="$(git rev-parse --short HEAD)"; \
    BUILD_DATE="$(date -u +%Y%m%d-%H:%M:%S)"; \
    GO_VERSION="$(go version | awk '{print $3}')"; \
    PKG="github.com/prometheus/common/version"; \
    LDFLAGS="-s -w \
      -X ${PKG}.Version=${PROMETHEUS_VERSION#v} \
      -X ${PKG}.Revision=${REV} \
      -X ${PKG}.Branch=HEAD \
      -X ${PKG}.BuildUser=forge@github-actions \
      -X ${PKG}.BuildDate=${BUILD_DATE} \
      -X ${PKG}.GoVersion=${GO_VERSION}"; \
    mkdir -p /out/usr/bin; \
    GOFLAGS=-mod=mod CGO_ENABLED=0 \
      go build -tags 'netgo builtinassets stringlabels' -ldflags "${LDFLAGS}" \
        -o /out/usr/bin/prometheus ./cmd/prometheus; \
    GOFLAGS=-mod=mod CGO_ENABLED=0 \
      go build -tags 'netgo builtinassets stringlabels' -ldflags "${LDFLAGS}" \
        -o /out/usr/bin/promtool ./cmd/promtool

# SBOM — Go module cataloger against source tree. Captures the Go module
# graph and the Node package graph.
RUN syft scan dir:/src/ -o cyclonedx-json > /sbom.json

# Collect the prometheus-specific overlay — binaries + consoles +
# console_libraries (text templates, NOT embedded in the binary) +
# default prometheus.yml + TSDB dir.
RUN set -eux; \
    install -d /out/etc/prometheus /out/prometheus \
               /out/usr/share/prometheus; \
    cp -r consoles          /out/usr/share/prometheus/consoles; \
    cp -r console_libraries /out/usr/share/prometheus/console_libraries; \
    # Symlinks at /etc/prometheus/{consoles,console_libraries} so CMD's
    # --web.console.* flags can keep pointing there.
    ln -s /usr/share/prometheus/consoles         /out/etc/prometheus/consoles; \
    ln -s /usr/share/prometheus/console_libraries /out/etc/prometheus/console_libraries; \
    # chown TSDB to nobody (65534) — matches upstream prom/prometheus
    # so pre-existing volumes are mutually readable on migration.
    chown -R 65534:65534 /out/prometheus

# Ship a minimal self-scrape config as the baked default. Consumers
# mount their own at the same path in prod.
COPY prometheus.yml /out/etc/prometheus/prometheus.yml

# --- Stage 3: runtime (scratch) -----------------------------------------------
FROM scratch AS runtime

ARG GIT_SHA=unknown
ARG BUILD_TIMESTAMP=unknown
ARG PROMETHEUS_VERSION

LABEL org.opencontainers.image.source="https://github.com/bboortz/forge"
LABEL org.opencontainers.image.licenses="Apache-2.0"
LABEL org.opencontainers.image.description="Minimal, continuously patched Prometheus 2.53 server base image (FROM scratch runtime; built from Go source + Node-built UI embedded via -tags builtinassets; derives from scratch-base-trixie)"
LABEL org.opencontainers.image.revision="${GIT_SHA}"
LABEL org.opencontainers.image.created="${BUILD_TIMESTAMP}"
LABEL org.opencontainers.image.version="${PROMETHEUS_VERSION}"

# Baseline first, overlay on top.
# hadolint ignore=DL3067
COPY --from=scratch_base / /
COPY --from=builder /out /
COPY --from=builder /sbom.json /sbom.json
# FG-031: /hc for docker-native HEALTHCHECK.
COPY --from=hc /hc /hc

# FG-009: baseline's ENV SSL_CERT_FILE does NOT propagate through COPY —
# re-declare so remote_write + alertmanager HTTPS resolves.
ENV PATH=/usr/bin \
    SSL_CERT_FILE=/etc/ssl/certs/ca-certificates.crt \
    SSL_CERT_DIR=/etc/ssl/certs

# uid 65534 (nobody) matches upstream prom/prometheus; TSDB volumes
# migrating in from prom/prometheus remain readable without chown.
USER 65534:65534
WORKDIR /prometheus
EXPOSE 9090

# FG-031: self-healthcheck via /hc against /-/healthy. --start-period
# 10s allows for prometheus WAL replay on boot.
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
  CMD ["/hc", "-t", "3", "http://127.0.0.1:9090/-/healthy"]

ENTRYPOINT ["/usr/bin/prometheus"]
CMD ["--config.file=/etc/prometheus/prometheus.yml", \
     "--storage.tsdb.path=/prometheus", \
     "--web.console.libraries=/etc/prometheus/console_libraries", \
     "--web.console.templates=/etc/prometheus/consoles", \
     "--web.listen-address=:9090"]
