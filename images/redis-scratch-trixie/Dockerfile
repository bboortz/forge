# syntax=docker/dockerfile:1.7
#
# Two-stage. Builder from forge-builder-trixie (apt-upgraded + syft + CA
# certs pre-installed). Runtime FROM scratch, composed of:
#   1. scratch-base-trixie (glibc + TLS + DNS + zoneinfo + /etc)
#   2. redis-specific overlay (redis-server + redis-cli + libatomic + libcap
#      + libjemalloc + liblzf + libstdc++ + libsystemd + redis user @ uid 999)
#
# No shell, no apt, no dpkg database. Entrypoint = redis-server binary
# (upstream Docker image uses a bash docker-entrypoint.sh; redis doesn't
# NEED it — the server starts directly with no side effects. Consumer
# healthcheck uses `redis-cli ping` which also works without a shell.)

ARG SCRATCH_BASE_REF=ghcr.io/bboortz/scratch-base-trixie:latest
# FG-025 Phase 2: builder stage FROMs the shared forge-builder-trixie image.
ARG FORGE_BUILDER_REF=ghcr.io/bboortz/forge-builder-trixie:latest

# --- Stage 0: baseline reference ---------------------------------------------
FROM ${SCRATCH_BASE_REF} AS scratch_base

# --- Stage 1: builder ---------------------------------------------------------
FROM ${FORGE_BUILDER_REF} AS builder

ARG GIT_SHA=unknown
ARG BUILD_TIMESTAMP=unknown

COPY sid-pins/ /etc/apt/preferences.d/

# forge-builder-trixie cleared apt lists + applied apt-upgrade. Re-populate
# the lists and install redis. apt-upgrade NOT repeated (pre-done upstream).
# hadolint ignore=DL3008
RUN set -eux; \
    apt-get update; \
    apt-get -y --no-install-recommends install redis-server redis-tools; \
    rm -rf /var/lib/apt/lists/*

# FG-020: embedded SBOM from builder-stage dpkg. syft is pre-installed by
# forge-builder-trixie (FG-025). Scan AFTER apt-get install so the overlay
# packages (redis + its runtime deps) are captured.
RUN set -eux; \
    syft dir:/ --override-default-catalogers dpkg-db-cataloger -o cyclonedx-json > /sbom.json

# Pull baseline's /etc/passwd + /etc/group so we APPEND the redis user
# instead of overwriting (FG-005 append pattern — future baseline additions
# propagate automatically).
COPY --from=scratch_base /etc/passwd /tmp/baseline-passwd
COPY --from=scratch_base /etc/group  /tmp/baseline-group

# Assemble the redis overlay. Baseline supplies the core glibc + TLS + DNS
# closure (libc/m/ssl/crypto/z/zstd/gcc_s/nss_*). We add:
#   - redis-server + redis-cli + aof/rdb check binaries
#   - redis-specific libs (libatomic libcap libjemalloc liblzf libstdc++ libsystemd)
#   - redis service user at uid 999 (Docker Hub convention)
#   - writable /data for optional persistence (owned by redis uid 999)
RUN set -eux; \
    install -d /out/etc /out/usr/bin /out/lib/x86_64-linux-gnu /out/data; \
    for b in redis-server redis-cli redis-check-aof redis-check-rdb; do \
      cp "/usr/bin/${b}" "/out/usr/bin/${b}"; \
    done; \
    # Redis-specific libs on top of baseline. Baseline provides
    # libc/m/ssl/crypto/z/zstd/gcc_s; we add the rest.
    for lib in libatomic.so.1 libcap.so.2 libjemalloc.so.2 liblzf.so.1 \
               libstdc++.so.6 libsystemd.so.0; do \
      cp "/lib/x86_64-linux-gnu/${lib}" "/out/lib/x86_64-linux-gnu/${lib}"; \
    done; \
    # Append redis service user (uid 999 — Docker Hub convention) to
    # baseline's /etc/passwd + /etc/group.
    redis_uid=999; redis_gid=999; \
    cat /tmp/baseline-passwd                                                     > /out/etc/passwd; \
    printf 'redis:x:%s:%s:redis:/data:/sbin/nologin\n' \
      "${redis_uid}" "${redis_gid}"                                              >> /out/etc/passwd; \
    cat /tmp/baseline-group                                                      > /out/etc/group; \
    printf 'redis:x:%s:\n' "${redis_gid}"                                       >> /out/etc/group; \
    # /data is the default working/persistence dir (upstream redis convention).
    chown "${redis_uid}:${redis_gid}" /out/data; \
    chmod 0750 /out/data

# --- Stage 2: runtime (scratch) -----------------------------------------------
FROM scratch AS runtime

ARG GIT_SHA=unknown
ARG BUILD_TIMESTAMP=unknown

LABEL org.opencontainers.image.source="https://github.com/bboortz/forge"
LABEL org.opencontainers.image.licenses="Apache-2.0"
LABEL org.opencontainers.image.description="Minimal, continuously patched Redis 8 base image (FROM scratch runtime, derives from scratch-base-trixie)"
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

# hadolint DL3066: numeric uid — the redis user IS present in /etc/passwd
# at uid 999 (verified by smoke_user_redis.sh), but hadolint can't reason
# across stages, and numeric form is the robust recommendation.
USER 999:999
WORKDIR /data
EXPOSE 6379
ENTRYPOINT ["/usr/bin/redis-server"]
CMD []
