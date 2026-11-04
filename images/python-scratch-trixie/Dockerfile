# syntax=docker/dockerfile:1.7
#
# Two-stage build. Builder on python:3.13-slim-trixie (same base as the
# scratch baseline so glibc versions line up). Runtime FROM scratch, with
# the shared foundation (glibc + TLS + DNS + zoneinfo + /etc) coming from
# scratch-base-trixie and Python-specific closure COPY'd from the builder.
#
# No shell, no apt, no dpkg database. Pip bundled so `pip install --target`
# works for wheel-only packages at runtime.

ARG SCRATCH_BASE_REF=ghcr.io/bboortz/scratch-base-trixie:latest
ARG DEBIAN_BASE=python:3.13-slim-trixie

# --- Stage 0: baseline reference ---------------------------------------------
FROM ${SCRATCH_BASE_REF} AS scratch_base

# --- Stage 1: builder ---------------------------------------------------------
FROM ${DEBIAN_BASE} AS builder

ARG GIT_SHA=unknown
ARG BUILD_TIMESTAMP=unknown

COPY sid-pins/ /etc/apt/preferences.d/

# hadolint ignore=DL3005,DL3008
RUN set -eux; \
    apt-get update; \
    apt-get -y --no-install-recommends upgrade; \
    apt-get -y --no-install-recommends install ca-certificates; \
    rm -rf /var/lib/apt/lists/*

# Collect the Python-specific overlay. Baseline already supplies glibc + TLS
# + DNS + zoneinfo + minimal /etc (including /etc/passwd + /etc/group with
# root+nobody, which Python doesn't need to augment — no service user).
# We only COPY the Python interpreter, stdlib, libpython, pip, and Python's
# own stdlib C-extension deps (sqlite, bz2, lzma, zstd, expat, ffi, nsl,
# tirpc) + libutil (openpty/forkpty stdlib dep, not in baseline).
RUN set -eux; \
    install -d /out/usr/local/bin /out/usr/local/lib \
               /out/lib/x86_64-linux-gnu; \
    # Interpreter + stdlib + libpython + python3/python symlinks.
    cp -a /usr/local/bin/python3.13  /out/usr/local/bin/python3.13; \
    cp -a /usr/local/bin/python3     /out/usr/local/bin/python3     2>/dev/null || ln -s python3.13 /out/usr/local/bin/python3; \
    cp -a /usr/local/bin/python      /out/usr/local/bin/python      2>/dev/null || ln -s python3   /out/usr/local/bin/python; \
    cp -r /usr/local/lib/python3.13  /out/usr/local/lib/python3.13; \
    cp -a /usr/local/lib/libpython3*.so* /out/usr/local/lib/; \
    # Python-specific stdlib C-extension dyn deps (baseline supplies the core
    # but NOT libutil; the pty/openpty stdlib module needs it).
    for lib in libutil.so.1 \
               libbz2.so.1.0 liblzma.so.5 libzstd.so.1 \
               libexpat.so.1 libffi.so.8 libsqlite3.so.0 \
               libnsl.so.2 libtirpc.so.3; do \
      cp "/lib/x86_64-linux-gnu/$lib" "/out/lib/x86_64-linux-gnu/$lib" 2>/dev/null || true; \
    done; \
    # pip binary + symlinks.
    cp -a /usr/local/bin/pip* /out/usr/local/bin/ 2>/dev/null || true; \
    # Strip bytecode caches + unused stdlib trees.
    find /out/usr/local/lib/python3.13 -type d -name __pycache__ -exec rm -rf {} + || true; \
    find /out/usr/local/lib/python3.13 -name '*.pyc' -delete || true; \
    rm -rf /out/usr/local/lib/python3.13/test /out/usr/local/lib/python3.13/idlelib || true

# --- Stage 2: runtime (scratch) -----------------------------------------------
FROM scratch AS runtime

ARG GIT_SHA=unknown
ARG BUILD_TIMESTAMP=unknown

LABEL org.opencontainers.image.source="https://github.com/bboortz/forge"
LABEL org.opencontainers.image.licenses="Apache-2.0"
LABEL org.opencontainers.image.description="Minimal, continuously patched Python 3.13 base image (FROM scratch runtime, derives from scratch-base-trixie)"
LABEL org.opencontainers.image.revision="${GIT_SHA}"
LABEL org.opencontainers.image.created="${BUILD_TIMESTAMP}"

# Baseline first — glibc, TLS, DNS, zoneinfo, /etc/{passwd,group,nsswitch.conf,ssl/certs}.
# DL3067 silenced: copying the entire baseline is the whole point of the
# FG-005 composition pattern. Baseline is a signed audit-friendly artifact.
# hadolint ignore=DL3067
COPY --from=scratch_base / /
# Python-specific overlay. Later COPYs win if paths collide.
COPY --from=builder /out /

ENV PATH=/usr/local/bin \
    LANG=C.UTF-8

CMD ["python3.13"]
