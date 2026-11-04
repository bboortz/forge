# syntax=docker/dockerfile:1.7
#
# Two-stage build. Builder is python:3.13-slim-trixie (same base as python-
# scratch and nginx-scratch so the glibc/libssl versions line up). Runtime
# is FROM scratch: no shell, no apt, no dpkg database.
#
# Ships PostgreSQL 17 (trixie's default; 18 is not in trixie yet). LLVM JIT
# is NOT included — postgresql-17-jit would add ~100 MB of libLLVM for
# marginal query-speed benefit most consumers don't need. Consumers who
# need JIT use the slim variant (future postgres-slim-trixie) or build on
# this image and add JIT themselves.

ARG DEBIAN_BASE=python:3.13-slim-trixie

# --- Stage 1: builder ---------------------------------------------------------
FROM ${DEBIAN_BASE} AS builder

ARG GIT_SHA=unknown
ARG BUILD_TIMESTAMP=unknown

COPY sid-pins/ /etc/apt/preferences.d/

# DL3005: apt-get upgrade IS the point.
# DL3008: postgres + deps float within the trixie release channel.
# hadolint ignore=DL3005,DL3008
RUN set -eux; \
    apt-get update; \
    apt-get -y --no-install-recommends upgrade; \
    apt-get -y --no-install-recommends install \
      postgresql-17 postgresql-client-17 ca-certificates \
      locales libnss-db ; \
    rm -rf /var/lib/apt/lists/*

# Assemble the scratch tree.
RUN set -eux; \
    PG=/usr/lib/postgresql/17; \
    install -d /out/etc /out/etc/ssl/certs \
               /out/lib64 /out/lib/x86_64-linux-gnu \
               /out/usr/lib/postgresql/17/bin /out/usr/lib/postgresql/17/lib \
               /out/usr/share/postgresql /out/usr/share/zoneinfo \
               /out/tmp /out/var/lib/postgresql /out/var/run/postgresql; \
    chmod 1777 /out/tmp; \
    # Binaries — ship a minimal useful set (skip the Debian wrapper scripts
    # like pg_ctlcluster and pg_lsclusters that need perl + /etc/postgresql
    # multi-cluster config).
    for b in postgres initdb pg_ctl pg_isready psql pg_dump \
             pg_restore pg_config pg_dumpall; do \
      cp "${PG}/bin/${b}" "/out/usr/lib/postgresql/17/bin/${b}"; \
    done; \
    # Shared libs postgres loads at startup / extension time.
    cp -r "${PG}/lib" "/out/usr/lib/postgresql/17/"; \
    # Shared data (timezone sets, encoding conversions, extension SQL,
    # locale). Needed by initdb + runtime.
    cp -r /usr/share/postgresql/17 /out/usr/share/postgresql/17; \
    # Dynamic linker + full ldd closure of postgres + psql + initdb unified.
    cp /lib64/ld-linux-x86-64.so.2 /out/lib64/; \
    for lib in libc.so.6 libm.so.6 libdl.so.2 libpthread.so.0 libutil.so.1 \
               libssl.so.3 libcrypto.so.3 libz.so.1 libzstd.so.1 \
               liblz4.so.1 libxml2.so.2 libpam.so.0 libcrypt.so.1 \
               libxxhash.so.0 liblzma.so.5 \
               libgssapi_krb5.so.2 libkrb5.so.3 libk5crypto.so.3 \
               libcom_err.so.2 libkrb5support.so.0 libkeyutils.so.1 \
               libldap.so.2 liblber.so.2 libsasl2.so.2 libresolv.so.2 \
               libicui18n.so.76 libicuuc.so.76 libicudata.so.76 \
               libsystemd.so.0 libaudit.so.1 libcap.so.2 libcap-ng.so.0 \
               libstdc++.so.6 libgcc_s.so.1 libreadline.so.8 \
               libtinfo.so.6 \
               libnss_dns.so.2 libnss_files.so.2; do \
      cp "/lib/x86_64-linux-gnu/${lib}" "/out/lib/x86_64-linux-gnu/${lib}"; \
    done; \
    # libpq is under /lib/x86_64-linux-gnu in trixie
    cp /lib/x86_64-linux-gnu/libpq.so.5 /out/lib/x86_64-linux-gnu/; \
    # TLS trust anchors + NSS config.
    cp /etc/ssl/certs/ca-certificates.crt /out/etc/ssl/certs/; \
    cp /etc/nsswitch.conf                 /out/etc/; \
    cp -r /usr/share/zoneinfo             /out/usr/share/; \
    # Pin postgres uid/gid to 999:999 — matches Docker Hub's official
    # postgres image so a data directory initdb'd there (or vice versa)
    # is read/write-compatible out of the box. Trixie's own postgresql-17
    # package assigns postgres uid dynamically (we saw 100), which caused
    # a "Permission denied" when our scratch server tried to read a cluster
    # that had been initdb'd by a uid-999 sidecar. 999 is the ecosystem
    # convention — pin and move on.
    pg_uid=999; pg_gid=999; \
    printf 'root:x:0:0:root:/:/sbin/nologin\n'                       >  /out/etc/passwd; \
    printf 'postgres:x:%s:%s:postgres:/var/lib/postgresql:/sbin/nologin\n' \
      "${pg_uid}" "${pg_gid}"                                        >> /out/etc/passwd; \
    printf 'nobody:x:65534:65534:nobody:/:/sbin/nologin\n'           >> /out/etc/passwd; \
    printf 'root:x:0:\npostgres:x:%s:\nnobody:x:65534:\n' "${pg_gid}" > /out/etc/group; \
    # Writable data + run dirs for the postgres user.
    chown -R "${pg_uid}:${pg_gid}" /out/var/lib/postgresql /out/var/run/postgresql

# --- Stage 2: runtime (scratch) -----------------------------------------------
FROM scratch AS runtime

ARG GIT_SHA=unknown
ARG BUILD_TIMESTAMP=unknown

LABEL org.opencontainers.image.source="https://github.com/bboortz/forge"
LABEL org.opencontainers.image.licenses="Apache-2.0"
LABEL org.opencontainers.image.description="Minimal, continuously patched PostgreSQL 17 base image (FROM scratch runtime, trixie-derived, no LLVM JIT)"
LABEL org.opencontainers.image.revision="${GIT_SHA}"
LABEL org.opencontainers.image.created="${BUILD_TIMESTAMP}"

COPY --from=builder /out /

# PATH exposes the binaries so `docker run <image> psql` works without the
# full /usr/lib/postgresql/17/bin prefix. Consumers who want the path
# explicit still have it.
ENV PATH=/usr/lib/postgresql/17/bin \
    SSL_CERT_FILE=/etc/ssl/certs/ca-certificates.crt \
    PGDATA=/var/lib/postgresql/data \
    LANG=C.UTF-8

EXPOSE 5432
# USER uses the numeric form (hadolint DL3066) — same uid pinned in /etc/passwd.
USER 999:999

# No ENTRYPOINT — consumers pick initdb / postgres / psql explicitly.
CMD ["postgres"]
