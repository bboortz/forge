# syntax=docker/dockerfile:1.7
#
# FG-037: Prometheus IPMI Exporter 1.10 on Debian-slim-trixie. NOT a
# scratch image — the Debian `prometheus-ipmi-exporter` shells out to
# `freeipmi-tools` binaries (ipmimonitoring / ipmi-sel / ipmi-dcmi /
# ipmi-chassis) whose dynamic C closure (libfreeipmi + libgcrypt +
# libgpg-error + libgsasl + ...) makes scratch overlay impractical.
#
# Runs as root to access /dev/ipmi0 for local BMC scraping (upstream
# convention + homelab requirement — device perms are root:root).
#
# Shell + apt are KEPT at runtime (slim contract — see image.has-shell
# CAP) for operator debugging via `docker exec -it`.

ARG DEBIAN_BASE=debian:trixie-slim
# FG-031: /hc for docker-native HEALTHCHECK.
ARG HC_REF=ghcr.io/bboortz/hc:0.1.0

# --- Stage 0: hc source ------------------------------------------------------
FROM ${HC_REF} AS hc

# --- Stage 1: runtime (slim, single-stage) -----------------------------------
FROM ${DEBIAN_BASE}

ARG GIT_SHA=unknown
ARG BUILD_TIMESTAMP=unknown

LABEL org.opencontainers.image.source="https://github.com/bboortz/forge"
LABEL org.opencontainers.image.licenses="Apache-2.0"
LABEL org.opencontainers.image.description="Minimal, continuously patched Prometheus IPMI Exporter 1.10 + freeipmi-tools 1.6 (slim-trixie runtime; shell + apt kept for operator debugging)"
LABEL org.opencontainers.image.revision="${GIT_SHA}"
LABEL org.opencontainers.image.created="${BUILD_TIMESTAMP}"

COPY sid-pins/ /etc/apt/preferences.d/

# Fresh apt-upgrade before install (daily cron ensures patched runtime).
# ca-certificates needed for any HTTPS pushgateway consumers might use.
# hadolint ignore=DL3008
RUN set -eux; \
    apt-get update; \
    apt-get -y --no-install-recommends upgrade; \
    apt-get -y --no-install-recommends install \
      prometheus-ipmi-exporter \
      freeipmi-tools \
      ca-certificates; \
    rm -rf /var/lib/apt/lists/*

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
