# syntax=docker/dockerfile:1.7
#
# FG-034 + FG-046: Prometheus node_exporter FROM scratch. Built from
# upstream Go source via forge-builder-go-trixie (not Debian's
# prometheus-node-exporter package) so the Go stdlib matches the latest
# toolchain shipped in forge-builder-go-trixie (currently go1.27.x) —
# eliminates the Debian-Go-toolchain-lag CVE class (GO-2026-4337,
# GO-2026-6612, etc.) that applies to the pre-FG-046 Debian-packaged
# binary.
#
# Pure-Go upstream + CGO_ENABLED=0 → statically linked binary. No shell,
# no apt, no dpkg database, no glibc dyn deps in the runtime.
#
# Does NOT initiate outbound TLS (scrape-only exporter).

ARG SCRATCH_BASE_REF=ghcr.io/bboortz/scratch-base-trixie:latest
# FG-046: shared Go builder base (apt-upgraded + Go 1.27 + git + syft).
ARG FORGE_BUILDER_GO_REF=ghcr.io/bboortz/forge-builder-go-trixie:latest
# FG-031 pattern: embed /hc for docker-native HEALTHCHECK.
ARG HC_REF=ghcr.io/bboortz/hc:0.1.0
# FG-050: pinned to upstream v1.12.1 (bumped from v1.9.0). v1.10-v1.12
# ship no metric renames or label removals — container-contract safe.
# v1.10.0 moved mdadm metric collection from /proc/mdstat to sysfs
# (same metric names, slightly more accurate under RAID-degraded); v1.10
# added `erofs` to default filesystem excludes. node-exporter stays on
# an explicit pin (not :latest) because historically collector renames
# between minors have broken downstream dashboards.
ARG NODE_EXPORTER_VERSION=v1.12.1

# --- Stage 0: baseline reference ---------------------------------------------
FROM ${SCRATCH_BASE_REF} AS scratch_base

# --- Stage 0b: hc binary source (FG-031) -------------------------------------
FROM ${HC_REF} AS hc

# --- Stage 1: Go builder -----------------------------------------------------
FROM ${FORGE_BUILDER_GO_REF} AS builder

ARG NODE_EXPORTER_VERSION
ARG GIT_SHA=unknown
ARG BUILD_TIMESTAMP=unknown

WORKDIR /src
# Shallow clone at the pinned tag.
# hadolint ignore=DL3003
RUN set -eux; \
    git clone --depth 1 --branch "${NODE_EXPORTER_VERSION}" \
      https://github.com/prometheus/node_exporter.git .; \
    REV="$(git rev-parse --short HEAD)"; \
    echo "${REV}" > /tmp/git-revision

# Build static binary. Upstream's own `promu build` uses these ldflags
# to populate `node_exporter --version`.
# pipefail set via SHELL for DL4006 (go version | sed pipe).
SHELL ["/bin/bash", "-o", "pipefail", "-c"]
RUN set -eux; \
    REV="$(cat /tmp/git-revision)"; \
    BUILD_DATE="$(date -u +%Y%m%d-%H:%M:%S)"; \
    GO_VERSION="$(go version | awk '{print $3}')"; \
    PKG="github.com/prometheus/common/version"; \
    LDFLAGS="-s -w \
      -X ${PKG}.Version=${NODE_EXPORTER_VERSION#v} \
      -X ${PKG}.Revision=${REV} \
      -X ${PKG}.Branch=HEAD \
      -X ${PKG}.BuildUser=forge@github-actions \
      -X ${PKG}.BuildDate=${BUILD_DATE} \
      -X ${PKG}.GoVersion=${GO_VERSION}"; \
    mkdir -p /out/usr/bin; \
    GOFLAGS=-mod=mod CGO_ENABLED=0 \
      go build -tags netgo -ldflags "${LDFLAGS}" \
        -o /out/usr/bin/prometheus-node-exporter .

# SBOM — Go module cataloger (binary is built from source; dpkg catalogger
# captures forge-builder-go-trixie's layer which is just build tooling).
RUN syft scan dir:/src/ -o cyclonedx-json > /sbom.json

# --- Stage 2: runtime (scratch) -----------------------------------------------
FROM scratch AS runtime

ARG GIT_SHA=unknown
ARG BUILD_TIMESTAMP=unknown
ARG NODE_EXPORTER_VERSION

LABEL org.opencontainers.image.source="https://github.com/bboortz/forge"
LABEL org.opencontainers.image.licenses="Apache-2.0"
LABEL org.opencontainers.image.description="Minimal, continuously patched Prometheus node_exporter base image (FROM scratch runtime, derives from scratch-base-trixie; built from Go source)"
LABEL org.opencontainers.image.revision="${GIT_SHA}"
LABEL org.opencontainers.image.created="${BUILD_TIMESTAMP}"
LABEL org.opencontainers.image.version="${NODE_EXPORTER_VERSION}"

# Baseline first, overlay on top.
# hadolint ignore=DL3067
COPY --from=scratch_base / /
COPY --from=builder /out /
# FG-020: SBOM.
COPY --from=builder /sbom.json /sbom.json
# FG-031: /hc for docker-native HEALTHCHECK.
COPY --from=hc /hc /hc

USER 65532:65532
EXPOSE 9100

# FG-031: self-healthcheck via /hc against /metrics (always responds,
# even without /host/proc or /host/sys mounts).
HEALTHCHECK --interval=30s --timeout=5s --start-period=5s --retries=3 \
  CMD ["/hc", "-t", "3", "http://127.0.0.1:9100/metrics"]

ENTRYPOINT ["/usr/bin/prometheus-node-exporter"]
