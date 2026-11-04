# syntax=docker/dockerfile:1.7
#
# Two-stage. Builder is python:3.13-slim-trixie (matches the baseline's
# glibc/libssl versions). Runtime is FROM scratch, composed by overlaying:
#   1. scratch-base-trixie (shared glibc + TLS + DNS + zoneinfo + /etc)
#   2. nginx-specific overlay (binary + libpcre2 + config + www-data user)

ARG SCRATCH_BASE_REF=ghcr.io/bboortz/scratch-base-trixie:latest
ARG DEBIAN_BASE=python:3.13-slim-trixie

# --- Stage 0: baseline reference ---------------------------------------------
FROM ${SCRATCH_BASE_REF} AS scratch_base

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

# Assemble the nginx overlay (baseline already supplies glibc + TLS + DNS
# + zoneinfo + /etc/passwd+group with root/nobody). We add nginx + its one
# unique closure lib (libpcre2-8), nginx's writable dirs, our minimal config,
# and the www-data user line that overwrites baseline's /etc/passwd+group.
RUN set -eux; \
    install -d /out/usr/sbin /out/usr/share/nginx/html \
               /out/etc /out/etc/nginx \
               /out/lib/x86_64-linux-gnu \
               /out/var/log/nginx /out/var/cache/nginx \
               /out/var/lib/nginx /out/var/lib/nginx/body \
               /out/var/lib/nginx/fastcgi /out/var/lib/nginx/proxy \
               /out/var/lib/nginx/scgi /out/var/lib/nginx/uwsgi; \
    # nginx binary + its one lib not in baseline.
    cp /usr/sbin/nginx                    /out/usr/sbin/nginx; \
    cp /lib/x86_64-linux-gnu/libpcre2-8.so.0 /out/lib/x86_64-linux-gnu/libpcre2-8.so.0; \
    # Overwrite baseline's /etc/passwd+group to add the www-data (uid 33)
    # service user alongside root + nobody.
    printf 'root:x:0:0:root:/:/sbin/nologin\n'              >  /out/etc/passwd; \
    printf 'www-data:x:33:33:www-data:/:/sbin/nologin\n'    >> /out/etc/passwd; \
    printf 'nobody:x:65534:65534:nobody:/:/sbin/nologin\n'  >> /out/etc/passwd; \
    printf 'root:x:0:\nwww-data:x:33:\nnobody:x:65534:\n'   >  /out/etc/group; \
    chown -R 33:33 /out/var/lib/nginx /out/var/log/nginx /out/var/cache/nginx

COPY nginx.conf /out/etc/nginx/nginx.conf
COPY index.html /out/usr/share/nginx/html/index.html

# --- Stage 2: runtime (scratch) -----------------------------------------------
FROM scratch AS runtime

ARG GIT_SHA=unknown
ARG BUILD_TIMESTAMP=unknown

LABEL org.opencontainers.image.source="https://github.com/bboortz/forge"
LABEL org.opencontainers.image.licenses="Apache-2.0"
LABEL org.opencontainers.image.description="Minimal, continuously patched nginx 1.26 base image (FROM scratch runtime, derives from scratch-base-trixie)"
LABEL org.opencontainers.image.revision="${GIT_SHA}"
LABEL org.opencontainers.image.created="${BUILD_TIMESTAMP}"

# Baseline first, nginx overlay on top. Later COPY wins on path collision —
# critical for /etc/passwd + /etc/group which gain www-data here.
# DL3067 silenced: copying the entire baseline is the FG-005 composition.
# hadolint ignore=DL3067
COPY --from=scratch_base / /
COPY --from=builder /out /

ENV PATH=/usr/sbin

EXPOSE 80

ENTRYPOINT ["/usr/sbin/nginx"]
CMD ["-g", "daemon off;"]
