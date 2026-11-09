# syntax=docker/dockerfile:1.7
#
# FG-035: Prometheus server 2.53 FROM scratch. Debian builds the binary
# dynamically against glibc only (confirmed via ldd) — baseline supplies
# the full core closure.
#
# Initiates outbound TLS for remote_write + alertmanager delivery; the
# baseline CA bundle (/etc/ssl/certs/ca-certificates.crt) resolves via
# re-declared ENV SSL_CERT_FILE per FG-009.

ARG SCRATCH_BASE_REF=ghcr.io/bboortz/scratch-base-trixie:latest
ARG FORGE_BUILDER_REF=ghcr.io/bboortz/forge-builder-trixie:latest
# FG-031: /hc for docker-native HEALTHCHECK.
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
    apt-get -y --no-install-recommends install prometheus; \
    rm -rf /var/lib/apt/lists/*

# FG-020: embedded SBOM.
RUN set -eux; \
    syft dir:/ --override-default-catalogers dpkg-db-cataloger -o cyclonedx-json > /sbom.json

# Collect the prometheus-specific overlay.
# - Binaries: prometheus + promtool (promtool for config validation via
#   docker exec; FG-035 Gherkin scenario).
# - Debian ships /etc/prometheus/{consoles,console_libraries}/ as mostly-
#   empty placeholder dirs so the baked CMD's --web.console.* flags
#   resolve without error.
# - /usr/share/prometheus/web/ — FG-039: the Debian-build-compile-time
#   path for UI chrome templates (_base.html + the per-page HTML). The
#   binary hard-codes this path; GET / redirects to /classic/graph
#   which 500s with `error reading base template` without it. 332 KB.
# - /etc/prometheus/prometheus.yml ships as default (we overwrite it
#   with a minimal self-scrape config below).
# - /prometheus/ is the TSDB dir, owned 65534.
RUN set -eux; \
    install -d /out/usr/bin /out/etc/prometheus /out/prometheus \
               /out/usr/share/prometheus; \
    cp /usr/bin/prometheus /out/usr/bin/prometheus; \
    cp /usr/bin/promtool   /out/usr/bin/promtool; \
    cp -r /etc/prometheus/consoles         /out/etc/prometheus/consoles; \
    cp -r /etc/prometheus/console_libraries /out/etc/prometheus/console_libraries; \
    cp -r /usr/share/prometheus/web /out/usr/share/prometheus/web; \
    # chown TSDB to nobody (65534) — matches upstream prom/prometheus
    # so pre-existing volumes are mutually readable on migration.
    chown -R 65534:65534 /out/prometheus /out/etc/prometheus

# Ship a minimal self-scrape config as the baked default. Consumers
# mount their own at the same path in prod.
COPY prometheus.yml /out/etc/prometheus/prometheus.yml

# --- Stage 2: runtime (scratch) -----------------------------------------------
FROM scratch AS runtime

ARG GIT_SHA=unknown
ARG BUILD_TIMESTAMP=unknown

LABEL org.opencontainers.image.source="https://github.com/bboortz/forge"
LABEL org.opencontainers.image.licenses="Apache-2.0"
LABEL org.opencontainers.image.description="Minimal, continuously patched Prometheus 2.53 server base image (FROM scratch runtime, derives from scratch-base-trixie)"
LABEL org.opencontainers.image.revision="${GIT_SHA}"
LABEL org.opencontainers.image.created="${BUILD_TIMESTAMP}"

# Baseline first, overlay on top.
# hadolint ignore=DL3067
COPY --from=scratch_base / /
COPY --from=builder /out /
COPY --from=builder /sbom.json /sbom.json
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
