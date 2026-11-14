# syntax=docker/dockerfile:1.7
#
# FG-036 + FG-046: Prometheus Alertmanager FROM scratch. Built from
# upstream Go source via forge-builder-go-trixie (not Debian's
# prometheus-alertmanager package) so the Go stdlib matches the latest
# toolchain shipped in forge-builder-go-trixie (currently go1.27.x) —
# eliminates the Debian-Go-toolchain-lag CVE class.
#
# Static Go binary (CGO off), ships two binaries (alertmanager + amtool)
# + two notification templates (default.tmpl + email.tmpl).
#
# Initiates outbound HTTPS for every webhook receiver (Telegram,
# Mattermost, email over SMTPS, generic webhook_configs). Without
# ENV SSL_CERT_FILE re-declared (FG-009), webhooks fail with
# x509: certificate signed by unknown authority.

ARG SCRATCH_BASE_REF=ghcr.io/bboortz/scratch-base-trixie:latest
# FG-046: shared Go builder base.
ARG FORGE_BUILDER_GO_REF=ghcr.io/bboortz/forge-builder-go-trixie:latest
# FG-031: /hc for docker-native HEALTHCHECK.
ARG HC_REF=ghcr.io/bboortz/hc:0.1.0
# Pin exact upstream release — matches Debian trixie's
# prometheus-alertmanager 0.28.x wire-level contract. FG-050 attempted
# v0.28.1 → v0.35.0 but hit a build blocker: upstream v0.32.0+ no longer
# ships compiled UI assets in-tree (ui/web.go `//go:embed app/dist/*`),
# requiring a Node.js UI build pipeline. Blocked on FG-048's
# forge-builder-node-trixie extraction (prometheus hits the same wall).
# See IDEAS.md "alertmanager v0.32+ bump" entry.
ARG ALERTMANAGER_VERSION=v0.28.1

# --- Stage 0: baseline reference ---------------------------------------------
FROM ${SCRATCH_BASE_REF} AS scratch_base

# --- Stage 0b: hc binary source (FG-031) -------------------------------------
FROM ${HC_REF} AS hc

# --- Stage 1: Go builder -----------------------------------------------------
FROM ${FORGE_BUILDER_GO_REF} AS builder

ARG ALERTMANAGER_VERSION
ARG GIT_SHA=unknown
ARG BUILD_TIMESTAMP=unknown

WORKDIR /src
# hadolint ignore=DL3003
RUN set -eux; \
    git clone --depth 1 --branch "${ALERTMANAGER_VERSION}" \
      https://github.com/prometheus/alertmanager.git .; \
    REV="$(git rev-parse --short HEAD)"; \
    echo "${REV}" > /tmp/git-revision

# Build both binaries (alertmanager + amtool) with upstream's ldflag convention.
SHELL ["/bin/bash", "-o", "pipefail", "-c"]
# hadolint ignore=DL3003
RUN set -eux; \
    REV="$(cat /tmp/git-revision)"; \
    BUILD_DATE="$(date -u +%Y%m%d-%H:%M:%S)"; \
    GO_VERSION="$(go version | awk '{print $3}')"; \
    PKG="github.com/prometheus/common/version"; \
    LDFLAGS="-s -w \
      -X ${PKG}.Version=${ALERTMANAGER_VERSION#v} \
      -X ${PKG}.Revision=${REV} \
      -X ${PKG}.Branch=HEAD \
      -X ${PKG}.BuildUser=forge@github-actions \
      -X ${PKG}.BuildDate=${BUILD_DATE} \
      -X ${PKG}.GoVersion=${GO_VERSION}"; \
    mkdir -p /out/usr/bin /out/usr/share/prometheus/alertmanager \
             /out/etc/alertmanager /out/alertmanager; \
    GOFLAGS=-mod=mod CGO_ENABLED=0 \
      go build -tags netgo -ldflags "${LDFLAGS}" \
        -o /out/usr/bin/prometheus-alertmanager ./cmd/alertmanager; \
    GOFLAGS=-mod=mod CGO_ENABLED=0 \
      go build -tags netgo -ldflags "${LDFLAGS}" \
        -o /out/usr/bin/amtool ./cmd/amtool; \
    cp template/default.tmpl /out/usr/share/prometheus/alertmanager/default.tmpl; \
    cp template/email.tmpl   /out/usr/share/prometheus/alertmanager/email.tmpl; \
    chown -R 65534:65534 /out/alertmanager /out/etc/alertmanager

COPY alertmanager.yml /out/etc/alertmanager/alertmanager.yml

# SBOM — Go module graph from source tree.
RUN syft scan dir:/src/ -o cyclonedx-json > /sbom.json

# --- Stage 2: runtime (scratch) -----------------------------------------------
FROM scratch AS runtime

ARG GIT_SHA=unknown
ARG BUILD_TIMESTAMP=unknown
ARG ALERTMANAGER_VERSION

LABEL org.opencontainers.image.source="https://github.com/bboortz/forge"
LABEL org.opencontainers.image.licenses="Apache-2.0"
LABEL org.opencontainers.image.description="Minimal, continuously patched Prometheus Alertmanager base image (FROM scratch runtime, derives from scratch-base-trixie; built from Go source)"
LABEL org.opencontainers.image.revision="${GIT_SHA}"
LABEL org.opencontainers.image.created="${BUILD_TIMESTAMP}"
LABEL org.opencontainers.image.version="${ALERTMANAGER_VERSION}"

# hadolint ignore=DL3067
COPY --from=scratch_base / /
COPY --from=builder /out /
COPY --from=builder /sbom.json /sbom.json
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
