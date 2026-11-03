# syntax=docker/dockerfile:1.7
FROM python:3.13-slim-trixie

ARG GIT_SHA=unknown
ARG BUILD_TIMESTAMP=unknown

LABEL org.opencontainers.image.source="https://github.com/bboortz/forge"
LABEL org.opencontainers.image.licenses="Apache-2.0"
LABEL org.opencontainers.image.description="Minimal, continuously patched Python 3.13 base image (slim-trixie)"
LABEL org.opencontainers.image.revision="${GIT_SHA}"
LABEL org.opencontainers.image.created="${BUILD_TIMESTAMP}"

# sid pins live under images/python/sid-pins/ — empty on FG-001 (no pins yet).
COPY sid-pins/ /etc/apt/preferences.d/

# hadolint ignore=DL3005
RUN set -eux; \
    apt-get update; \
    apt-get -y --no-install-recommends upgrade; \
    rm -rf /var/lib/apt/lists/*

CMD ["python3"]
