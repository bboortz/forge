# syntax=docker/dockerfile:1.7
#
# FG-051: GitHub Actions self-hosted runner image, pre-baked with the
# full homelab-compatible CI toolset so consumers `docker pull` instead
# of `docker build` at deploy time.
#
# FROMs `ubuntu-slim-noble` (Forge's first Ubuntu base, FG-051 part a) —
# which pre-installs libicu74 (required by the runner's .NET 6 runtime
# that upstream `installdependencies.sh` fails to locate on Ubuntu 24.04
# because it only tries libicu70-72).
#
# RUNNER_VERSION= empty → resolves via the FG-050 `build.ref-latest-
# release` CAP. Daily cron re-resolves against upstream's weekly-ish
# runner releases.
#
# Toolset bake (homelab-aligned per iter-2 Q5 decision "vendor" strategy):
#   - apt: git curl jq unzip make python3 python3-pip shellcheck dumb-init
#   - hadolint v2.15.1 (upstream latest; was 2.12.0 in homelab)
#   - terraform v1.17.2 (upstream latest; was 1.10.3 in homelab)
#   - GHA runner (latest via API resolve)
#   - pip: ansible + whatever's in requirements-dev.txt (vendored)
#   - ansible-galaxy: collections per ansible-requirements.yml (vendored)
#
# Entrypoint matches homelab's current entrypoint.sh behavior: reads
# GITHUB_ORG + GITHUB_RUNNER_PAT + RUNNER_NAME + RUNNER_LABELS; registers
# at first start via GitHub API; subsequent starts skip to run.sh.

ARG BASE_UBUNTU_SLIM_NOBLE_REF=ghcr.io/bboortz/base/ubuntu-slim-noble:0.1

# Upstream-resolved versions (bump via Forge PR; daily cron bakes newer
# versions on each publish).
ARG HADOLINT_VERSION=v2.15.1
ARG TERRAFORM_VERSION=1.17.2
# Empty → build-time resolve via GitHub Releases API (FG-050 pattern).
ARG RUNNER_VERSION=

# Optional GitHub API token for the authenticated 5000/hr rate limit
# (vs 60/hr unauthenticated; shared GHA runner IPs exhaust the limit
# during parallel matrix publish). See PR #94.
# hadolint ignore=DL3064
ARG GITHUB_TOKEN=

FROM ${BASE_UBUNTU_SLIM_NOBLE_REF}

ARG HADOLINT_VERSION
ARG TERRAFORM_VERSION
ARG RUNNER_VERSION

# FG-077: base/*-slim-trixie defaults USER 65532 (nonroot). Override to
# USER 0 because this image needs root (apt install at build; runtime
# requires device/filesystem access typical of system services).
# hadolint ignore=DL3002
USER 0
# hadolint ignore=DL3064
ARG GITHUB_TOKEN
ARG GIT_SHA=unknown
ARG BUILD_TIMESTAMP=unknown

LABEL org.opencontainers.image.source="https://github.com/bboortz/forge"
LABEL org.opencontainers.image.licenses="Apache-2.0"
LABEL org.opencontainers.image.description="Pre-baked GitHub Actions self-hosted runner image (Ubuntu 24.04 noble + full homelab-compatible CI toolset: ansible + ansible-lint + ruff + yamllint + pytest + pytest-xdist + PyJWT + fastapi + ansible.posix + community.general + hadolint + terraform + shellcheck + make/jq/unzip + dumb-init). FG-051."
LABEL org.opencontainers.image.revision="${GIT_SHA}"
LABEL org.opencontainers.image.created="${BUILD_TIMESTAMP}"

ENV DEBIAN_FRONTEND=noninteractive
# GHA runner refuses UID 0 without this (upstream convention).
ENV RUNNER_ALLOW_RUNASROOT=1

# Core apt toolset. libicu74 already in the base (from ubuntu-slim-noble).
# DL3008: these are the versions ubuntu-24.04 ships; floating within
# the noble release channel.
# hadolint ignore=DL3008
RUN set -eux; \
    apt-get update; \
    apt-get -y --no-install-recommends install \
      git curl jq unzip make \
      python3 python3-pip \
      shellcheck dumb-init; \
    rm -rf /var/lib/apt/lists/*

# hadolint — Dockerfile linter.
RUN set -eux; \
    curl -fsSL "https://github.com/hadolint/hadolint/releases/download/${HADOLINT_VERSION}/hadolint-Linux-x86_64" \
      -o /usr/local/bin/hadolint; \
    chmod +x /usr/local/bin/hadolint; \
    hadolint --version

# terraform.
# DL3003: cd is scoped to this RUN (no state leakage), safer than fiddling
# with buildx mounts for a single-step install.
# hadolint ignore=DL3003
RUN set -eux; \
    curl -fsSL "https://releases.hashicorp.com/terraform/${TERRAFORM_VERSION}/terraform_${TERRAFORM_VERSION}_linux_amd64.zip" \
      -o /tmp/terraform.zip; \
    unzip -q /tmp/terraform.zip -d /usr/local/bin/; \
    rm /tmp/terraform.zip; \
    terraform --version

# GitHub Actions runner — resolve latest if RUNNER_VERSION empty (FG-050
# build.ref-latest-release pattern). The pipe needs pipefail (DL4006) +
# the Authorization header falls through to unauthenticated if
# GITHUB_TOKEN is empty.
# hadolint ignore=DL3003
SHELL ["/bin/bash", "-o", "pipefail", "-c"]
RUN set -eux; \
    TARGET_REF="${RUNNER_VERSION}"; \
    if [ -z "${TARGET_REF}" ]; then \
      TARGET_REF="$(curl -fsSL \
        ${GITHUB_TOKEN:+-H "Authorization: Bearer ${GITHUB_TOKEN}"} \
        https://api.github.com/repos/actions/runner/releases/latest \
        | jq -r '.tag_name // empty')"; \
      [ -n "${TARGET_REF}" ] || { echo "could not resolve latest actions/runner release" >&2; exit 1; }; \
    fi; \
    # Strip leading 'v' for the tarball naming convention.
    RUNNER_SEMVER="${TARGET_REF#v}"; \
    echo "${TARGET_REF}" > /tmp/resolved-runner-version; \
    mkdir -p /home/runner; \
    curl -fsSL \
      "https://github.com/actions/runner/releases/download/${TARGET_REF}/actions-runner-linux-x64-${RUNNER_SEMVER}.tar.gz" \
      -o /tmp/runner.tar.gz; \
    tar -xzf /tmp/runner.tar.gz -C /home/runner; \
    rm /tmp/runner.tar.gz; \
    /home/runner/bin/installdependencies.sh

# Vendored homelab CI dep lists. Keep in sync with
# bb-claw/homelab's requirements-dev.txt + ansible/requirements.yml
# via chore PRs (see FG-051 story § dep-sync strategy).
COPY requirements-dev.txt /build/requirements-dev.txt
COPY ansible-requirements.yml /build/ansible-requirements.yml

# pip: ansible + homelab-aligned requirements-dev.txt.
# --break-system-packages: Ubuntu 24.04 ships PEP-668 externally-managed
# marker; we deliberately pip-install at the system Python level because
# the runner user needs these on PATH.
# DL3042 ignore: --no-cache-dir would conflict with --break-system-packages
# flag ordering on Ubuntu 24.04's pip version; we clean the cache
# explicitly in the final RM.
# hadolint ignore=DL3042
RUN set -eux; \
    pip3 install --no-cache-dir --break-system-packages \
      ansible \
      -r /build/requirements-dev.txt

# ansible-galaxy: collections per homelab-aligned ansible-requirements.yml.
RUN set -eux; \
    ansible-galaxy collection install -r /build/ansible-requirements.yml

# Entrypoint — handles first-start registration against a GitHub org.
# Matches homelab's docker/github-runner/entrypoint.sh behavior.
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

WORKDIR /home/runner
ENTRYPOINT ["/entrypoint.sh"]
