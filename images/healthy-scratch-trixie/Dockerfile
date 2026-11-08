# syntax=docker/dockerfile:1.7
#
# FG-030: healthy-scratch-trixie v2 — hc-based minimal sidecar.
#
# Composition (NOT using scratch-base-trixie):
#   - raw FROM scratch (nothing inherited)
#   - /hc — static Zig binary from ghcr.io/bboortz/hc:0.1.0 (produced
#     by the sister `healthy` repo under HC-005)
#   - /usr/bin/sleep — GNU coreutils, dynamically linked against libc
#   - /lib64/ld-linux-x86-64.so.2 + /lib/x86_64-linux-gnu/libc.so.6 —
#     just enough runtime for sleep to execute
#
# Why not scratch-base-trixie? It brings glibc + full TLS + CA bundle +
# nss + zoneinfo (~13 MB), all unused here. hc is static; sleep only
# needs libc. Manual approach: ~2-3 MB image total.
#
# Why keep sleep at all? Docker container needs ONE long-running
# process. hc is one-shot (connect, check, exit). sleep infinity keeps
# the container alive so docker's healthcheck can repeatedly invoke hc
# via docker exec through a shared netns (network_mode: service:<name>).

ARG HC_REF=ghcr.io/bboortz/hc:0.1.0
ARG FORGE_BUILDER_REF=ghcr.io/bboortz/forge-builder-trixie:latest

# --- Stage 0: hc binary source -----------------------------------------------
FROM ${HC_REF} AS hc

# --- Stage 1: builder (for sleep + libc extraction) --------------------------
FROM ${FORGE_BUILDER_REF} AS builder

ARG GIT_SHA=unknown
ARG BUILD_TIMESTAMP=unknown

# coreutils is already in forge-builder-trixie; syft too (used for SBOM).
RUN set -eux; \
    syft dir:/ --override-default-catalogers dpkg-db-cataloger -o cyclonedx-json > /sbom.json

# Stage the minimal filesystem into /out so the runtime stage can
# `COPY --from=builder /out /` in one shot.
RUN set -eux; \
    install -d /out/usr/bin /out/lib/x86_64-linux-gnu /out/lib64; \
    cp /usr/bin/sleep /out/usr/bin/sleep; \
    # Use plain cp (not cp -a) for ld-linux so the Debian multiarch
    # symlink dereferences into a real binary — matches the lesson from
    # memory/scratch-closures.md.
    cp /lib64/ld-linux-x86-64.so.2 /out/lib64/ld-linux-x86-64.so.2; \
    cp /lib/x86_64-linux-gnu/libc.so.6 /out/lib/x86_64-linux-gnu/libc.so.6

# --- Stage 2: runtime (raw scratch) ------------------------------------------
FROM scratch AS runtime

ARG GIT_SHA=unknown
ARG BUILD_TIMESTAMP=unknown

LABEL org.opencontainers.image.source="https://github.com/bboortz/forge"
LABEL org.opencontainers.image.licenses="Apache-2.0"
LABEL org.opencontainers.image.description="Minimal signed scratch sidecar carrying hc + sleep for healthcheck-companion deployments (~2 MB; hc from bboortz/healthy)"
LABEL org.opencontainers.image.revision="${GIT_SHA}"
LABEL org.opencontainers.image.created="${BUILD_TIMESTAMP}"

# hc comes in as /hc
COPY --from=hc /hc /hc
# sleep + its libc closure
COPY --from=builder /out /
# SBOM (FG-020) — covers coreutils + libc only; hc has no OS packages.
COPY --from=builder /sbom.json /sbom.json

# Run as uid 65532 (distroless nonroot convention). No home dir needed —
# hc and sleep both work without one.
USER 65532:65532
WORKDIR /
# CMD = sleep forever. docker's healthcheck invokes /hc on demand via
# the shared netns.
CMD ["/usr/bin/sleep", "infinity"]
