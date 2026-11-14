# FG-051 — Plan: ubuntu-slim-noble (first Ubuntu base) + github-runner-noble

**Story**: [`docs/stories/FG-051-ubuntu-base-and-github-runner.md`](../stories/FG-051-ubuntu-base-and-github-runner.md)
**Status**: ready → in-progress → shipped
**Branch**: `feat/FG-051-ubuntu-base-and-github-runner`

## Design delta

### `images/ubuntu-slim-noble/` (new)

- `image.yaml`: `tag: "24.04"`, `platforms: [linux/amd64]`, no `depends_on` (Ubuntu upstream exemption like debian-slim-trixie; forge-rooted pre-builder). Shape mirrors `images/debian-slim-trixie/image.yaml` exactly.
- `Dockerfile`: literal `FROM ubuntu:24.04` (NOT ARG-indirected, so FG-042's grep-invariant check can cheaply detect future drift) + apt-upgrade + CA certificates + libicu74. Keeps apt + shell.
- `PROMISES.yaml`: `files.ubuntu-noble` + `files.ca-certificates` + `files.libicu74` + `apt.freshly-upgraded` + `apt.no-cache`. `version: "0.1"`.
- `tests/`: `smoke_os_release.sh` (UBUNTU_CODENAME=noble), `smoke_ca_bundle.sh`, `smoke_libicu74_installed.sh`, `smoke_apt_no_cache.sh`, `smoke_size.sh`.
- `scan-baseline.json`: regenerated per-build. Nonzero accepted (slim contract).
- `sid-pins/` directory (empty at creation; Ubuntu doesn't use sid, we may need `focal-security` or similar apt pinning later — placeholder for parity with debian-slim-trixie structure).

### `scripts/verify-no-upstream-drift.sh` — extend anchor list

Add `ubuntu:24\.04` to `_UPSTREAM_ANCHORS`. Bump `_EXPECTED` from 2 → 3. The invariant now: three Dockerfiles FROM Docker Hub directly (debian:trixie-slim, python:3.14-slim-trixie, ubuntu:24.04 — one per forge pre-builder).

### `images/github-runner-noble/` (new)

- `image.yaml`: `tag: "latest"` (FG-050 `build.ref-latest-release` pattern — runner version floats), `platforms: [linux/amd64]`, no `depends_on` (slim variant, not scratch-overlay composition). Publish 2-tag family (`:latest` + `:latest-amd64`).
- `Dockerfile`:
  - `ARG UBUNTU_SLIM_NOBLE_REF=ghcr.io/bboortz/ubuntu-slim-noble:24.04`
  - `ARG RUNNER_VERSION=` (empty → resolves upstream latest via GitHub API)
  - `ARG HADOLINT_VERSION=v2.15.1` (upstream latest at ship time)
  - `ARG TERRAFORM_VERSION=1.17.2` (upstream latest at ship time)
  - Stage 0: syft source (same as other builders)
  - Stage 1: builder `FROM ${UBUNTU_SLIM_NOBLE_REF}` — apt-install `curl ca-certificates git jq unzip make python3 python3-pip shellcheck libicu74` (note: libicu74 already in base, this is defensive). Resolve runner version via curl + jq (FG-050 pattern, pipefail SHELL set). Download hadolint binary + terraform zip + extract + install. Download actions-runner-linux-x64-${RUNNER_VERSION}.tar.gz, extract to /home/runner, run installdependencies.sh. Pip install ansible + vendored requirements-dev.txt. ansible-galaxy install vendored ansible-requirements.yml. Emit SBOM via syft.
  - Stage 2: runtime `FROM ${UBUNTU_SLIM_NOBLE_REF}` — install only runtime deps (coreutils/make/jq/python3/pip/shellcheck/libicu74). COPY runner + hadolint + terraform + pip-installed Python packages + ansible-galaxy collections + entrypoint.sh + SBOM.
  - `ENV RUNNER_ALLOW_RUNASROOT=1 DEBIAN_FRONTEND=noninteractive`.
  - `WORKDIR /home/runner`. `ENTRYPOINT ["/entrypoint.sh"]`.
- `entrypoint.sh`: byte-for-byte match of homelab's current entrypoint.sh behavior — reads env, POSTs to GitHub API for registration token, calls config.sh `--unattended --replace`, execs run.sh. Set executable.
- `requirements-dev.txt`: vendored from homelab's current (ansible-lint==26.4.0, fastapi==0.136.3, PyJWT==2.13.0, pytest==9.0.3, pytest-xdist==3.8.0, ruff==0.15.22, yamllint==1.38.0).
- `ansible-requirements.yml`: vendored from homelab's current (ansible.posix >=2.1.0, community.general >=9.0.0).
- `PROMISES.yaml`: `runtime.gha-runner-binary`, `runtime.ci-toolset-full-bake` (tool list promise), `runtime.ansible-collections-preinstalled`, `runtime.entrypoint-registers-first-start`, `presence.shell`, `scan.nonzero-accepted`. `version: "0.1"`.
- `tests/`: `smoke_runner_version.sh`, `smoke_tools_present.sh` (every tool from the Gherkin tool list), `smoke_ansible_collections.sh`, `smoke_entrypoint_env_validation.sh` (missing GITHUB_ORG → immediate exit nonzero), `smoke_size.sh`.
- `scan-baseline.json`: regenerated.
- NO `sid-pins/` dir — Ubuntu doesn't use the Debian sid mechanism.

### `scripts/build-image.sh` (new ref)

Mirror the `forge-builder-go-trixie` wiring (same shape as FG-046 + FG-048):
```bash
# FG-051: ubuntu-slim-noble auto-build when the Dockerfile declares UBUNTU_SLIM_NOBLE_REF.
_UBUNTU_SLIM_NOBLE_DIR="${ROOT}/images/ubuntu-slim-noble"
if [[ -d "${_UBUNTU_SLIM_NOBLE_DIR}" && -f "${SRC}/Dockerfile" ]] \
   && grep -q "UBUNTU_SLIM_NOBLE_REF" "${SRC}/Dockerfile"; then
  echo "→ pre-builder dependency: ubuntu-slim-noble"
  REGISTRY="${REGISTRY}" "${BASH_SOURCE[0]}" ubuntu-slim-noble
fi
```
Plus the ref-resolution block + forge-local/ghcr.io fallback + --pull guard + --build-arg wiring + `_HAS_LOCAL_DEP` check. Identical pattern to debian-slim-trixie + python-slim-trixie.

### `scripts/discover-images.sh` — extend `_PRE_BUILDERS`

```bash
_PRE_BUILDERS=(debian-slim-trixie python-slim-trixie ubuntu-slim-noble)
```

### `.github/workflows/build.yml` — comment update

Four-tier publish comment now names the three pre-builders.

### `docs/CAPABILITIES.md` (2 NEW + 2 EXT)

- NEW `build.ubuntu-base-noble` — Forge's first Ubuntu base. `ubuntu-slim-noble:24.04` pre-builder; FROMs `ubuntu:24.04` upstream; downstream Ubuntu consumers must FROM this. Published in `publish-pre-builders` tier.
- NEW `image.github-runner-noble-pre-baked` — GHA self-hosted runner image with homelab-compatible CI toolset. Enables consumers (homelab first) to `docker pull` instead of `docker build` at deploy time.
- EXT `build.ref-latest-release` — now covers `actions/runner`.
- EXT `image.has-shell` — now lists ubuntu-slim-noble + github-runner-noble.

### `memory/design-decisions.md` — Ubuntu precedent note

The existing "Base distribution — Debian trixie (not Wolfi, not Alpine)" section needs an addendum acknowledging Ubuntu as a second base family for specific library-compat reasons. New section: "Ubuntu — case-by-case addition (FG-051)" explaining the libicu74 driver + the single-upstream-consumer rule for the new Ubuntu anchor.

### `docs/plan/IDEAS.md`

No new entries. The existing `uptime-kuma-browser-slim-trixie` + `forge-builder-node-trixie` entries are unrelated.

## Alternatives rejected

- **Patch Debian trixie to ship libicu74** — would require apt-pinning from unstable, carrying a forge-specific override. Ubuntu already ships 74. Simpler to use Ubuntu.
- **Generic github-runner image with no Python deps** (iter-1 Q2 option A) — rejected per user decision. Full homelab-compatible bake chosen.
- **Fetch homelab's requirements files at build time via curl** (iter-2 Q5 option B) — homelab is private, token management in CI gets ugly. Vendor instead.
- **Single-image flat Dockerfile without the pre-builder split** (iter-2 Q8 option B) — violates FG-042 upstream-single-consumer rule. Pre-builder enables future Ubuntu-base consumers to share apt-upgrade state.
- **ubuntu-slim-oracular (25.04)** — non-LTS, 9-month support. Not worth the churn for a stable CI runner.
- **Multi-arch / arm64** — amd64-only per every other Forge image.
- **Ephemeral runners** — single persistent runner is sufficient for homelab's volume. Scale when needed.

## Breaking changes

**For Forge image consumers**: None at the API level.

- No existing Forge image is affected. Both new images are additive.
- New precedent: Forge now accepts Ubuntu as a base family. Documented explicitly in `memory/design-decisions.md`.

**For homelab**: Operator-side migration available (not forced). Homelab's current `docker/github-runner/Dockerfile` continues to work as-is. Migration to the forge image is a separate homelab PR (see the companion doc `~/git/homelab/docs/forge-fg-051-github-runner-image-migration.md`).

## Merge plan

Blocking gates per `memory/workflow.md`:

- hadolint + shellcheck + yamllint + actionlint clean.
- `make verify-sid-pins` — N/A (ubuntu-slim-noble has empty sid-pins/ dir; github-runner-noble has none).
- `make verify-traceability` — new CAPs registered.
- `make verify-contracts` — new PROMISES validate.
- `make verify-no-upstream-drift` — script updated to expect `ubuntu:24.04` in exactly 1 Dockerfile; total pre-builder anchor count 2 → 3.
- `make test-acceptance` — FG-051 red test green.
- `make build` + `make scan` + `make verify` for both images.
- Scan-baseline regenerated.
- Image sizes within budget (ubuntu-slim-noble ≤ 150 MB; github-runner-noble ≤ 2 GB — large due to Python + ansible-galaxy footprint).

## Rollout plan

1. Land FG-051 on `feat/FG-051-...` branch.
2. Autonomous merge on green CI per workflow.md step 8.
3. User triggers `release.yml` → promotes dev → main.
4. Daily cron publishes:
   - `ubuntu-slim-noble:0.1` + `:latest` + `-amd64` variants (pre-builders tier).
   - `github-runner-noble:latest` + `:latest-amd64` (base tier, since it's a derivative of the pre-builder).
5. Companion homelab PR (user-triggered) swaps `docker/github-runner/` to pull-not-build via `image: ghcr.io/bboortz/github-runner-noble:latest`. See companion doc.

## Shipping evidence

| Item | Pointer | Status |
|------|---------|--------|
| Story drafted | `docs/stories/FG-051-ubuntu-base-and-github-runner.md` | ✅ |
| Plan drafted | `docs/plan/FG-051-ubuntu-base-and-github-runner-plan.md` | ✅ |
| Red acceptance test | `tests/acceptance/test_FG_051_ubuntu-base-and-github-runner.sh` | ⚠️ (create next) |
| ubuntu-slim-noble image dir | `images/ubuntu-slim-noble/` | ⚠️ |
| github-runner-noble image dir | `images/github-runner-noble/` | ⚠️ |
| scripts/build-image.sh wiring | `scripts/build-image.sh` | ⚠️ |
| scripts/discover-images.sh update | `scripts/discover-images.sh` | ⚠️ |
| scripts/verify-no-upstream-drift.sh update | `scripts/verify-no-upstream-drift.sh` | ⚠️ |
| CAPs registered | `docs/CAPABILITIES.md` | ⚠️ |
| memory/design-decisions.md Ubuntu precedent | `memory/design-decisions.md` | ⚠️ |
| INDEX.md updated | `docs/stories/INDEX.md` | ⚠️ |
| Scan-baselines regenerated | both images | ⚠️ |
| Homelab migration doc | `~/git/homelab/docs/forge-fg-051-github-runner-image-migration.md` | ⚠️ (created alongside PR) |
| CI green on PR | PR #TBD | ⚠️ |
