# syntax=docker/dockerfile:1.7
#
# Two-stage. Builder is python:3.14-slim-trixie (matches baseline glibc).
# Runtime FROM scratch, composed of:
#   1. scratch-base-trixie (glibc + TLS + DNS + zoneinfo + /etc)
#   2. postgres-specific overlay (binaries + ICU + krb5 + ldap + xml + pam
#      + readline + libpq + share data + postgres user)
#
# No LLVM JIT (postgresql-18-jit omitted — saves ~100 MB of libLLVM for
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

# FG-026: PostgreSQL 18 is not in Debian trixie yet — pull from the PGDG
# official apt repository (same source Docker Hub's `postgres:18` image
# uses). forge-builder-trixie cleared apt lists + applied apt-upgrade;
# we add the PGDG source, then install postgres 18 + extras.
# DL3008: postgres + deps float within the trixie release channel.
# hadolint ignore=DL3008,DL4006
RUN set -eux; \
    apt-get update; \
    apt-get -y --no-install-recommends install gnupg wget; \
    wget -qO- https://www.postgresql.org/media/keys/ACCC4CF8.asc \
      | gpg --dearmor -o /usr/share/keyrings/pgdg.gpg; \
    echo "deb [signed-by=/usr/share/keyrings/pgdg.gpg] https://apt.postgresql.org/pub/repos/apt trixie-pgdg main" \
      > /etc/apt/sources.list.d/pgdg.list; \
    apt-get update; \
    apt-get -y --no-install-recommends install \
      postgresql-18 postgresql-client-18 \
      locales libnss-db; \
    apt-get -y --purge --auto-remove remove gnupg wget; \
    rm -rf /var/lib/apt/lists/*

# FG-033: compile the two UTF-8 locales we promise in PROMISES. Using
# localedef (not locale-gen) so we get EXACTLY these two locales —
# a bare `locale-gen` with a full /etc/locale.gen would bloat the
# archive by ~55 MB. `--no-archive` writes each locale to its own
# /usr/lib/locale/<name>.utf8/ dir (and keeps the archive alongside)
# so the overlay COPY can grab deterministic per-locale directories.
# DL4006 ignore: the set -eux + exit-chaining is enough for our failure
# semantics — bringing in a bash SHELL directive just for pipefail here
# would affect every subsequent RUN layer.
# hadolint ignore=DL4006
RUN set -eux; \
    localedef --no-archive -c -i C     -f UTF-8 C.UTF-8; \
    localedef --no-archive -c -i en_US -f UTF-8 en_US.UTF-8; \
    test -f /usr/lib/locale/C.utf8/LC_CTYPE; \
    test -f /usr/lib/locale/en_US.utf8/LC_CTYPE; \
    locale -a | grep -qx C.utf8; \
    locale -a | grep -qx en_US.utf8

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
# ...), /usr/share/postgresql/18 shared data, the postgres service user at
# uid 999, and writable data/run directories.
RUN set -eux; \
    PG=/usr/lib/postgresql/18; \
    install -d /out/etc /out/lib/x86_64-linux-gnu \
               /out/usr/lib/postgresql/18/bin /out/usr/lib/postgresql/18/lib \
               /out/usr/share/postgresql \
               /out/usr/lib/locale \
               /out/var/lib/postgresql /out/var/run/postgresql; \
    # FG-033: ship both compiled UTF-8 locales + the locale archive.
    cp -r /usr/lib/locale/C.utf8     /out/usr/lib/locale/C.utf8; \
    cp -r /usr/lib/locale/en_US.utf8 /out/usr/lib/locale/en_US.utf8; \
    cp /usr/lib/locale/locale-archive /out/usr/lib/locale/locale-archive 2>/dev/null || true; \
    # Binary subset (no Debian wrappers; they need perl + multi-cluster
    # config we deliberately don't ship).
    for b in postgres initdb pg_ctl pg_isready psql pg_dump \
             pg_restore pg_config pg_dumpall; do \
      cp "${PG}/bin/${b}" "/out/usr/lib/postgresql/18/bin/${b}"; \
    done; \
    cp -r "${PG}/lib" "/out/usr/lib/postgresql/18/"; \
    cp -r /usr/share/postgresql/18 /out/usr/share/postgresql/18; \
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
               libnuma.so.1 liburing.so.2 \
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
LABEL org.opencontainers.image.description="Minimal, continuously patched PostgreSQL 18 base image (FROM scratch runtime, derives from scratch-base-trixie, no LLVM JIT)"
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
ENV PATH=/usr/lib/postgresql/18/bin \
    PGDATA=/var/lib/postgresql/data \
    LANG=C.UTF-8 \
    SSL_CERT_FILE=/etc/ssl/certs/ca-certificates.crt \
    SSL_CERT_DIR=/etc/ssl/certs

EXPOSE 5432
# USER uses the numeric form (hadolint DL3066) — same uid pinned in /etc/passwd.
USER 999:999

CMD ["postgres"]
