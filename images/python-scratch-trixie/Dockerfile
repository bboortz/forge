# syntax=docker/dockerfile:1.7
#
# Two-stage build: builder on python:3.13-slim-trixie so the ldd closure
# matches what we COPY into scratch. Runtime is FROM scratch — no shell,
# no apt, no dpkg database. grype against this image finds zero Debian-
# source matches; every surviving finding is a PyPI dep the consumer
# installed themselves.

ARG DEBIAN_BASE=python:3.13-slim-trixie

# --- Stage 1: builder ---------------------------------------------------------
FROM ${DEBIAN_BASE} AS builder

ARG GIT_SHA=unknown
ARG BUILD_TIMESTAMP=unknown

COPY sid-pins/ /etc/apt/preferences.d/

# DL3005: apt-get upgrade IS the point (daily rebuild cadence).
# DL3008: ca-certificates is pinned by the trixie release channel, not by us;
#         the daily rebuild tracks whatever ca-certificates ships in trixie.
# hadolint ignore=DL3005,DL3008
RUN set -eux; \
    apt-get update; \
    apt-get -y --no-install-recommends upgrade; \
    apt-get -y --no-install-recommends install ca-certificates; \
    rm -rf /var/lib/apt/lists/*

# Collect the file closure into a staging dir so the final stage's COPY list
# is a single explicit tree, not an ad-hoc list of /lib paths. Pre-populate
# /etc/passwd + /etc/group minimal entries so getpwuid(geteuid()) won't crash
# in a scratch container running as uid 0.
RUN set -eux; \
    install -d /out/bin /out/lib64 /out/lib/x86_64-linux-gnu \
               /out/usr/local/bin /out/usr/local/lib \
               /out/etc/ssl/certs /out/etc \
               /out/usr/share/zoneinfo /out/tmp; \
    chmod 1777 /out/tmp; \
    # Interpreter (binary + python3 + python symlinks) + stdlib + the shared
    # libpython that the interpreter dynamically links against (archive mode so
    # symlinks survive).
    install -d /out/usr/local/lib; \
    cp -a /usr/local/bin/python3.13                    /out/usr/local/bin/python3.13; \
    cp -a /usr/local/bin/python3                       /out/usr/local/bin/python3 2>/dev/null || ln -s python3.13 /out/usr/local/bin/python3; \
    cp -a /usr/local/bin/python                        /out/usr/local/bin/python   2>/dev/null || ln -s python3   /out/usr/local/bin/python; \
    cp -r /usr/local/lib/python3.13                    /out/usr/local/lib/python3.13; \
    cp -a /usr/local/lib/libpython3*.so*               /out/usr/local/lib/; \
    # Dynamic linker
    cp /lib64/ld-linux-x86-64.so.2                     /out/lib64/; \
    # Core libs that python3 interpreter dlopens (ldd python3.13)
    for lib in libc.so.6 libm.so.6 libdl.so.2 libpthread.so.0 libutil.so.1 \
               libz.so.1 libcrypt.so.1; do \
      cp "/lib/x86_64-linux-gnu/$lib" "/out/lib/x86_64-linux-gnu/$lib" 2>/dev/null || true; \
    done; \
    # Libs that stdlib C-extensions dlopen (ssl, hashlib, bz2, lzma, xml, ctypes, sqlite3, zoneinfo)
    for lib in libssl.so.3 libcrypto.so.3 libbz2.so.1.0 liblzma.so.5 libzstd.so.1 \
               libexpat.so.1 libffi.so.8 libsqlite3.so.0 libgcc_s.so.1 \
               libnsl.so.2 libtirpc.so.3; do \
      cp "/lib/x86_64-linux-gnu/$lib" "/out/lib/x86_64-linux-gnu/$lib" 2>/dev/null || true; \
    done; \
    # NSS plugins for getaddrinfo (DNS + /etc/hosts)
    for lib in libnss_dns.so.2 libnss_files.so.2 libresolv.so.2; do \
      cp "/lib/x86_64-linux-gnu/$lib" "/out/lib/x86_64-linux-gnu/$lib" 2>/dev/null || true; \
    done; \
    # CA bundle + zoneinfo + nss config
    cp /etc/ssl/certs/ca-certificates.crt              /out/etc/ssl/certs/; \
    cp -r /usr/share/zoneinfo                          /out/usr/share/; \
    cp /etc/nsswitch.conf                              /out/etc/; \
    # Minimal passwd/group so python's pwd/grp modules and subprocess don't crash
    printf 'root:x:0:0:root:/:/sbin/nologin\n'         >  /out/etc/passwd; \
    printf 'nobody:x:65534:65534:nobody:/:/sbin/nologin\n' >> /out/etc/passwd; \
    printf 'root:x:0:\nnobody:x:65534:\n'              >  /out/etc/group; \
    # Pip + its vendored deps (so pip install --target <dir> <wheel> works at
    # runtime). Archive mode so pip, pip3, pip3.13 symlinks all survive.
    cp -a /usr/local/bin/pip*                          /out/usr/local/bin/ 2>/dev/null || true; \
    # Strip python bytecode caches to trim size
    find /out/usr/local/lib/python3.13 -type d -name __pycache__ -exec rm -rf {} + || true; \
    find /out/usr/local/lib/python3.13 -name '*.pyc' -delete || true; \
    # Drop the test suite from stdlib — big and unused in production
    rm -rf /out/usr/local/lib/python3.13/test /out/usr/local/lib/python3.13/idlelib || true

# --- Stage 2: runtime (scratch) -----------------------------------------------
FROM scratch AS runtime

ARG GIT_SHA=unknown
ARG BUILD_TIMESTAMP=unknown

LABEL org.opencontainers.image.source="https://github.com/bboortz/forge"
LABEL org.opencontainers.image.licenses="Apache-2.0"
LABEL org.opencontainers.image.description="Minimal, continuously patched Python 3.13 base image (FROM scratch runtime, trixie-derived)"
LABEL org.opencontainers.image.revision="${GIT_SHA}"
LABEL org.opencontainers.image.created="${BUILD_TIMESTAMP}"

COPY --from=builder /out /

# SSL_CERT_FILE points apps at the CA bundle location that matches our Debian
# heritage; required because scratch has no default /etc/pki or OpenSSL config.
ENV SSL_CERT_FILE=/etc/ssl/certs/ca-certificates.crt \
    PATH=/usr/local/bin \
    LANG=C.UTF-8

CMD ["python3.13"]
