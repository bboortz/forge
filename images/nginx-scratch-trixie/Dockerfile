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
    apt-get -y --no-install-recommends install nginx libnginx-mod-stream ca-certificates curl; \
    rm -rf /var/lib/apt/lists/*

# FG-020: generate an SBOM from the builder stage (where dpkg metadata is
# present with full Debian version suffixes like -deb13u10). COPY'd into
# runtime below so grype honors Debian backports via its Debian matcher
# rather than falling back to NVD-CPE (which doesn't know about -u suffixes).
ARG SYFT_VERSION=v1.57.0
# hadolint ignore=DL4006
RUN set -eux; \
    curl -sSfL "https://raw.githubusercontent.com/anchore/syft/main/install.sh" \
      | sh -s -- -b /usr/local/bin "${SYFT_VERSION}"; \
    # Purge curl BEFORE scanning so builder-only install tooling doesn't leak
    # its dpkg entries into the SBOM. Any dep brought in only for curl goes
    # with it (--auto-remove).
    apt-get -y --purge --auto-remove remove curl; \
    syft dir:/ --override-default-catalogers dpkg-db-cataloger -o cyclonedx-json > /sbom.json

# Pull the baseline's /etc identity files into the builder so we can APPEND
# the www-data service-user line rather than overwriting the whole file.
# This way future additions to the baseline (e.g. nogroup) propagate into
# every derivative on the next rebuild instead of being silently dropped.
COPY --from=scratch_base /etc/passwd /tmp/baseline-passwd
COPY --from=scratch_base /etc/group  /tmp/baseline-group

# Assemble the nginx overlay. Baseline supplies glibc + TLS + DNS + zoneinfo
# + /etc/passwd+group with root+nobody; we APPEND the www-data service user.
RUN set -eux; \
    install -d /out/usr/sbin /out/usr/share/nginx/html \
               /out/etc /out/etc/nginx \
               /out/lib/x86_64-linux-gnu \
               /out/usr/lib/nginx/modules \
               /out/var/log/nginx /out/var/cache/nginx \
               /out/var/lib/nginx /out/var/lib/nginx/body \
               /out/var/lib/nginx/fastcgi /out/var/lib/nginx/proxy \
               /out/var/lib/nginx/scgi /out/var/lib/nginx/uwsgi; \
    # nginx binary + its one lib not in baseline.
    cp /usr/sbin/nginx                    /out/usr/sbin/nginx; \
    cp /lib/x86_64-linux-gnu/libpcre2-8.so.0 /out/lib/x86_64-linux-gnu/libpcre2-8.so.0; \
    # FG-016: bundle every dynamic module nginx-full ships (currently just
    # ngx_stream_module.so, which bundles ssl_preread). Enables consumers
    # to use `load_module` + stream{}/ssl_preread configs by mounting
    # their own config — no derived image needed.
    cp /usr/lib/nginx/modules/*.so        /out/usr/lib/nginx/modules/; \
    # nginx's compile-time module prefix is /usr/share/nginx/modules, but
    # Debian places modules at /usr/lib/nginx/modules. Symlink so relative
    # `load_module modules/<name>.so;` directives resolve without forcing
    # consumers to use absolute paths.
    ln -s /usr/lib/nginx/modules          /out/usr/share/nginx/modules; \
    # FG-016: ship mime.types — standard-ish nginx distribution file that
    # any HTTP config `include /etc/nginx/mime.types;` expects to resolve.
    cp /etc/nginx/mime.types              /out/etc/nginx/mime.types; \
    # Build /etc/passwd + /etc/group by appending service-user lines to
    # baseline's contents (append semantic via build-time concat + full-file
    # COPY in the runtime stage).
    cat /tmp/baseline-passwd                                 > /out/etc/passwd; \
    printf 'www-data:x:33:33:www-data:/:/sbin/nologin\n'    >> /out/etc/passwd; \
    cat /tmp/baseline-group                                  > /out/etc/group; \
    printf 'www-data:x:33:\n'                               >> /out/etc/group; \
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
# FG-020: SBOM from the builder stage (with real Debian version suffixes).
# scan-regression.py extracts this and uses `grype sbom:<path>` so Debian
# backports (like nginx 1.26.3-3+deb13u10) are honored.
COPY --from=builder /sbom.json /sbom.json

# FG-009: baseline's ENV SSL_CERT_FILE does NOT propagate through COPY —
# re-declare here so nginx-side TLS (e.g. upstream SSL verification in
# proxy_pass) resolves the CA bundle without needing an ssl_trusted_certificate
# directive. See docs/baseline-contract.md § "TLS trust".
ENV PATH=/usr/sbin \
    SSL_CERT_FILE=/etc/ssl/certs/ca-certificates.crt \
    SSL_CERT_DIR=/etc/ssl/certs

EXPOSE 80

ENTRYPOINT ["/usr/sbin/nginx"]
CMD ["-g", "daemon off;"]
