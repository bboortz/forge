# syntax=docker/dockerfile:1.7
#
# FG-034: Prometheus node_exporter FROM scratch. Pure-Go upstream, but
# Debian builds it dynamically against glibc — so we need libc + libm +
# libpthread + libdl (baseline supplies all four). No shell, no apt,
# no dpkg database in the runtime.
#
# Does NOT initiate outbound TLS (scrape-only exporter), so no CA
# bundle gymnastics beyond what the baseline already ships.

ARG SCRATCH_BASE_REF=ghcr.io/bboortz/scratch-base-trixie:latest
ARG FORGE_BUILDER_REF=ghcr.io/bboortz/forge-builder-trixie:latest
# FG-031 pattern: embed /hc for docker-native HEALTHCHECK.
ARG HC_REF=ghcr.io/bboortz/hc:0.1.0

# --- Stage 0: baseline reference ---------------------------------------------
FROM ${SCRATCH_BASE_REF} AS scratch_base

# --- Stage 0b: hc binary source (FG-031) -------------------------------------
FROM ${HC_REF} AS hc

# --- Stage 1: builder ---------------------------------------------------------
FROM ${FORGE_BUILDER_REF} AS builder

ARG GIT_SHA=unknown
ARG BUILD_TIMESTAMP=unknown

COPY sid-pins/ /etc/apt/preferences.d/

# hadolint ignore=DL3008
RUN set -eux; \
    apt-get update; \
    apt-get -y --no-install-recommends install prometheus-node-exporter; \
    rm -rf /var/lib/apt/lists/*

# FG-020: embedded SBOM from builder-stage dpkg.
RUN set -eux; \
    syft dir:/ --override-default-catalogers dpkg-db-cataloger -o cyclonedx-json > /sbom.json

# Collect the node_exporter-specific overlay. Baseline supplies the full
# core glibc + TLS + DNS + zoneinfo closure; node_exporter only needs the
# binary itself (and baseline-provided libs).
RUN set -eux; \
    install -d /out/usr/bin; \
    cp /usr/bin/prometheus-node-exporter /out/usr/bin/prometheus-node-exporter

# --- Stage 2: runtime (scratch) -----------------------------------------------
FROM scratch AS runtime

ARG GIT_SHA=unknown
ARG BUILD_TIMESTAMP=unknown

LABEL org.opencontainers.image.source="https://github.com/bboortz/forge"
LABEL org.opencontainers.image.licenses="Apache-2.0"
LABEL org.opencontainers.image.description="Minimal, continuously patched Prometheus node_exporter 1.9 base image (FROM scratch runtime, derives from scratch-base-trixie)"
LABEL org.opencontainers.image.revision="${GIT_SHA}"
LABEL org.opencontainers.image.created="${BUILD_TIMESTAMP}"

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
