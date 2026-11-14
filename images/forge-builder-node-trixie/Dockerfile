# syntax=docker/dockerfile:1.7
#
# FG-048: shared builder-base image for every Forge-native from-Node-source
# image. Sibling to FG-046's forge-builder-go-trixie (Go from-source) and
# FG-025's forge-builder-trixie (Debian builder + syft).
#
# Pre-bakes:
#   - apt-get upgrade applied (trixie-security included)
#   - ca-certificates (TLS verify for curl / git / npm registry)
#   - git + curl + jq (for upstream release resolution + source clone;
#     FG-013 latest-resolve pattern)
#   - syft (dpkg + go/node module cataloger)
#   - make + g++ + python3 (native-module rebuild safety net — @louislam/
#     sqlite3 and other Node native deps ship prebuilt amd64 binaries for
#     LTS Node versions, but keep the toolchain so a future dep switch
#     doesn't fail silently at build time)
#   - dumb-init (PID 1 signal forwarding — consumers may copy it into
#     their runtime stage; uptime-kuma does this per FG-045 convention)
#   - corepack enable — Node ships corepack as its official package-manager
#     shim; `corepack enable` creates /usr/local/bin/pnpm + /usr/local/bin/
#     yarn so `pnpm install` + `yarn install` Just Work without a separate
#     `npm install -g pnpm`. The actual pnpm/yarn version comes from each
#     consumer's package.json `packageManager` field (pnpm resolution on
#     first invocation). Downstream dockerfiles can call any of npm/pnpm/
#     yarn without extra setup.
#
# Node 24 LTS: active LTS until April 2028. Satisfies prometheus v3 (.nvmrc
# says 24.21.0) and prometheus v2.53 (compatible). Uptime-kuma's vite SPA
# build is Node-20+ compatible, works on 24 fine.
#
# Daily cron (build.yml) rebuilds this first; derivatives pull it as a
# FROM reference. Bumping the Node major version is a single `NODE_BASE`
# ARG update + a rebuild — all from-Node-source derivatives inherit the
# new runtime without each needing their own Dockerfile change.

ARG NODE_BASE=node:24-trixie-slim
# syft via Docker Hub (same precedent as forge-builder-go-trixie).
ARG SYFT_SRC=docker.io/anchore/syft:latest

# --- Stage 0: syft source (Docker Hub) ---------------------------------------
FROM ${SYFT_SRC} AS syft-src

# --- Stage 1: builder base (Node + Debian) -----------------------------------
FROM ${NODE_BASE}

ARG GIT_SHA=unknown
ARG BUILD_TIMESTAMP=unknown

LABEL org.opencontainers.image.source="https://github.com/bboortz/forge"
LABEL org.opencontainers.image.licenses="Apache-2.0"
LABEL org.opencontainers.image.description="Shared builder for Forge from-Node-source images — Node 24 LTS + corepack (npm/pnpm/yarn) + apt-upgraded + CA certs + syft + git/curl/jq + make/g++/python3 + dumb-init"
LABEL org.opencontainers.image.revision="${GIT_SHA}"
LABEL org.opencontainers.image.created="${BUILD_TIMESTAMP}"

# apt-upgrade + base build deps.
# - git: shallow-clone upstream source
# - curl + jq: resolve latest-release tag at build time (FG-013 pattern)
# - ca-certificates: TLS verify for curl / git / npm
# - make + g++ + python3: safety-net for native Node module rebuilds
#   (@louislam/sqlite3 + similar C/C++ deps). amd64 prebuilds usually
#   ship for LTS Node; this toolchain catches the fallback path.
# - dumb-init: downstream copies into runtime stage for proper PID 1
#   signal forwarding (upstream node convention).
# hadolint ignore=DL3008
RUN set -eux; \
    apt-get update; \
    apt-get -y --no-install-recommends upgrade; \
    apt-get -y --no-install-recommends install \
      ca-certificates git curl jq make g++ python3 dumb-init; \
    rm -rf /var/lib/apt/lists/*

# syft from Docker Hub.
COPY --from=syft-src /syft /usr/local/bin/syft

# Enable corepack so pnpm + yarn work out-of-the-box. Node 24 ships corepack
# natively; `corepack enable` creates shim binaries under /usr/local/bin/.
# Downstream consumers' package.json `packageManager` field determines which
# version of pnpm/yarn gets resolved on first invocation.
# Smoke the toolchain at build time so a broken image fails fast.
# pipefail set via SHELL to satisfy DL4006 on piped checks.
SHELL ["/bin/bash", "-o", "pipefail", "-c"]
RUN set -eux; \
    corepack enable; \
    node --version | head -1; \
    npm --version | head -1; \
    corepack prepare pnpm@latest --activate >/dev/null 2>&1 || true; \
    pnpm --version || true; \
    yarn --version || true; \
    syft version | head -1

WORKDIR /
