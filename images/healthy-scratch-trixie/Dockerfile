# syntax=docker/dockerfile:1.7
#
# FG-029: Two-stage. Builder from forge-builder-trixie. Runtime FROM
# scratch, composed of:
#   1. scratch-base-trixie (glibc + TLS + DNS + zoneinfo + CA bundle)
#   2. minimal utility overlay (wget + nc + sleep + their libs; no curl
#      because curl's closure drags ~15 MB of GSSAPI/LDAP/brotli/GnuTLS
#      — defeats the "sidecar should be tiny" principle).
#
# Default CMD sleeps forever. Consumers mount it as a sidecar via
# `network_mode: "service:<name>"` and let docker's healthcheck feature
# invoke /usr/bin/wget / /usr/bin/nc against the shared loopback.

ARG SCRATCH_BASE_REF=ghcr.io/bboortz/scratch-base-trixie:latest
ARG FORGE_BUILDER_REF=ghcr.io/bboortz/forge-builder-trixie:latest

# --- Stage 0: baseline reference ---------------------------------------------
FROM ${SCRATCH_BASE_REF} AS scratch_base

# --- Stage 1: builder ---------------------------------------------------------
FROM ${FORGE_BUILDER_REF} AS builder

ARG GIT_SHA=unknown
ARG BUILD_TIMESTAMP=unknown

COPY sid-pins/ /etc/apt/preferences.d/

# hadolint ignore=DL3008
RUN set -eux; \
    apt-get update; \
    apt-get -y --no-install-recommends install wget netcat-openbsd coreutils; \
    rm -rf /var/lib/apt/lists/*

# FG-020: embedded SBOM from builder-stage dpkg. syft pre-installed by FG-025.
RUN set -eux; \
    syft dir:/ --override-default-catalogers dpkg-db-cataloger -o cyclonedx-json > /sbom.json

# Assemble the healthcheck-utilities overlay.
RUN set -eux; \
    install -d /out/usr/bin /out/lib/x86_64-linux-gnu; \
    # wget — primary HTTP healthcheck tool
    cp /usr/bin/wget /out/usr/bin/wget; \
    # nc — resolve symlink /usr/bin/nc → /bin/nc.openbsd; copy the real binary
    # into /usr/bin/nc so scratch doesn't need the alternatives system.
    cp /bin/nc.openbsd /out/usr/bin/nc; \
    # sleep — GNU coreutils; CMD uses `sleep infinity` so the sidecar stays up.
    cp /usr/bin/sleep /out/usr/bin/sleep; \
    # wget-specific libs (baseline provides libc + libz).
    for lib in libpcre2-8.so.0 libuuid.so.1 libidn2.so.0 libnettle.so.8 \
               libgnutls.so.30 libpsl.so.5 libunistring.so.5 libp11-kit.so.0 \
               libtasn1.so.6 libhogweed.so.6 libgmp.so.10 libffi.so.8; do \
      cp "/lib/x86_64-linux-gnu/${lib}" "/out/lib/x86_64-linux-gnu/${lib}"; \
    done; \
    # nc-specific libs (baseline provides libresolv, libc).
    for lib in libbsd.so.0 libmd.so.0; do \
      cp "/lib/x86_64-linux-gnu/${lib}" "/out/lib/x86_64-linux-gnu/${lib}"; \
    done

# --- Stage 2: runtime (scratch) -----------------------------------------------
FROM scratch AS runtime

ARG GIT_SHA=unknown
ARG BUILD_TIMESTAMP=unknown

LABEL org.opencontainers.image.source="https://github.com/bboortz/forge"
LABEL org.opencontainers.image.licenses="Apache-2.0"
LABEL org.opencontainers.image.description="Minimal, continuously patched scratch sidecar carrying wget + nc + sleep for healthcheck-companion deployments"
LABEL org.opencontainers.image.revision="${GIT_SHA}"
LABEL org.opencontainers.image.created="${BUILD_TIMESTAMP}"

# Baseline first (glibc + TLS + DNS + zoneinfo + /etc + CA bundle),
# then utility overlay.
# hadolint ignore=DL3067
COPY --from=scratch_base / /
COPY --from=builder /out /
# FG-020: SBOM embed.
COPY --from=builder /sbom.json /sbom.json

# FG-009: re-declare SSL_CERT_FILE per the "ENV does not propagate" lesson.
ENV SSL_CERT_FILE=/etc/ssl/certs/ca-certificates.crt \
    SSL_CERT_DIR=/etc/ssl/certs

# Run as the baseline-provided nonroot (65532) — no privileged work needed.
USER 65532:65532
WORKDIR /
# CMD = sleep forever. Consumer compose can drop `command:` entirely;
# docker's healthcheck invokes wget / nc via the shared netns.
CMD ["/usr/bin/sleep", "infinity"]
