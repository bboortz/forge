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

# FG-042: FROM forge-rooted debian-slim-trixie (not debian:trixie-slim
# upstream) so cadvisor-slim and ipmi-exporter-slim share apt-upgrade
# state atomically. Resolved to forge-local during local builds, to
# ghcr.io/bboortz/debian-slim-trixie:latest in CI (see build-image.sh).
ARG DEBIAN_SLIM_REF=ghcr.io/bboortz/debian-slim-trixie:latest
# FG-046: shared Go builder base (apt-upgraded, syft + git + jq pre-baked,
# Go 1.27+ toolchain). Rebuilt before this image in the daily cron so
# Go stdlib CVE fixes propagate within 24h.
ARG FORGE_BUILDER_GO_REF=ghcr.io/bboortz/forge-builder-go-trixie:latest
# FG-031: /hc for docker-native HEALTHCHECK (no curl/wget in slim runtime).
ARG HC_REF=ghcr.io/bboortz/hc:0.1.0
# FG-050: track upstream's latest GitHub release. Empty default → build-time
# resolves via GitHub API (build.ref-latest-release CAP). Override for
# reproducible local builds via --build-arg CADVISOR_VERSION=v0.60.6.
ARG CADVISOR_VERSION=

# --- Stage 0: hc source ------------------------------------------------------
FROM ${HC_REF} AS hc

# --- Stage 1: Go builder (compile cadvisor + emit SBOM) ---------------------
FROM ${FORGE_BUILDER_GO_REF} AS builder

ARG CADVISOR_VERSION

WORKDIR /src
# FG-050: the resolve step pipes curl into jq; needs pipefail set before
# the RUN (hadolint DL4006). SHELL directive persists through the rest
# of this stage's subsequent RUNs.
SHELL ["/bin/bash", "-o", "pipefail", "-c"]
# FG-050: resolve CADVISOR_VERSION if empty (track upstream latest release).
# Shallow clone: we only need the tagged commit, not the full history.
# hadolint ignore=DL3003
RUN set -eux; \
    TARGET_REF="${CADVISOR_VERSION}"; \
    if [ -z "${TARGET_REF}" ]; then \
      TARGET_REF="$(curl -fsSL \
        https://api.github.com/repos/google/cadvisor/releases/latest \
        | jq -r '.tag_name // empty')"; \
      [ -n "${TARGET_REF}" ] || { echo "could not resolve latest cadvisor release" >&2; exit 1; }; \
    fi; \
    echo "${TARGET_REF}" > /tmp/resolved-version; \
    git clone --depth 1 --branch "${TARGET_REF}" \
      https://github.com/google/cadvisor.git .; \
    GIT_REVISION="$(git rev-parse --short HEAD)"; \
    echo "${GIT_REVISION}" > /tmp/git-revision

# Build static binary (CGO off → no glibc dyn deps, no libpfm needed).
# Mirror upstream build.sh's ldflags (-X injects version/revision into
# the lib/version package so `cadvisor_version_info` metric populates).
# netgo tag: pure-Go DNS resolver (upstream's convention).
# pipefail is set via SHELL so DL4006's pipe-in-RUN rule is satisfied; the
# cd-in-RUN (DL3003) is intentional — cmd/ is a nested Go module.
# FG-050: SHELL directive set above the resolve step still in effect here.
# hadolint ignore=DL3003
RUN set -eux; \
    VERSION="$(cat /tmp/resolved-version)"; \
    REVISION="$(cat /tmp/git-revision)"; \
    BUILD_DATE="$(date -u +%Y%m%d-%H:%M:%S)"; \
    GO_VERSION="$(go version | sed -e 's/^[^0-9.]*\([0-9.]*\).*/\1/')"; \
    LDFLAGS="-s -w \
      -X github.com/google/cadvisor/lib/version.Version=${VERSION} \
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
FROM ${DEBIAN_SLIM_REF}

ARG GIT_SHA=unknown
ARG BUILD_TIMESTAMP=unknown

LABEL org.opencontainers.image.source="https://github.com/bboortz/forge"
LABEL org.opencontainers.image.licenses="Apache-2.0"
LABEL org.opencontainers.image.description="Minimal, continuously patched Google cAdvisor built from source (slim-trixie runtime; shell + apt kept)"
LABEL org.opencontainers.image.revision="${GIT_SHA}"
LABEL org.opencontainers.image.created="${BUILD_TIMESTAMP}"
# FG-050: no image.version label — CADVISOR_VERSION resolves at build time.
# Resolved upstream version is baked into the cadvisor binary (visible via
# `cadvisor --version` and the `cadvisor_version_info` metric).

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
