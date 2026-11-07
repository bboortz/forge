# syntax=docker/dockerfile:1.7
#
# Shared signed foundation for every Forge scratch image (FG-005).
# Contains the intersection of python-scratch-trixie, nginx-scratch-trixie,
# and postgres-scratch-trixie closures — what ALL three need:
#   - dynamic linker + core glibc
#   - TLS trust (OpenSSL libs + CA bundle)
#   - common compression (libz + libzstd)
#   - DNS resolution (nss plugins + nsswitch.conf)
#   - minimal /etc identity (root + nobody; each derivative appends its own)
#   - /usr/share/zoneinfo
#   - writable /tmp
#
# Everything language- or app-specific stays in the derivative's own image:
# interpreters, libpcre, libicu, libkrb5, libldap, libxml, libreadline, etc.
#
# Derivatives consume it via:
#   ARG SCRATCH_BASE_REF=ghcr.io/bboortz/scratch-base-trixie:latest
#   FROM ${SCRATCH_BASE_REF} AS scratch_base
#   ...
#   FROM scratch AS runtime
#   COPY --from=scratch_base / /
#   COPY --from=builder /out /

ARG DEBIAN_BASE=python:3.13-slim-trixie

# --- Stage 1: builder ---------------------------------------------------------
FROM ${DEBIAN_BASE} AS builder

ARG GIT_SHA=unknown
ARG BUILD_TIMESTAMP=unknown

COPY sid-pins/ /etc/apt/preferences.d/

# hadolint ignore=DL3005,DL3008
RUN set -eux; \
    apt-get update; \
    apt-get -y --no-install-recommends upgrade; \
    apt-get -y --no-install-recommends install ca-certificates curl; \
    rm -rf /var/lib/apt/lists/*

# FG-020: SBOM from builder-stage dpkg. Each scratch derivative gets its
# own /sbom.json (from its own builder), but scratch-base-trixie itself
# also carries one so direct consumers of the baseline see Debian version
# detail. scan-regression reads /sbom.json via `grype sbom:`.
ARG SYFT_VERSION=v1.57.0
# hadolint ignore=DL4006
RUN set -eux; \
    curl -sSfL "https://raw.githubusercontent.com/anchore/syft/main/install.sh" \
      | sh -s -- -b /usr/local/bin "${SYFT_VERSION}"; \
    apt-get -y --purge --auto-remove remove curl; \
    syft dir:/ --override-default-catalogers dpkg-db-cataloger -o cyclonedx-json > /sbom.json

# Assemble the baseline tree — the common standard every Forge scratch
# image can rely on. Documented in docs/baseline-contract.md.
RUN set -eux; \
    install -d /out/etc /out/etc/ssl/certs /out/lib64 /out/lib/x86_64-linux-gnu \
               /out/usr/share/zoneinfo /out/tmp /out/var/tmp /out/nonroot; \
    chmod 1777 /out/tmp /out/var/tmp; \
    # Dynamic linker (plain cp so the Debian multiarch symlink dereferences;
    # cp -a would leave /lib64/ld-linux-* as a dangling symlink — FG-006 lesson).
    cp /lib64/ld-linux-x86-64.so.2 /out/lib64/; \
    # Core glibc satellites everyone's dyn-linker closure pulls in (strict
    # intersection of python + nginx + postgres). libutil is deliberately
    # NOT here — nginx doesn't need it; python + postgres add it in their
    # own overlay.
    for lib in libc.so.6 libm.so.6 libdl.so.2 libpthread.so.0 \
               libcrypt.so.1 libgcc_s.so.1 \
               libssl.so.3 libcrypto.so.3 \
               libz.so.1 libzstd.so.1 \
               libnss_dns.so.2 libnss_files.so.2 libresolv.so.2; do \
      cp "/lib/x86_64-linux-gnu/${lib}" "/out/lib/x86_64-linux-gnu/${lib}"; \
    done; \
    # TLS trust + nss config.
    cp /etc/ssl/certs/ca-certificates.crt /out/etc/ssl/certs/; \
    cp /etc/nsswitch.conf                 /out/etc/; \
    # Zoneinfo (full tree, preserving symlinks like UTC → Etc/UTC).
    cp -r /usr/share/zoneinfo             /out/usr/share/; \
    # Network-resolution data (FG-008): socket.getservbyname, getprotobyname,
    # and localhost loopback lookups all silently fail without these.
    cp /etc/services                      /out/etc/services; \
    cp /etc/protocols                     /out/etc/protocols; \
    printf '127.0.0.1\tlocalhost\n::1\tlocalhost ip6-localhost ip6-loopback\n' \
                                          >  /out/etc/hosts; \
    # /etc/localtime → UTC (FG-008): many apps read /etc/localtime first;
    # without it they fall through to inconsistent defaults.
    ln -s /usr/share/zoneinfo/Etc/UTC /out/etc/localtime; \
    # Identity file: root + nonroot (65532, distroless convention) + nobody.
    # Derivatives APPEND their service user (FG-005 pattern) rather than
    # overwrite.
    printf 'root:x:0:0:root:/:/sbin/nologin\n'                                 >  /out/etc/passwd; \
    printf 'nonroot:x:65532:65532:nonroot:/nonroot:/sbin/nologin\n'            >> /out/etc/passwd; \
    printf 'nobody:x:65534:65534:nobody:/:/sbin/nologin\n'                     >> /out/etc/passwd; \
    printf 'root:x:0:\nnonroot:x:65532:\nnobody:x:65534:\n'                    >  /out/etc/group; \
    # /nonroot home dir owned by uid 65532 (matches distroless :nonroot).
    chown 65532:65532 /out/nonroot; \
    chmod 0755        /out/nonroot

# --- Stage 2: runtime (scratch) -----------------------------------------------
FROM scratch AS runtime

ARG GIT_SHA=unknown
ARG BUILD_TIMESTAMP=unknown

LABEL org.opencontainers.image.source="https://github.com/bboortz/forge"
LABEL org.opencontainers.image.licenses="Apache-2.0"
LABEL org.opencontainers.image.description="Shared signed baseline for Forge scratch images (glibc + TLS + DNS + zoneinfo + minimal /etc)"
LABEL org.opencontainers.image.revision="${GIT_SHA}"
LABEL org.opencontainers.image.created="${BUILD_TIMESTAMP}"

COPY --from=builder /out /
# FG-020: SBOM from builder-stage dpkg. scan-regression reads this via
# `grype sbom:` so Debian version detail (and backports) are honored.
COPY --from=builder /sbom.json /sbom.json

ENV SSL_CERT_FILE=/etc/ssl/certs/ca-certificates.crt
