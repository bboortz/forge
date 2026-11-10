# syntax=docker/dockerfile:1.7
#
# FG-043 + FG-046: Prometheus IPMI Exporter FROM scratch. Hybrid build:
# - prometheus-ipmi-exporter Go binary built from upstream source via
#   forge-builder-go-trixie (not Debian's prometheus-ipmi-exporter pkg)
#   so the Go stdlib matches forge-builder-go-trixie's toolchain
#   (go1.27.x) instead of Debian's go1.24.x.
# - freeipmi ELF tools (bmc-info, ipmi-sensors, ipmi-chassis, ipmi-dcmi,
#   ipmi-sel) + their libs + their /etc/freeipmi/*.conf files are C
#   binaries from Debian — installed in a separate builder stage via
#   forge-builder-trixie, then overlayed.
#
# Runs as root for /dev/ipmi0 access (documented exception to
# scratch-nonroot default — see smoke_user_root.sh + PROMISES).
#
# Default collector set: bmc, ipmi, chassis, dcmi, sel. The `ipmi`
# collector's command is overridden to ipmi-sensors + wrapper flags
# (see ipmi-exporter.yml) because the upstream default
# `ipmimonitoring` is a Debian shell-script wrapper that can't run on
# scratch (FG-043 homelab lesson 2026-11-10).

ARG SCRATCH_BASE_REF=ghcr.io/bboortz/scratch-base-trixie:latest
# FG-046: Go builder for the exporter binary.
ARG FORGE_BUILDER_GO_REF=ghcr.io/bboortz/forge-builder-go-trixie:latest
# FG-025: Debian builder for the C freeipmi tools.
ARG FORGE_BUILDER_REF=ghcr.io/bboortz/forge-builder-trixie:latest
# FG-031: /hc for docker-native HEALTHCHECK.
ARG HC_REF=ghcr.io/bboortz/hc:0.1.0
# Pin upstream ipmi_exporter release (matches Debian's 1.10.0 wire-level
# contract).
ARG IPMI_EXPORTER_VERSION=v1.10.0

# --- Stage 0: baseline reference ---------------------------------------------
FROM ${SCRATCH_BASE_REF} AS scratch_base

# --- Stage 0b: hc binary source (FG-031) -------------------------------------
FROM ${HC_REF} AS hc

# --- Stage 1: Go builder — compile the exporter ------------------------------
FROM ${FORGE_BUILDER_GO_REF} AS go-builder

ARG IPMI_EXPORTER_VERSION

WORKDIR /src
# hadolint ignore=DL3003
RUN set -eux; \
    git clone --depth 1 --branch "${IPMI_EXPORTER_VERSION}" \
      https://github.com/prometheus-community/ipmi_exporter.git .; \
    REV="$(git rev-parse --short HEAD)"; \
    echo "${REV}" > /tmp/git-revision

SHELL ["/bin/bash", "-o", "pipefail", "-c"]
# hadolint ignore=DL3003
RUN set -eux; \
    REV="$(cat /tmp/git-revision)"; \
    BUILD_DATE="$(date -u +%Y%m%d-%H:%M:%S)"; \
    GO_VERSION="$(go version | awk '{print $3}')"; \
    PKG="github.com/prometheus/common/version"; \
    LDFLAGS="-s -w \
      -X ${PKG}.Version=${IPMI_EXPORTER_VERSION#v} \
      -X ${PKG}.Revision=${REV} \
      -X ${PKG}.Branch=HEAD \
      -X ${PKG}.BuildUser=forge@github-actions \
      -X ${PKG}.BuildDate=${BUILD_DATE} \
      -X ${PKG}.GoVersion=${GO_VERSION}"; \
    mkdir -p /out/usr/bin; \
    GOFLAGS=-mod=mod CGO_ENABLED=0 \
      go build -tags netgo -ldflags "${LDFLAGS}" \
        -o /out/usr/bin/prometheus-ipmi-exporter .

# SBOM — Go module graph.
RUN syft scan dir:/src/ -o cyclonedx-json > /sbom.json

# --- Stage 2: C builder — install freeipmi tools -----------------------------
FROM ${FORGE_BUILDER_REF} AS c-builder

COPY sid-pins/ /etc/apt/preferences.d/

# hadolint ignore=DL3008
RUN set -eux; \
    apt-get update; \
    apt-get -y --no-install-recommends install freeipmi-tools; \
    rm -rf /var/lib/apt/lists/*

# Collect freeipmi overlay: 5 ELF tools + 4 libs + 4 confs.
RUN set -eux; \
    install -d /out/usr/sbin /out/lib/x86_64-linux-gnu \
               /out/var/lib/freeipmi /out/var/log/freeipmi \
               /out/var/log/ipmiconsole /out/etc/prometheus \
               /out/etc/freeipmi; \
    for b in bmc-info ipmi-sensors ipmi-chassis ipmi-dcmi ipmi-sel; do \
      cp "/usr/sbin/${b}" "/out/usr/sbin/${b}"; \
    done; \
    for lib in libfreeipmi.so.17 libgcrypt.so.20 libgpg-error.so.0 libipmidetect.so.0; do \
      cp "/lib/x86_64-linux-gnu/${lib}" "/out/lib/x86_64-linux-gnu/${lib}"; \
    done; \
    for conf in freeipmi.conf freeipmi_interpret_sel.conf \
                freeipmi_interpret_sensor.conf libipmiconsole.conf; do \
      cp "/etc/freeipmi/${conf}" "/out/etc/freeipmi/${conf}"; \
    done

# Default config (collector_cmd + custom_args fix shipped with FG-043).
COPY ipmi-exporter.yml /out/etc/prometheus/ipmi-exporter.yml

# --- Stage 3: runtime (scratch) ----------------------------------------------
FROM scratch AS runtime

ARG GIT_SHA=unknown
ARG BUILD_TIMESTAMP=unknown
ARG IPMI_EXPORTER_VERSION

LABEL org.opencontainers.image.source="https://github.com/bboortz/forge"
LABEL org.opencontainers.image.licenses="Apache-2.0"
LABEL org.opencontainers.image.description="Minimal Prometheus IPMI Exporter FROM scratch (freeipmi-tools inlined, no shell; built from Go source + Debian freeipmi overlay). Runs as root for /dev/ipmi0 access."
LABEL org.opencontainers.image.revision="${GIT_SHA}"
LABEL org.opencontainers.image.created="${BUILD_TIMESTAMP}"
LABEL org.opencontainers.image.version="${IPMI_EXPORTER_VERSION}"

# Baseline first, overlay freeipmi tools, overlay Go exporter binary.
# hadolint ignore=DL3067
COPY --from=scratch_base /  /
COPY --from=c-builder    /out /
COPY --from=go-builder   /out /
COPY --from=go-builder   /sbom.json /sbom.json
# FG-031: /hc for docker-native HEALTHCHECK.
COPY --from=hc /hc /hc

# Runs as root. Documented exception — /dev/ipmi0 requires it.
WORKDIR /
EXPOSE 9290

HEALTHCHECK --interval=30s --timeout=5s --start-period=5s --retries=3 \
  CMD ["/hc", "-t", "3", "http://127.0.0.1:9290/metrics"]

ENTRYPOINT ["/usr/bin/prometheus-ipmi-exporter"]
CMD ["--config.file=/etc/prometheus/ipmi-exporter.yml", \
     "--web.listen-address=:9290"]
