# syntax=docker/dockerfile:1.7
#
# FG-043: Prometheus IPMI Exporter 1.10 FROM scratch. Debian trixie's
# prometheus-ipmi-exporter + freeipmi-tools (ELF binaries only — the
# shell-script wrappers `ipmimonitoring`, `ipmi-chassis-config`, etc.
# are deliberately NOT shipped since scratch has no shell).
#
# Runs as root for /dev/ipmi0 access (homelab hetzner-staging +
# server2 pattern). Documented exception to the "scratch runs
# nonroot 65532" default — see smoke_user_root.sh + PROMISES.
#
# Default collector set: bmc, ipmi, chassis, dcmi, sel. Matches
# ipmi-exporter-slim-trixie's default. Operators needing other
# collectors (bmc-watchdog, sm-lan-mode via ipmi-raw) use the slim
# variant.

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
    apt-get -y --no-install-recommends install \
      prometheus-ipmi-exporter freeipmi-tools; \
    rm -rf /var/lib/apt/lists/*

# FG-020: embedded SBOM (dpkg cataloger).
RUN set -eux; \
    syft dir:/ --override-default-catalogers dpkg-db-cataloger -o cyclonedx-json > /sbom.json

# Collect the ipmi-exporter + freeipmi overlay.
#
# Binaries: exporter + the 5 ELF tools that match the default-config
# collectors (bmc, ipmi, chassis, dcmi, sel). ipmi-raw + bmc-watchdog
# deliberately excluded; see plan § "Alternatives rejected".
#
# Libs: 4 .so files not in scratch-base-trixie. libc + libm are in
# the baseline.
#
# Writable dirs: /var/lib/freeipmi (IPC key), /var/log/freeipmi (logs)
# pre-created mode 0755 owned by root (container runs as root for
# /dev/ipmi0; non-root is impossible without host-side device-group
# changes).
RUN set -eux; \
    install -d /out/usr/bin /out/usr/sbin /out/lib/x86_64-linux-gnu \
               /out/var/lib/freeipmi /out/var/log/freeipmi \
               /out/var/log/ipmiconsole /out/etc/prometheus \
               /out/etc/freeipmi; \
    cp /usr/bin/prometheus-ipmi-exporter /out/usr/bin/prometheus-ipmi-exporter; \
    for b in bmc-info ipmi-sensors ipmi-chassis ipmi-dcmi ipmi-sel; do \
      cp "/usr/sbin/${b}" "/out/usr/sbin/${b}"; \
    done; \
    # libs (plain cp dereferences the SONAME symlink into a real file).
    for lib in libfreeipmi.so.17 libgcrypt.so.20 libgpg-error.so.0 libipmidetect.so.0; do \
      cp "/lib/x86_64-linux-gnu/${lib}" "/out/lib/x86_64-linux-gnu/${lib}"; \
    done; \
    # freeipmi-common config files: ipmi-sensors reads these to interpret
    # sensor-event thresholds. WITHOUT them the exporter's `ipmi` collector
    # silently returns ipmi_up=0 even though stand-alone ipmi-sensors runs
    # OK on /dev/ipmi0. Caught on homelab server2.home verification
    # 2026-11-10: FG-037 slim pulls freeipmi-common as a dpkg dep; scratch
    # overlay needs them explicit. See CAPABILITIES image.ipmi-exporter-serves-metrics.
    for conf in freeipmi.conf freeipmi_interpret_sel.conf \
                freeipmi_interpret_sensor.conf libipmiconsole.conf; do \
      cp "/etc/freeipmi/${conf}" "/out/etc/freeipmi/${conf}"; \
    done

# Default config — same collector set as the slim variant's default
# (bmc + ipmi + chassis + dcmi + sel). Consumers mount their own at
# this path in prod (e.g. for remote-BMC credentials).
COPY ipmi-exporter.yml /out/etc/prometheus/ipmi-exporter.yml

# --- Stage 2: runtime (scratch) -----------------------------------------------
FROM scratch AS runtime

ARG GIT_SHA=unknown
ARG BUILD_TIMESTAMP=unknown

LABEL org.opencontainers.image.source="https://github.com/bboortz/forge"
LABEL org.opencontainers.image.licenses="Apache-2.0"
LABEL org.opencontainers.image.description="Minimal Prometheus IPMI Exporter 1.10 FROM scratch (freeipmi-tools inlined, no shell; 3× smaller than ipmi-exporter-slim-trixie). Runs as root for /dev/ipmi0 access."
LABEL org.opencontainers.image.revision="${GIT_SHA}"
LABEL org.opencontainers.image.created="${BUILD_TIMESTAMP}"

# Baseline first (glibc + libm + TLS + DNS + /etc + /tmp 1777), then overlay.
# hadolint ignore=DL3067
COPY --from=scratch_base / /
COPY --from=builder /out /
COPY --from=builder /sbom.json /sbom.json
# FG-031: /hc for docker-native HEALTHCHECK.
COPY --from=hc /hc /hc

# Runs as root (default). Documented exception — /dev/ipmi0 requires it.
# Non-root is impossible without host-side device-group changes.
WORKDIR /
EXPOSE 9290

# FG-031: self-healthcheck via /hc on /metrics. Responds even without
# /dev/ipmi0 (self-metrics are always present; ipmi probes fail cleanly).
HEALTHCHECK --interval=30s --timeout=5s --start-period=5s --retries=3 \
  CMD ["/hc", "-t", "3", "http://127.0.0.1:9290/metrics"]

ENTRYPOINT ["/usr/bin/prometheus-ipmi-exporter"]
CMD ["--config.file=/etc/prometheus/ipmi-exporter.yml", \
     "--web.listen-address=:9290"]
