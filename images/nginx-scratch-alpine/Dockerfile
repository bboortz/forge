# syntax=docker/dockerfile:1.7
#
# FG-080: nginx-scratch-alpine — nginx on musl, FROM scratch. Builder stage
# apk-adds nginx from Alpine's package tree; runtime stage FROM scratch
# + overlay base/scratch-alpine-3 (musl + CA + nss + /etc identity) +
# COPY the nginx binary + ldd closure + conf tree.
#
# Chain (at FG-042 cap for Alpine):
#   alpine:3 → pre-builder/alpine-3 → base/alpine-3 (build) → scratch (runtime)
#   overlay: base/scratch-alpine-3 via COPY --from=
#
# Target size: ~15 MB. Compare nginx-scratch-trixie at ~16 MB.

ARG BASE_ALPINE_REF=ghcr.io/bboortz/base/alpine-3:3
ARG BASE_SCRATCH_ALPINE_REF=ghcr.io/bboortz/base/scratch-alpine-3:3
ARG HC_REF=ghcr.io/bboortz/hc:0.1.0

# --- Stage 0: scratch-musl overlay source -----------------------------------
FROM ${BASE_SCRATCH_ALPINE_REF} AS scratch_base_alpine

# --- Stage 1: hc binary source (FG-031 pattern) -----------------------------
FROM ${HC_REF} AS hc

# --- Stage 2: nginx builder --------------------------------------------------
# hadolint ignore=DL3002
FROM ${BASE_ALPINE_REF} AS builder
USER 0

ARG GIT_SHA=unknown
ARG BUILD_TIMESTAMP=unknown

# hadolint ignore=DL3018
RUN apk add --no-cache nginx

# Stage the nginx runtime layout into /out. Mirrors the
# memory/scratch-closures.md recipe:
#   - /usr/sbin/nginx binary
#   - /usr/lib/nginx/modules (dynamic modules)
#   - ldd closure (libssl/libcrypto/pcre/zlib/etc.) via `cp -a` so symlinks
#     survive (critical for musl SONAME resolution)
#   - /etc/nginx config tree (default, upstream-sourced)
#   - /var/cache/nginx + /var/log/nginx + /var/lib/nginx — pre-created with
#     uid 65532 ownership because scratch has no mkdir at runtime
# hadolint ignore=DL3059,DL4006,DL3003
RUN set -eux; \
    mkdir -p /out/usr/sbin /out/usr/lib/nginx/modules \
             /out/var/cache/nginx /out/var/log/nginx \
             /out/var/lib/nginx/logs /out/var/lib/nginx/html \
             /out/var/lib/nginx/tmp/client_body \
             /out/var/lib/nginx/tmp/proxy \
             /out/var/lib/nginx/tmp/fastcgi \
             /out/var/lib/nginx/tmp/uwsgi \
             /out/var/lib/nginx/tmp/scgi \
             /out/etc/nginx /out/run /out/run/nginx; \
    cp /usr/sbin/nginx /out/usr/sbin/nginx; \
    # dynamic modules (dir may exist but be empty on alpine's nginx —
    # cp -r with the trailing dot handles that)
    if [ -d /usr/lib/nginx/modules ]; then \
      cp -a /usr/lib/nginx/modules/. /out/usr/lib/nginx/modules/; \
    fi; \
    # ldd closure for the nginx binary. On Alpine/musl, libs are symlinks
    # (e.g. libpcre2-8.so.0 → libpcre2-8.so.0.16.1). ldd reports the symlink
    # path but `cp -a` on that path preserves only the symlink; we also need
    # the realpath target. For each ldd-reported lib, resolve `readlink -f`
    # and copy BOTH the symlink (preserved via cp -a) AND the realpath.
    ldd /usr/sbin/nginx 2>/dev/null | awk '/=>/ {print $3}' | sort -u | while read -r lib; do \
      [ -z "$lib" ] && continue; \
      [ -e "$lib" ] || continue; \
      target=$(readlink -f "$lib"); \
      for p in "$lib" "$target"; do \
        [ -e "$p" ] || continue; \
        mkdir -p "/out$(dirname "$p")"; \
        cp -a "$p" "/out$p" 2>/dev/null || true; \
      done; \
    done; \
    # conf tree (upstream default)
    cp -r /etc/nginx/. /out/etc/nginx/; \
    # Copy html index page too (default welcome served by nginx).
    if [ -d /var/lib/nginx/html ]; then \
      cp -a /var/lib/nginx/html/. /out/var/lib/nginx/html/; \
    fi; \
    # ownership — nonroot uid 65532 (nonroot in /etc/passwd from scratch-alpine-3)
    chown -R 65532:65532 /out/var/cache/nginx /out/var/log/nginx /out/var/lib/nginx /out/run /out/run/nginx

# --- Stage 3: SBOM -----------------------------------------------------------
# hadolint ignore=DL3002
FROM ${BASE_ALPINE_REF} AS sbom
USER 0
# hadolint ignore=DL3018
RUN apk add --no-cache syft
COPY --from=builder /out /sbom-input
# hadolint ignore=DL3059
RUN syft dir:/sbom-input -o cyclonedx-json > /sbom.json

# --- Stage 4: runtime (scratch + musl overlay + nginx) -----------------------
FROM scratch AS runtime

ARG GIT_SHA=unknown
ARG BUILD_TIMESTAMP=unknown

LABEL org.opencontainers.image.source="https://github.com/bboortz/forge"
LABEL org.opencontainers.image.licenses="Apache-2.0"
LABEL org.opencontainers.image.description="nginx on Alpine/musl FROM scratch — overlay base/scratch-alpine-3 + apk-sourced nginx binary + ldd closure. ~15 MB. Serves on :80; HEALTHCHECK on /. Parallel to nginx-scratch-trixie for consumers who prefer a musl-sized runtime (FG-080)."
LABEL org.opencontainers.image.revision="${GIT_SHA}"
LABEL org.opencontainers.image.created="${BUILD_TIMESTAMP}"

# Overlay first (musl + CA + nss + /etc identity + zoneinfo + /tmp).
COPY --from=scratch_base_alpine / /

# Then the nginx runtime overlay.
COPY --from=builder /out /

# SBOM + hc.
COPY --from=sbom /sbom.json /sbom.json
COPY --from=hc /hc /hc

USER 65532

EXPOSE 80
VOLUME ["/var/cache/nginx", "/var/log/nginx"]

HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
  CMD ["/hc", "-t", "3", "http://127.0.0.1/"]

ENTRYPOINT ["/usr/sbin/nginx"]
CMD ["-g", "daemon off;"]
