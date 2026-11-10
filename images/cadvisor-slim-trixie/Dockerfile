# syntax=docker/dockerfile:1.7
#
# FG-044: Google cAdvisor v0.60.6 on debian:trixie-slim. Built from Go
# source because cadvisor is NOT in Debian trixie (upstream ships only
# an Alpine/musl image; Forge is glibc-world). CGO_ENABLED=0 produces
# a static Go binary with no dynamic deps; libpfm (perf events) is
# deliberately NOT linked — homelab monitoring doesn't need it.
#
# Shell + apt KEPT at runtime (slim contract — see image.has-shell CAP).
# Runs as root: cadvisor needs to read host cgroups (/sys/fs/cgroup),
# /var/lib/docker, and /:/rootfs, all root-owned. Upstream's runbook
# requires either --privileged or specific device/mount perms + caps.

ARG DEBIAN_BASE=debian:trixie-slim
# FG-046: shared Go builder base (apt-upgraded, syft + git + jq pre-baked,
# Go 1.27+ toolchain). Rebuilt before this image in the daily cron so
# Go stdlib CVE fixes propagate within 24h.
ARG FORGE_BUILDER_GO_REF=ghcr.io/bboortz/forge-builder-go-trixie:latest
# FG-031: /hc for docker-native HEALTHCHECK (no curl/wget in slim runtime).
ARG HC_REF=ghcr.io/bboortz/hc:0.1.0
# Pin exact upstream release. Daily cron auto-rebuilds against this ref.
ARG CADVISOR_VERSION=v0.60.6

# --- Stage 0: hc source ------------------------------------------------------
FROM ${HC_REF} AS hc

# --- Stage 1: Go builder (compile cadvisor + emit SBOM) ---------------------
FROM ${FORGE_BUILDER_GO_REF} AS builder

ARG CADVISOR_VERSION

WORKDIR /src
# Shallow clone: we only need the tagged commit, not the full history.
# hadolint ignore=DL3003
RUN set -eux; \
    git clone --depth 1 --branch "${CADVISOR_VERSION}" \
      https://github.com/google/cadvisor.git .; \
    GIT_REVISION="$(git rev-parse --short HEAD)"; \
    echo "${GIT_REVISION}" > /tmp/git-revision

# Build static binary (CGO off → no glibc dyn deps, no libpfm needed).
# Mirror upstream build.sh's ldflags (-X injects version/revision into
# the lib/version package so `cadvisor_version_info` metric populates).
# netgo tag: pure-Go DNS resolver (upstream's convention).
# pipefail is set via SHELL so DL4006's pipe-in-RUN rule is satisfied; the
# cd-in-RUN (DL3003) is intentional — cmd/ is a nested Go module.
SHELL ["/bin/bash", "-o", "pipefail", "-c"]
# hadolint ignore=DL3003
RUN set -eux; \
    REVISION="$(cat /tmp/git-revision)"; \
    BUILD_DATE="$(date -u +%Y%m%d-%H:%M:%S)"; \
    GO_VERSION="$(go version | sed -e 's/^[^0-9.]*\([0-9.]*\).*/\1/')"; \
    LDFLAGS="-s -w \
      -X github.com/google/cadvisor/lib/version.Version=${CADVISOR_VERSION} \
      -X github.com/google/cadvisor/lib/version.Revision=${REVISION} \
      -X github.com/google/cadvisor/lib/version.Branch=HEAD \
      -X github.com/google/cadvisor/lib/version.BuildUser=forge@github-actions \
      -X github.com/google/cadvisor/lib/version.BuildDate=${BUILD_DATE} \
      -X github.com/google/cadvisor/lib/version.GoVersion=${GO_VERSION}"; \
    mkdir -p /out/usr/bin; \
    cd cmd && \
      GOFLAGS=-mod=mod CGO_ENABLED=0 \
      go build -tags netgo -ldflags "${LDFLAGS}" \
        -o /out/usr/bin/cadvisor github.com/google/cadvisor/cmd; \
    cd /

# SBOM — dpkg (base layer) + go-module (cadvisor's module graph).
# Generated against /out so it names the single file we ship, plus the
# Go module list from the source tree.
RUN syft scan dir:/src/ -o cyclonedx-json > /sbom.json

# --- Stage 3: runtime (debian-slim) -----------------------------------------
FROM ${DEBIAN_BASE}

ARG GIT_SHA=unknown
ARG BUILD_TIMESTAMP=unknown
ARG CADVISOR_VERSION

LABEL org.opencontainers.image.source="https://github.com/bboortz/forge"
LABEL org.opencontainers.image.licenses="Apache-2.0"
LABEL org.opencontainers.image.description="Minimal, continuously patched Google cAdvisor built from source (slim-trixie runtime; shell + apt kept)"
LABEL org.opencontainers.image.revision="${GIT_SHA}"
LABEL org.opencontainers.image.created="${BUILD_TIMESTAMP}"
LABEL org.opencontainers.image.version="${CADVISOR_VERSION}"

COPY sid-pins/ /etc/apt/preferences.d/

# Fresh apt-upgrade before install (daily cron ensures patched runtime).
# ca-certificates for any HTTPS metric pushers.
# hadolint ignore=DL3008
RUN set -eux; \
    apt-get update; \
    apt-get -y --no-install-recommends upgrade; \
    apt-get -y --no-install-recommends install ca-certificates; \
    rm -rf /var/lib/apt/lists/*

COPY --from=builder /out/usr/bin/cadvisor /usr/bin/cadvisor
COPY --from=builder /sbom.json /sbom.json

# FG-031: /hc from the pinned hc image.
COPY --from=hc /hc /hc

EXPOSE 8080

# FG-031: self-healthcheck via /hc → /healthz (cadvisor's liveness endpoint).
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
  CMD ["/hc", "-t", "3", "http://127.0.0.1:8080/healthz"]

# Root: needed for cgroup read + /var/lib/docker bind mount + /:/rootfs.
# Upstream convention; any non-root path would require host-side changes.
ENTRYPOINT ["/usr/bin/cadvisor"]
CMD ["-logtostderr=true", "-port=8080"]
