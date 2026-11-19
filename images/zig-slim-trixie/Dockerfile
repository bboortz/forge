# syntax=docker/dockerfile:1.7
#
# FG-072: forge-rooted Zig toolchain slim pre-builder. Published pre-builder;
# `forge-builder-zig-trixie` FROMs this instead of a Zig-upstream image
# (dogfood — same shape as `forge-builder-{python,go,node}-trixie` FROMing
# their respective pre-builders per FG-065 arch.language-family-image-pair).
#
# Zig doesn't ship an official Debian-based Docker Hub image, so this
# pre-builder FROMs ${DEBIAN_SLIM_REF} (forge-rooted debian-slim-trixie)
# and installs Zig from the official ziglang.org tarball with SHA256
# verification. This preserves FG-042's single-upstream-consumer rule —
# debian:trixie-slim remains consumed by exactly one forge image
# (debian-slim-trixie itself; the drift guard _EXPECTED stays at 6).
#
# Current consumers (post-FG-072):
#   - forge-builder-zig-trixie (builder base; dogfood)
#
# Zig produces fully static binaries (no runtime libc dependency), so there
# is no need for a "zig-runtime" slim consumer. This image's justification
# is the FG-065 arch.language-family-image-pair invariant + FBZ dogfood;
# future Zig-source runtimes (e.g. a Forge-native hc migration) use this
# chain at builder-stage only.
#
# ZIG_VERSION is pinned (Zig is pre-1.0; ABI changes between minors).
# Bumping is a chore-commit that updates both ZIG_VERSION + ZIG_SHA256
# after validating against every downstream consumer.

ARG DEBIAN_SLIM_REF=ghcr.io/bboortz/debian-slim-trixie:latest

FROM ${DEBIAN_SLIM_REF}

ARG GIT_SHA=unknown
ARG BUILD_TIMESTAMP=unknown
ARG ZIG_VERSION=0.17.1
ARG ZIG_SHA256=3581863e3cbcfd0fce0efc682ce7e9e93da96668a977791d356a26d2a7e9b17a

LABEL org.opencontainers.image.source="https://github.com/bboortz/forge"
LABEL org.opencontainers.image.licenses="Apache-2.0"
LABEL org.opencontainers.image.description="Forge-rooted Zig 0.17 toolchain slim base — apt-upgraded + CA certs + dumb-init + Zig from ziglang.org, dogfooded by forge-builder-zig-trixie per FG-072 (language-family image-pair invariant)"
LABEL org.opencontainers.image.revision="${GIT_SHA}"
LABEL org.opencontainers.image.created="${BUILD_TIMESTAMP}"

# apt-upgrade + base tools:
# - ca-certificates: TLS verify for curl / git / Zig package fetches
# - dumb-init: PID 1 signal forwarding in downstream consumers (symmetry
#   with go-slim-trixie / node-slim-trixie)
# - xz-utils: untar the .tar.xz Zig tarball
# - curl: fetch the Zig tarball from ziglang.org
# All of these except dumb-init come from debian-slim-trixie's apt-upgrade
# layer already; adding them again is a no-op after cache (ca-certificates
# already present, curl + xz-utils fresh installs).
# hadolint ignore=DL3008,DL3015
RUN set -eux; \
    apt-get update; \
    apt-get -y --no-install-recommends upgrade; \
    apt-get -y --no-install-recommends install \
      ca-certificates curl dumb-init xz-utils; \
    rm -rf /var/lib/apt/lists/*

# Install Zig from the official ziglang.org tarball + SHA256-verify.
# Tarball layout: zig-x86_64-linux-<ver>/{zig,lib/,doc/,LICENSE,README.md}
# We install to /usr/local/zig + symlink /usr/local/bin/zig for PATH.
# hadolint ignore=DL3059
RUN set -eux; \
    _tar="zig-x86_64-linux-${ZIG_VERSION}.tar.xz"; \
    _url="https://ziglang.org/download/${ZIG_VERSION}/${_tar}"; \
    curl -fsSLo "/tmp/${_tar}" "${_url}"; \
    printf '%s  /tmp/%s\n' "${ZIG_SHA256}" "${_tar}" > /tmp/zig.sha256; \
    sha256sum -c /tmp/zig.sha256; \
    rm /tmp/zig.sha256; \
    mkdir -p /usr/local/zig; \
    tar -xJf "/tmp/${_tar}" -C /usr/local/zig --strip-components=1; \
    rm "/tmp/${_tar}"; \
    ln -s /usr/local/zig/zig /usr/local/bin/zig; \
    /usr/local/bin/zig version

WORKDIR /
