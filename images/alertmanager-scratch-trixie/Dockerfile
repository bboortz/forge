# syntax=docker/dockerfile:1.7
#
# FG-036: Prometheus Alertmanager 0.28 FROM scratch. Debian builds the
# binary dynamically against libc only (confirmed via ldd).
#
# Initiates outbound HTTPS for EVERY notification receiver (Telegram,
# Mattermost, email over SMTPS, generic webhook_configs). Without
# ENV SSL_CERT_FILE re-declared (FG-009), every webhook fails with
# x509: certificate signed by unknown authority.

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
    apt-get -y --no-install-recommends install prometheus-alertmanager; \
    rm -rf /var/lib/apt/lists/*

# FG-020: embedded SBOM.
RUN set -eux; \
    syft dir:/ --override-default-catalogers dpkg-db-cataloger -o cyclonedx-json > /sbom.json

# Collect the alertmanager-specific overlay:
# - /usr/bin/prometheus-alertmanager + /usr/bin/amtool (for docker exec
#   config validation)
# - /usr/share/prometheus/alertmanager/default.tmpl — alertmanager
#   requires this on startup and exits 1 if it's missing
# - /etc/alertmanager/ (default config we overwrite below)
# - /alertmanager/ (silences + notification history store, owned 65534)
RUN set -eux; \
    install -d /out/usr/bin /out/etc/alertmanager /out/alertmanager \
               /out/usr/share/prometheus/alertmanager; \
    cp /usr/bin/prometheus-alertmanager /out/usr/bin/prometheus-alertmanager; \
    cp /usr/bin/amtool                  /out/usr/bin/amtool; \
    cp /usr/share/prometheus/alertmanager/default.tmpl \
       /out/usr/share/prometheus/alertmanager/default.tmpl; \
    cp /usr/share/prometheus/alertmanager/email.tmpl \
       /out/usr/share/prometheus/alertmanager/email.tmpl; \
    chown -R 65534:65534 /out/alertmanager /out/etc/alertmanager

# Minimal self-contained config (null receiver so container boots with
# no operator config). Consumers mount their own at the same path.
COPY alertmanager.yml /out/etc/alertmanager/alertmanager.yml

# --- Stage 2: runtime (scratch) -----------------------------------------------
FROM scratch AS runtime

ARG GIT_SHA=unknown
ARG BUILD_TIMESTAMP=unknown

LABEL org.opencontainers.image.source="https://github.com/bboortz/forge"
LABEL org.opencontainers.image.licenses="Apache-2.0"
LABEL org.opencontainers.image.description="Minimal, continuously patched Prometheus Alertmanager 0.28 base image (FROM scratch runtime, derives from scratch-base-trixie)"
LABEL org.opencontainers.image.revision="${GIT_SHA}"
LABEL org.opencontainers.image.created="${BUILD_TIMESTAMP}"

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
