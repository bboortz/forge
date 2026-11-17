# syntax=docker/dockerfile:1.7
#
# FG-066 mirror: zero-mod forge-signed passthrough of anchore/syft:latest.
#
# Only forge OCI labels + cosign signature differ from upstream. No RUN,
# no ENV (other than labels), no WORKDIR/CMD/USER/ADD/APT/EXPOSE —
# `arch.forge-mirror-image` invariant enforced by Rule 10 in
# scripts/verify-dockerfile-conformance.py.
#
# Consumed by the three forge-builders (forge-builder-{python,go,node}-
# trixie) via `COPY --from=syft-src /syft /usr/local/bin/syft`. Published
# in the new `publish-mirrors` CI tier that runs in parallel with
# `publish-pre-builders` and blocks `publish-builders`.

# hadolint ignore=DL3007
FROM anchore/syft:latest

ARG GIT_SHA=unknown
ARG BUILD_TIMESTAMP=unknown

LABEL org.opencontainers.image.source="https://github.com/bboortz/forge"
LABEL org.opencontainers.image.licenses="Apache-2.0"
LABEL org.opencontainers.image.description="Forge-signed zero-mod mirror of anchore/syft (SBOM CycloneDX cataloger). Pattern: arch.forge-mirror-image (FG-066)."
LABEL org.opencontainers.image.revision="${GIT_SHA}"
LABEL org.opencontainers.image.created="${BUILD_TIMESTAMP}"
