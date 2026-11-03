*Dockerfile and build-time conventions for Forge images. Every image under `images/<name>/` conforms to this.*

## Two-stage Dockerfile template (scratch runtime)

```dockerfile
# syntax=docker/dockerfile:1.7
ARG DEBIAN_BASE=python:3.13-slim-trixie

# --- Stage 1: builder ---------------------------------------------------------
FROM ${DEBIAN_BASE} AS builder

# Apply any sid pins committed under images/<name>/sid-pins/.
COPY sid-pins/ /etc/apt/preferences.d/
# shellcheck disable=SC2015
RUN set -eux; \
    apt-get update; \
    apt-get -y --no-install-recommends upgrade; \
    apt-get -y --no-install-recommends install curl ca-certificates; \
    rm -rf /var/lib/apt/lists/*

# Build-time additions go here (pip install, compile, strip, etc.).

# --- Stage 2: runtime ---------------------------------------------------------
FROM scratch AS runtime

# Interpreter + stdlib + libc + ld-linux. See § "What to COPY" below.
COPY --from=builder /usr/local/bin/python3.13     /usr/local/bin/python3.13
COPY --from=builder /usr/local/lib/python3.13     /usr/local/lib/python3.13
COPY --from=builder /lib/x86_64-linux-gnu/libc.so.6         /lib/x86_64-linux-gnu/libc.so.6
COPY --from=builder /lib/x86_64-linux-gnu/libssl.so.3       /lib/x86_64-linux-gnu/libssl.so.3
COPY --from=builder /lib/x86_64-linux-gnu/libcrypto.so.3    /lib/x86_64-linux-gnu/libcrypto.so.3
COPY --from=builder /lib/x86_64-linux-gnu/libm.so.6         /lib/x86_64-linux-gnu/libm.so.6
COPY --from=builder /lib/x86_64-linux-gnu/libpthread.so.0   /lib/x86_64-linux-gnu/libpthread.so.0
COPY --from=builder /lib/x86_64-linux-gnu/libdl.so.2        /lib/x86_64-linux-gnu/libdl.so.2
COPY --from=builder /lib64/ld-linux-x86-64.so.2             /lib64/ld-linux-x86-64.so.2
# Also COPY /etc/ssl/certs/ca-certificates.crt for TLS.

ENTRYPOINT ["/usr/local/bin/python3.13"]
```

Multi-arch note: the `/lib/<triple>` path is per-arch (`aarch64-linux-gnu` on arm64). Use buildx `TARGETARCH` + a sed step, or publish per-arch Dockerfiles — do not hard-code x86_64 in the image we publish for arm64.

## What to COPY into the scratch stage — discovery recipe

Reproduce this inside the builder stage once per image, then commit the discovered paths:

```bash
# everything the interpreter dlopens
ldd /usr/local/bin/python3.13 | awk '/=>/ {print $3}'

# everything stdlib modules dlopen under /usr/local/lib/python3.13/lib-dynload/
find /usr/local/lib/python3.13/lib-dynload -name '*.so' -exec ldd {} \; \
  | awk '/=>/ {print $3}' | sort -u

# CA bundle (empty curl / urllib without this)
/etc/ssl/certs/ca-certificates.crt

# zoneinfo if the image handles timezone-sensitive data
/usr/share/zoneinfo
```

Rule: if `ldd` says it's needed, it must be COPY'd. If it isn't needed, do not COPY "just in case" — the point of scratch is a tight runtime.

## sid-pin file format

Under `images/<name>/sid-pins/<package>.pref`:

```
# CVE-2026-NNNNN: libxml2 double-free in SAX2 path.
# Backport to trixie not landed as of 2026-11-03. Remove this pin once
# libxml2 ≥ 2.12.9+dfsg-1 is in trixie.
Package: libxml2
Pin: release a=unstable
Pin-Priority: 500
```

Required fields in the comment: CVE id, condition for removal, date added. `make verify-sid-pins` greps these; a pin with no removal condition fails lint.

## Multi-arch builds

Primary platforms: `linux/amd64`, `linux/arm64`. We build via `docker buildx build --platform linux/amd64,linux/arm64 --push`. GHA runners emulate arm64 via QEMU, which is slow but acceptable at daily cadence. If build time crosses ~45 min we migrate arm64 to a `ubuntu-22.04-arm` runner.

## Build cache

- Use `--cache-from=type=registry,ref=ghcr.io/forge-images/<name>:buildcache` and `--cache-to=type=registry,ref=...,mode=max` on both PR and nightly builds.
- Cache invalidation is implicit when a sid pin changes (apt layer rehashes) — do not add cache-busting ARGs.

## Image labels

Every image sets, at minimum:

```dockerfile
LABEL org.opencontainers.image.source="https://github.com/forge-images/forge"
LABEL org.opencontainers.image.licenses="Apache-2.0"
LABEL org.opencontainers.image.description="Minimal, continuously patched <name> base image"
LABEL org.opencontainers.image.revision="${GIT_SHA}"
LABEL org.opencontainers.image.created="${BUILD_TIMESTAMP}"
```

`revision` + `created` are injected at build time via `--label` from the Makefile — do not hard-code in the Dockerfile.

## What NOT to put in a Forge image

- Shell (`sh`, `bash`, `busybox`) in a scratch-runtime image. The `-slim` variants keep their shell on purpose; scratch runtimes do not.
- Package managers (`apt`, `apk`, `pip`) in the runtime stage.
- Compilers, build toolchains, header files, docs, `.pyc` cache directories (`__pycache__`).
- `/tmp` content from the builder (strip it with `rm -rf` before the final COPY surface).

If you catch yourself COPY'ing a directory and only using 2% of it, extract the 2%.
