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

# FG-042: FROM forge-rooted debian-slim-trixie (not debian:trixie-slim
# upstream). Resolved by scripts/build-image.sh.
ARG DEBIAN_SLIM_REF=ghcr.io/bboortz/debian-slim-trixie:latest
# FG-046: shared Go builder base.
ARG FORGE_BUILDER_GO_REF=ghcr.io/bboortz/forge-builder-go-trixie:latest
# FG-031: /hc for docker-native HEALTHCHECK.
ARG HC_REF=ghcr.io/bboortz/hc:0.1.0
# FG-050: track upstream's latest GitHub release. Empty default → build-time
# resolves via GitHub API (build.ref-latest-release CAP). Override for
# reproducible local builds via --build-arg IPMI_EXPORTER_VERSION=v1.10.0.
# Scratch sibling flips together — the pair must stay in lockstep so
# scratch + slim ship the same ipmi_exporter revision every cron.
ARG IPMI_EXPORTER_VERSION=

# --- Stage 0: hc source ------------------------------------------------------
FROM ${HC_REF} AS hc

# --- Stage 1: Go builder — compile the exporter ------------------------------
FROM ${FORGE_BUILDER_GO_REF} AS go-builder

ARG IPMI_EXPORTER_VERSION

WORKDIR /src
# FG-050: the resolve step pipes curl into jq; needs pipefail set before
# the RUN (hadolint DL4006). SHELL directive persists for subsequent RUNs.
SHELL ["/bin/bash", "-o", "pipefail", "-c"]
# FG-050: resolve IPMI_EXPORTER_VERSION if empty (track upstream latest).
# hadolint ignore=DL3003
RUN set -eux; \
    TARGET_REF="${IPMI_EXPORTER_VERSION}"; \
    if [ -z "${TARGET_REF}" ]; then \
      TARGET_REF="$(curl -fsSL \
        https://api.github.com/repos/prometheus-community/ipmi_exporter/releases/latest \
        | jq -r '.tag_name // empty')"; \
      [ -n "${TARGET_REF}" ] || { echo "could not resolve latest ipmi_exporter release" >&2; exit 1; }; \
    fi; \
    echo "${TARGET_REF}" > /tmp/resolved-version; \
    git clone --depth 1 --branch "${TARGET_REF}" \
      https://github.com/prometheus-community/ipmi_exporter.git .; \
    REV="$(git rev-parse --short HEAD)"; \
    echo "${REV}" > /tmp/git-revision

RUN set -eux; \
    VERSION="$(cat /tmp/resolved-version)"; \
    REV="$(cat /tmp/git-revision)"; \
    BUILD_DATE="$(date -u +%Y%m%d-%H:%M:%S)"; \
    GO_VERSION="$(go version | awk '{print $3}')"; \
    PKG="github.com/prometheus/common/version"; \
    LDFLAGS="-s -w \
      -X ${PKG}.Version=${VERSION#v} \
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
FROM ${DEBIAN_SLIM_REF}

ARG GIT_SHA=unknown
ARG BUILD_TIMESTAMP=unknown

LABEL org.opencontainers.image.source="https://github.com/bboortz/forge"
LABEL org.opencontainers.image.licenses="Apache-2.0"
LABEL org.opencontainers.image.description="Minimal, continuously patched Prometheus IPMI Exporter (built from Go source) + freeipmi-tools 1.6 (slim-trixie runtime; shell + apt kept for operator debugging)"
LABEL org.opencontainers.image.revision="${GIT_SHA}"
LABEL org.opencontainers.image.created="${BUILD_TIMESTAMP}"
# FG-050: no image.version label — IPMI_EXPORTER_VERSION resolves at build time.
# Resolved upstream version is baked into the exporter binary.

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
