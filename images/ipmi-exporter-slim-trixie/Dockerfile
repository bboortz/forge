# syntax=docker/dockerfile:1.7
#
# FG-037 + FG-046: Prometheus IPMI Exporter on debian:trixie-slim.
# Hybrid build:
# - prometheus-ipmi-exporter Go binary built from upstream source via
#   forge-builder-go-trixie (not Debian's prometheus-ipmi-exporter pkg)
#   so the Go stdlib matches forge-builder-go-trixie's toolchain
#   (go1.27.x) instead of Debian's lagging go1.24.x.
# - freeipmi-tools + ca-certificates installed via Debian apt in the
#   runtime stage (keeps shell + apt available for operator debugging,
#   which is the slim variant's whole point).
#
# Runs as root to access /dev/ipmi0 (upstream convention + homelab
# requirement — device perms are root:root).
#
# Shell + apt KEPT at runtime (slim contract — see image.has-shell CAP)
# for operator debugging via `docker exec -it`.

ARG DEBIAN_BASE=debian:trixie-slim
# FG-046: shared Go builder base.
ARG FORGE_BUILDER_GO_REF=ghcr.io/bboortz/forge-builder-go-trixie:latest
# FG-031: /hc for docker-native HEALTHCHECK.
ARG HC_REF=ghcr.io/bboortz/hc:0.1.0
# Pin upstream ipmi_exporter release.
ARG IPMI_EXPORTER_VERSION=v1.10.0

# --- Stage 0: hc source ------------------------------------------------------
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

# --- Stage 2: runtime (slim) -------------------------------------------------
FROM ${DEBIAN_BASE}

ARG GIT_SHA=unknown
ARG BUILD_TIMESTAMP=unknown
ARG IPMI_EXPORTER_VERSION

LABEL org.opencontainers.image.source="https://github.com/bboortz/forge"
LABEL org.opencontainers.image.licenses="Apache-2.0"
LABEL org.opencontainers.image.description="Minimal, continuously patched Prometheus IPMI Exporter (built from Go source) + freeipmi-tools 1.6 (slim-trixie runtime; shell + apt kept for operator debugging)"
LABEL org.opencontainers.image.revision="${GIT_SHA}"
LABEL org.opencontainers.image.created="${BUILD_TIMESTAMP}"
LABEL org.opencontainers.image.version="${IPMI_EXPORTER_VERSION}"

COPY sid-pins/ /etc/apt/preferences.d/

# Fresh apt-upgrade before install (daily cron ensures patched runtime).
# NOTE: prometheus-ipmi-exporter the Debian package is NOT installed —
# the Go binary from the builder stage replaces it. We still apt-install
# freeipmi-tools (C binaries) + ca-certificates.
# hadolint ignore=DL3008
RUN set -eux; \
    apt-get update; \
    apt-get -y --no-install-recommends upgrade; \
    apt-get -y --no-install-recommends install \
      freeipmi-tools \
      ca-certificates; \
    rm -rf /var/lib/apt/lists/*

# Overlay the forge-built Go exporter + SBOM.
COPY --from=go-builder /out/usr/bin/prometheus-ipmi-exporter /usr/bin/prometheus-ipmi-exporter
COPY --from=go-builder /sbom.json /sbom.json

# FG-031: /hc from the pinned hc image.
COPY --from=hc /hc /hc

# Ship the local-BMC config (Debian's default). Consumers mount their
# own at /etc/prometheus/ipmi-exporter.yml in prod (e.g. for remote
# BMCs with credentials) — the CMD below points at this path.
COPY ipmi-exporter.yml /etc/prometheus/ipmi-exporter.yml

EXPOSE 9290

# FG-031: self-healthcheck via /hc. /metrics responds even without
# /dev/ipmi0 (self-metrics only — the IPMI probes return errors but
# the endpoint stays up).
HEALTHCHECK --interval=30s --timeout=5s --start-period=5s --retries=3 \
  CMD ["/hc", "-t", "3", "http://127.0.0.1:9290/metrics"]

# Root user: /dev/ipmi0 permissions are root:root on Debian hosts;
# upstream prometheuscommunity/ipmi-exporter also runs as root.
ENTRYPOINT ["/usr/bin/prometheus-ipmi-exporter"]
CMD ["--config.file=/etc/prometheus/ipmi-exporter.yml", \
     "--web.listen-address=:9290"]
