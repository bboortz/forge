# syntax=docker/dockerfile:1.7
#
# Two-stage. Builder is python:3.13-slim-trixie (matches baseline glibc).
# Runtime FROM scratch, composed of:
#   1. scratch-base-trixie (glibc + TLS + DNS + zoneinfo + /etc)
#   2. postgres-specific overlay (binaries + ICU + krb5 + ldap + xml + pam
#      + readline + libpq + share data + postgres user)
#
# No LLVM JIT (postgresql-17-jit omitted — saves ~100 MB of libLLVM for
# marginal gain). No shell → initdb cannot run in-scratch; use a shelled
# sidecar for one-time cluster init (see FG-007 smoke_server_accepts.sh).

ARG SCRATCH_BASE_REF=ghcr.io/bboortz/scratch-base-trixie:latest
# FG-025 Phase 2: builder stage FROMs the shared forge-builder-trixie image
# (apt-upgraded + CA certs + syft pre-installed).
ARG FORGE_BUILDER_REF=ghcr.io/bboortz/forge-builder-trixie:latest

# --- Stage 0: baseline reference ---------------------------------------------
FROM ${SCRATCH_BASE_REF} AS scratch_base

# --- Stage 1: builder ---------------------------------------------------------
FROM ${FORGE_BUILDER_REF} AS builder

ARG GIT_SHA=unknown
ARG BUILD_TIMESTAMP=unknown

COPY sid-pins/ /etc/apt/preferences.d/

# forge-builder-trixie cleared apt lists + applied apt-upgrade. Re-populate
# the lists and install postgres-specific packages. apt-upgrade NOT repeated.
# DL3008: postgres + deps float within the trixie release channel.
# hadolint ignore=DL3008
RUN set -eux; \
    apt-get update; \
    apt-get -y --no-install-recommends install \
      postgresql-17 postgresql-client-17 \
      locales libnss-db ; \
    rm -rf /var/lib/apt/lists/*

# FG-020: embedded SBOM from builder-stage dpkg. syft is pre-installed by
# forge-builder-trixie (FG-025). Scan AFTER apt-get install.
RUN set -eux; \
    syft dir:/ --override-default-catalogers dpkg-db-cataloger -o cyclonedx-json > /sbom.json

# Pull baseline's /etc/passwd + /etc/group so we APPEND the postgres user
# instead of overwriting (FG-005 append pattern — future baseline additions
# propagate automatically).
COPY --from=scratch_base /etc/passwd /tmp/baseline-passwd
COPY --from=scratch_base /etc/group  /tmp/baseline-group

# Assemble the postgres-specific overlay. Baseline supplies the core glibc +
# TLS + DNS + zoneinfo + minimal /etc. We add postgres binaries, postgres-
# specific shared libs (ICU + krb5 + ldap + pam + xml + readline + libpq +
# ...), /usr/share/postgresql/17 shared data, the postgres service user at
# uid 999, and writable data/run directories.
RUN set -eux; \
    PG=/usr/lib/postgresql/17; \
    install -d /out/etc /out/lib/x86_64-linux-gnu \
               /out/usr/lib/postgresql/17/bin /out/usr/lib/postgresql/17/lib \
               /out/usr/share/postgresql \
               /out/var/lib/postgresql /out/var/run/postgresql; \
    # Binary subset (no Debian wrappers; they need perl + multi-cluster
    # config we deliberately don't ship).
    for b in postgres initdb pg_ctl pg_isready psql pg_dump \
             pg_restore pg_config pg_dumpall; do \
      cp "${PG}/bin/${b}" "/out/usr/lib/postgresql/17/bin/${b}"; \
    done; \
    cp -r "${PG}/lib" "/out/usr/lib/postgresql/17/"; \
    cp -r /usr/share/postgresql/17 /out/usr/share/postgresql/17; \
    # Postgres-specific libs on top of baseline (baseline supplies
    # libc/m/dl/pthread/crypt/gcc_s/ssl/crypto/z/zstd/nss_* — NOT libutil).
    for lib in libutil.so.1 liblz4.so.1 libxml2.so.2 libpam.so.0 \
               libxxhash.so.0 liblzma.so.5 \
               libgssapi_krb5.so.2 libkrb5.so.3 libk5crypto.so.3 \
               libcom_err.so.2 libkrb5support.so.0 libkeyutils.so.1 \
               libldap.so.2 liblber.so.2 libsasl2.so.2 \
               libicui18n.so.76 libicuuc.so.76 libicudata.so.76 \
               libsystemd.so.0 libaudit.so.1 libcap.so.2 libcap-ng.so.0 \
               libstdc++.so.6 libreadline.so.8 libtinfo.so.6 \
               libpq.so.5; do \
      cp "/lib/x86_64-linux-gnu/${lib}" "/out/lib/x86_64-linux-gnu/${lib}"; \
    done; \
    # Append postgres service user (uid 999 — Docker Hub convention) to
    # baseline's /etc/passwd + /etc/group.
    pg_uid=999; pg_gid=999; \
    cat /tmp/baseline-passwd                                                     > /out/etc/passwd; \
    printf 'postgres:x:%s:%s:postgres:/var/lib/postgresql:/sbin/nologin\n' \
      "${pg_uid}" "${pg_gid}"                                                    >> /out/etc/passwd; \
    cat /tmp/baseline-group                                                      > /out/etc/group; \
    printf 'postgres:x:%s:\n' "${pg_gid}"                                       >> /out/etc/group; \
    chown -R "${pg_uid}:${pg_gid}" /out/var/lib/postgresql /out/var/run/postgresql

# --- Stage 2: runtime (scratch) -----------------------------------------------
FROM scratch AS runtime

ARG GIT_SHA=unknown
ARG BUILD_TIMESTAMP=unknown

LABEL org.opencontainers.image.source="https://github.com/bboortz/forge"
LABEL org.opencontainers.image.licenses="Apache-2.0"
LABEL org.opencontainers.image.description="Minimal, continuously patched PostgreSQL 17 base image (FROM scratch runtime, derives from scratch-base-trixie, no LLVM JIT)"
LABEL org.opencontainers.image.revision="${GIT_SHA}"
LABEL org.opencontainers.image.created="${BUILD_TIMESTAMP}"

# DL3067 silenced: copying the entire baseline is the FG-005 composition.
# hadolint ignore=DL3067
COPY --from=scratch_base / /
COPY --from=builder /out /
# FG-020: SBOM from builder (dpkg-aware). scan-regression uses `grype sbom:`
# so Debian backports are honored.
COPY --from=builder /sbom.json /sbom.json

# FG-009: baseline's ENV SSL_CERT_FILE does NOT propagate through COPY —
# re-declare here so postgres can do outbound TLS (e.g. postgres_fdw
# connecting to a TLS-encrypted remote instance, extensions issuing HTTPS
# calls). See docs/baseline-contract.md § "TLS trust".
ENV PATH=/usr/lib/postgresql/17/bin \
    PGDATA=/var/lib/postgresql/data \
    LANG=C.UTF-8 \
    SSL_CERT_FILE=/etc/ssl/certs/ca-certificates.crt \
    SSL_CERT_DIR=/etc/ssl/certs

EXPOSE 5432
# USER uses the numeric form (hadolint DL3066) — same uid pinned in /etc/passwd.
USER 999:999

CMD ["postgres"]
