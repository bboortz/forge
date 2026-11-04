# syntax=docker/dockerfile:1.7
#
# Two-stage build. Builder is python:3.13-slim-trixie (same base as
# python-scratch-trixie so the glibc/libssl/libcrypt/libz versions used
# here match the python-scratch runtime's byte-for-byte — important for
# the forthcoming scratch-base-trixie refactor). Runtime is FROM scratch:
# no shell, no apt, no dpkg database. nginx 1.26.3 from Debian trixie.

ARG DEBIAN_BASE=python:3.13-slim-trixie

# --- Stage 1: builder ---------------------------------------------------------
FROM ${DEBIAN_BASE} AS builder

ARG GIT_SHA=unknown
ARG BUILD_TIMESTAMP=unknown

COPY sid-pins/ /etc/apt/preferences.d/

# DL3005: apt-get upgrade IS the point.
# DL3008: trixie's nginx + deps float within the release channel.
# hadolint ignore=DL3005,DL3008
RUN set -eux; \
    apt-get update; \
    apt-get -y --no-install-recommends upgrade; \
    apt-get -y --no-install-recommends install nginx ca-certificates; \
    rm -rf /var/lib/apt/lists/*

# Assemble the scratch tree.
RUN set -eux; \
    install -d /out/usr/sbin /out/usr/share/nginx/html \
               /out/etc /out/etc/nginx /out/etc/ssl/certs \
               /out/lib64 /out/lib/x86_64-linux-gnu \
               /out/tmp /out/var/log/nginx /out/var/cache/nginx \
               /out/var/lib/nginx /out/var/lib/nginx/body \
               /out/var/lib/nginx/fastcgi /out/var/lib/nginx/proxy \
               /out/var/lib/nginx/scgi /out/var/lib/nginx/uwsgi \
               /out/usr/share/zoneinfo; \
    chown -R 33:33 /out/var/lib/nginx /out/var/log/nginx /out/var/cache/nginx; \
    chmod 1777 /out/tmp; \
    # nginx binary + ldd closure (over the baseline python-scratch libs).
    # Use plain `cp` (not `cp -a`) so symlinks dereference and we end up
    # with real files at each SONAME path — same pattern as python-scratch.
    # Using `cp -a` instead left /lib64/ld-linux-x86-64.so.2 as a broken
    # symlink pointing at /lib/x86_64-linux-gnu/ld-linux-x86-64.so.2 which
    # didn't exist in the image, so the binary failed to exec.
    cp    /usr/sbin/nginx                            /out/usr/sbin/nginx; \
    cp    /lib64/ld-linux-x86-64.so.2                /out/lib64/; \
    for lib in libc.so.6 libm.so.6 libdl.so.2 libpthread.so.0 \
               libcrypt.so.1 libpcre2-8.so.0 \
               libssl.so.3 libcrypto.so.3 \
               libz.so.1 libzstd.so.1 \
               libgcc_s.so.1 \
               libnss_dns.so.2 libnss_files.so.2 libresolv.so.2; do \
      cp "/lib/x86_64-linux-gnu/$lib" "/out/lib/x86_64-linux-gnu/$lib"; \
    done; \
    # trust anchors + nss config + minimal /etc/passwd+group with www-data (uid 33)
    cp /etc/ssl/certs/ca-certificates.crt            /out/etc/ssl/certs/; \
    cp /etc/nsswitch.conf                            /out/etc/; \
    cp -r /usr/share/zoneinfo                        /out/usr/share/; \
    printf 'root:x:0:0:root:/:/sbin/nologin\n'          >  /out/etc/passwd; \
    printf 'www-data:x:33:33:www-data:/:/sbin/nologin\n' >> /out/etc/passwd; \
    printf 'nobody:x:65534:65534:nobody:/:/sbin/nologin\n' >> /out/etc/passwd; \
    printf 'root:x:0:\nwww-data:x:33:\nnobody:x:65534:\n'  >  /out/etc/group

# Ship the minimal self-contained config + default welcome page.
COPY nginx.conf   /out/etc/nginx/nginx.conf
COPY index.html   /out/usr/share/nginx/html/index.html

# --- Stage 2: runtime (scratch) -----------------------------------------------
FROM scratch AS runtime

ARG GIT_SHA=unknown
ARG BUILD_TIMESTAMP=unknown

LABEL org.opencontainers.image.source="https://github.com/bboortz/forge"
LABEL org.opencontainers.image.licenses="Apache-2.0"
LABEL org.opencontainers.image.description="Minimal, continuously patched nginx 1.26 base image (FROM scratch runtime, trixie-derived)"
LABEL org.opencontainers.image.revision="${GIT_SHA}"
LABEL org.opencontainers.image.created="${BUILD_TIMESTAMP}"

COPY --from=builder /out /

ENV SSL_CERT_FILE=/etc/ssl/certs/ca-certificates.crt \
    PATH=/usr/sbin

EXPOSE 80

ENTRYPOINT ["/usr/sbin/nginx"]
CMD ["-g", "daemon off;"]
