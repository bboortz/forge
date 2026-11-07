# syntax=docker/dockerfile:1.7
#
# FG-028: Two-stage. Builder from forge-builder-trixie (apt-upgraded +
# syft + CA certs pre-installed). Runtime FROM scratch, composed of:
#   1. scratch-base-trixie (glibc + TLS + DNS + zoneinfo + /etc identity)
#   2. mosquitto-specific overlay (mosquitto server + clients + libcjson
#      + libcap + libdlt + libmosquitto + libsystemd + libwebsockets
#      + libwrap + mosquitto user @ uid 1883 (Eclipse convention) +
#      writable /mosquitto/{config,data,log})
#
# Default-permissive config at /mosquitto/config/mosquitto.conf so a
# config-less `docker run` works for dev. Production consumers mount
# their own config at the same path.

ARG SCRATCH_BASE_REF=ghcr.io/bboortz/scratch-base-trixie:latest
ARG FORGE_BUILDER_REF=ghcr.io/bboortz/forge-builder-trixie:latest

# --- Stage 0: baseline reference ---------------------------------------------
FROM ${SCRATCH_BASE_REF} AS scratch_base

# --- Stage 1: builder ---------------------------------------------------------
FROM ${FORGE_BUILDER_REF} AS builder

ARG GIT_SHA=unknown
ARG BUILD_TIMESTAMP=unknown

COPY sid-pins/ /etc/apt/preferences.d/

# forge-builder-trixie cleared apt lists + applied apt-upgrade. Re-populate
# the lists and install mosquitto. apt-upgrade NOT repeated.
# hadolint ignore=DL3008
RUN set -eux; \
    apt-get update; \
    apt-get -y --no-install-recommends install mosquitto mosquitto-clients; \
    rm -rf /var/lib/apt/lists/*

# FG-020: embedded SBOM from builder-stage dpkg. syft pre-installed by FG-025.
RUN set -eux; \
    syft dir:/ --override-default-catalogers dpkg-db-cataloger -o cyclonedx-json > /sbom.json

# Pull baseline's /etc identity files so we APPEND the mosquitto user
# instead of overwriting (FG-005 append pattern).
COPY --from=scratch_base /etc/passwd /tmp/baseline-passwd
COPY --from=scratch_base /etc/group  /tmp/baseline-group

# Assemble the mosquitto overlay. Baseline supplies glibc + TLS + DNS
# (libc/m/ssl/crypto/z/zstd/gcc_s/nss_*). We add:
#   - mosquitto server + client binaries + mosquitto_passwd util
#   - mosquitto-specific libs (libcjson, libcap, libdlt, libmosquitto,
#     libsystemd, libwebsockets, libwrap)
#   - mosquitto user @ uid 1883 (Eclipse convention)
#   - writable /mosquitto/{config,data,log} with correct ownership
RUN set -eux; \
    install -d /out/etc \
               /out/usr/sbin /out/usr/bin \
               /out/lib/x86_64-linux-gnu \
               /out/mosquitto/config /out/mosquitto/data /out/mosquitto/log; \
    cp /usr/sbin/mosquitto         /out/usr/sbin/mosquitto; \
    for b in mosquitto_sub mosquitto_pub mosquitto_passwd mosquitto_rr mosquitto_ctrl; do \
      cp "/usr/bin/${b}" "/out/usr/bin/${b}"; \
    done; \
    # Mosquitto-specific libs on top of baseline.
    for lib in libcap.so.2 libcjson.so.1 libdlt.so.2 libmosquitto.so.1 \
               libsystemd.so.0 libwebsockets.so.19 libwrap.so.0; do \
      cp "/lib/x86_64-linux-gnu/${lib}" "/out/lib/x86_64-linux-gnu/${lib}"; \
    done; \
    # Append mosquitto service user (uid 1883 — Eclipse convention) to
    # baseline's /etc/passwd + /etc/group.
    mq_uid=1883; mq_gid=1883; \
    cat /tmp/baseline-passwd                                                     > /out/etc/passwd; \
    printf 'mosquitto:x:%s:%s:mosquitto:/mosquitto:/sbin/nologin\n' \
      "${mq_uid}" "${mq_gid}"                                                    >> /out/etc/passwd; \
    cat /tmp/baseline-group                                                      > /out/etc/group; \
    printf 'mosquitto:x:%s:\n' "${mq_gid}"                                      >> /out/etc/group; \
    chown -R "${mq_uid}:${mq_gid}" /out/mosquitto; \
    chmod 0750 /out/mosquitto/config /out/mosquitto/data /out/mosquitto/log

# Bake the default-permissive config AFTER the chown so mosquitto can
# read it under uid 1883.
COPY --chown=1883:1883 config/mosquitto.conf /out/mosquitto/config/mosquitto.conf

# --- Stage 2: runtime (scratch) -----------------------------------------------
FROM scratch AS runtime

ARG GIT_SHA=unknown
ARG BUILD_TIMESTAMP=unknown

LABEL org.opencontainers.image.source="https://github.com/bboortz/forge"
LABEL org.opencontainers.image.licenses="Apache-2.0"
LABEL org.opencontainers.image.description="Minimal, continuously patched Mosquitto 2 MQTT broker (FROM scratch, derives from scratch-base-trixie)"
LABEL org.opencontainers.image.revision="${GIT_SHA}"
LABEL org.opencontainers.image.created="${BUILD_TIMESTAMP}"

# Baseline first (glibc + TLS + DNS + zoneinfo + /etc identity), then overlay.
# hadolint ignore=DL3067
COPY --from=scratch_base / /
COPY --from=builder /out /
# FG-020: SBOM embed.
COPY --from=builder /sbom.json /sbom.json

# FG-009: re-declare SSL_CERT_FILE per the "ENV does not propagate" lesson.
ENV SSL_CERT_FILE=/etc/ssl/certs/ca-certificates.crt \
    SSL_CERT_DIR=/etc/ssl/certs

# Numeric form satisfies hadolint DL3066 (the mosquitto user IS in /etc/passwd
# at uid 1883 — smoke_user_mosquitto.sh verifies it).
USER 1883:1883
WORKDIR /mosquitto
EXPOSE 1883
ENTRYPOINT ["/usr/sbin/mosquitto"]
CMD ["-c", "/mosquitto/config/mosquitto.conf"]
