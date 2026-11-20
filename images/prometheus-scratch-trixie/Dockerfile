# syntax=docker/dockerfile:1.7
#
# FG-048 → FG-053: Prometheus server FROM scratch, built from upstream
# Go source via dual-builder. FG-053 (this revision) bumps v2.53.5 LTS →
# v3.x floating :latest per FG-050 `build.ref-latest-release` pattern.
# Motivation: v2.53.5's transitive golang.org/x/crypto v0.39.0 pin is
# vulnerable to GHSA-x527-x647-q7gg / CVE-2026-46595 (CVSS 10.0,
# VerifiedPublicKeyCallback permissions-skip enforcement). The v2.53 LTS
# line last shipped in June 2025 — no backport coming. v3.16.0 uses
# x/crypto v0.58.0 (patched) and the UI build is now pnpm-based (Mantine).
#
# Stage 1 (UI builder) — FROM forge-builder-node-trixie: clones
# prometheus @ <resolved>, enables corepack, runs `pnpm install
# --frozen-lockfile` + `pnpm run build` which invokes build_ui.sh --all
# (same script name as v2.53; internals produce the Mantine SPA now).
# Then `scripts/compress_assets.sh` gzips + generates web/ui/embed.go.
#
# Stage 2 (Go builder) — FROM forge-builder-go-trixie: COPY the full
# /src tree, `go build -tags "netgo builtinassets stringlabels"`.
#
# Stage 3 (runtime scratch) — baseline + prometheus binaries + console
# templates + default prometheus.yml. UI embedded via -tags builtinassets.
#
# Homelab impact (v2.53 → v3): webhook/alerting paths unchanged; TSDB
# format is backward-compatible on read; /api/v1/query stable; /classic/*
# routes gone (homelab's grafana-verify.py already updated in FG-048
# follow-up). Full audit in docs/plan/FG-053-prometheus-v3-cve-fix-plan.md.

ARG SCRATCH_BASE_REF=ghcr.io/bboortz/base/scratch-trixie:latest
ARG FORGE_BUILDER_NODE_REF=ghcr.io/bboortz/forge-builder-node-trixie:latest
ARG FORGE_BUILDER_GO_REF=ghcr.io/bboortz/forge-builder-go-trixie:latest
ARG HC_REF=ghcr.io/bboortz/hc:0.1.0
# FG-053: FG-050 build.ref-latest-release pattern — empty default →
# resolved at build time via GitHub Releases API. Pin explicitly via
# --build-arg for reproducibility (e.g. PROMETHEUS_VERSION=v3.16.0).
ARG PROMETHEUS_VERSION=
# Optional GitHub API token for the 5000/hr authenticated rate limit
# (vs 60/hr unauthenticated; CI matrix publish exhausts it otherwise).
# hadolint ignore=DL3064
ARG GITHUB_TOKEN=

# --- Stage 0: baseline reference ---------------------------------------------
FROM ${SCRATCH_BASE_REF} AS scratch_base

# --- Stage 0b: hc binary source (FG-031) -------------------------------------
FROM ${HC_REF} AS hc

# --- Stage 1: UI builder (Node) ----------------------------------------------
FROM ${FORGE_BUILDER_NODE_REF} AS ui-builder

ARG PROMETHEUS_VERSION
# hadolint ignore=DL3064
ARG GITHUB_TOKEN

SHELL ["/bin/bash", "-o", "pipefail", "-c"]
WORKDIR /src
# FG-053: resolve :latest at build time (FG-050 pattern) + run upstream's
# UI pipeline:
#   1) `cd web/ui && pnpm install --frozen-lockfile` — v3 switched from
#      npm to pnpm (pnpm-lock.yaml + pnpm-workspace.yaml). forge-builder-
#      node-trixie has `corepack enable`; pnpm is resolved from the
#      package.json `packageManager` field if set.
#   2) `pnpm run build:mantine-ui` → invokes `bash build_ui.sh --mantine-ui`
#      which builds the module/* workspaces + the Mantine UI, SKIPPING
#      the legacy react-app. Rationale: v3 serves Mantine at `/` by
#      default (`web/web.go:500`); the react-app is only reachable via
#      `--use-old-ui` and homelab doesn't set that flag. react-app lives
#      outside the pnpm workspace (own package.json, own deps) and would
#      require a separate `cd react-app && pnpm install` step — not worth
#      the extra install for a deprecated-by-default surface.
#   3) `bash scripts/compress_assets.sh` — gzips web/ui/static/ in place
#      AND generates web/ui/embed.go from embed.go.tmpl.
# hadolint ignore=DL3003
RUN set -eux; \
    TARGET_REF="${PROMETHEUS_VERSION}"; \
    if [ -z "${TARGET_REF}" ]; then \
      TARGET_REF="$(curl -fsSL \
        ${GITHUB_TOKEN:+-H "Authorization: Bearer ${GITHUB_TOKEN}"} \
        https://api.github.com/repos/prometheus/prometheus/releases/latest \
        | jq -r '.tag_name // empty')"; \
      [ -n "${TARGET_REF}" ] || { echo "could not resolve latest prometheus release" >&2; exit 1; }; \
    fi; \
    echo "${TARGET_REF}" > /tmp/resolved-version; \
    git clone --depth 1 --branch "${TARGET_REF}" \
      https://github.com/prometheus/prometheus.git .; \
    (cd web/ui && pnpm install --frozen-lockfile && pnpm run build:mantine-ui); \
    bash scripts/compress_assets.sh

# --- Stage 2: Go builder -----------------------------------------------------
FROM ${FORGE_BUILDER_GO_REF} AS builder

ARG GIT_SHA=unknown
ARG BUILD_TIMESTAMP=unknown

WORKDIR /src
# Take the full source tree from the UI builder (including compiled UI
# assets at web/ui/static/react/ that -tags builtinassets will embed) +
# the resolved version marker.
COPY --from=ui-builder /src /src
COPY --from=ui-builder /tmp/resolved-version /tmp/resolved-version

# Build prometheus + promtool with upstream's .promu.yml linux tags
# (netgo + builtinassets + stringlabels) and the standard LDFLAGS pattern
# injecting version metadata into github.com/prometheus/common/version.
# pipefail set via SHELL for DL4006 (go version | awk).
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
    mkdir -p /out/usr/bin; \
    GOFLAGS=-mod=mod CGO_ENABLED=0 GOWORK=off \
      go build -tags 'netgo builtinassets stringlabels' -ldflags "${LDFLAGS}" \
        -o /out/usr/bin/prometheus ./cmd/prometheus; \
    GOFLAGS=-mod=mod CGO_ENABLED=0 GOWORK=off \
      go build -tags 'netgo builtinassets stringlabels' -ldflags "${LDFLAGS}" \
        -o /out/usr/bin/promtool ./cmd/promtool

# SBOM — Go module cataloger against source tree. Captures the Go module
# graph and the Node package graph.
RUN syft scan dir:/src/ -o cyclonedx-json > /sbom.json

# Collect the prometheus-specific overlay — binaries + default
# prometheus.yml + TSDB dir. v3 removed the `consoles/` + `console_libraries/`
# directories from the repo root (deprecated feature). We still create the
# target dirs (empty) + symlinks so operators who pass `--web.console.*`
# flags don't get a startup error. Consumers who want classic consoles
# can bind-mount them into /etc/prometheus/consoles.
RUN set -eux; \
    install -d /out/etc/prometheus /out/prometheus \
               /out/usr/share/prometheus/consoles \
               /out/usr/share/prometheus/console_libraries; \
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

LABEL org.opencontainers.image.source="https://github.com/bboortz/forge"
LABEL org.opencontainers.image.licenses="Apache-2.0"
LABEL org.opencontainers.image.description="Minimal, continuously patched Prometheus server base image (FROM scratch runtime; built from Go source + Node-built UI embedded via -tags builtinassets; derives from scratch-base-trixie). FG-053: v3.x floating :latest for the x/crypto CVE fix."
LABEL org.opencontainers.image.revision="${GIT_SHA}"
LABEL org.opencontainers.image.created="${BUILD_TIMESTAMP}"
# FG-053: image.version no longer hard-pinned via ARG. Operators can
# inspect the resolved version via `docker exec <ctr> prometheus --version`
# or by reading /tmp/resolved-version at build time.

# Baseline first, overlay on top.
# hadolint ignore=DL3067
COPY --from=scratch_base / /
COPY --from=builder /out /
COPY --from=builder /sbom.json /sbom.json
COPY --from=builder /tmp/resolved-version /tmp/resolved-version
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
