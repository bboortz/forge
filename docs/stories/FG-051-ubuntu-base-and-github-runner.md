---
id: FG-051
slug: ubuntu-base-and-github-runner
status: shipped
owner: bboortz
created: 2026-11-14
shipped: 2026-11-14
---

# FG-051 — First Ubuntu base (`ubuntu-slim-noble`) + `github-runner-noble` pre-baked CI image

Homelab currently builds `docker/github-runner/Dockerfile` locally on every deployment — a from-scratch `FROM ubuntu:24.04` install of apt packages, pip Python deps, ansible-galaxy collections, hadolint + terraform downloads, and the GitHub Actions runner tarball. On a fresh host this build runs several minutes; on an already-populated host with layer cache, still 30-60s of repeated apt/pip churn per deploy. The CI job on server2 blocks on it.

FG-051 ships two forge-signed images so homelab (and future consumers) pull instead of build:

1. **`ghcr.io/bboortz/ubuntu-slim-noble:24.04`** — Forge's first Ubuntu-based image. `FROM ubuntu:24.04` + `apt-get upgrade` + `ca-certificates` + `libicu74` (required for the GitHub Actions runner's .NET 6 runtime; the runner's own `installdependencies.sh` only tries libicu70 and below). Published in the `publish-pre-builders` CI tier.
2. **`ghcr.io/bboortz/github-runner-noble:latest`** — `FROM ubuntu-slim-noble` + GitHub Actions runner binary (upstream latest release, resolved at build time via FG-050's `build.ref-latest-release` CAP) + hadolint v2.15.1 + terraform v1.17.2 + full homelab-compatible CI toolset (ansible, ansible-lint, ruff, yamllint, pytest, pytest-xdist, PyJWT, fastapi; ansible-galaxy posix + community.general collections) + a standard entrypoint.sh that handles first-start registration against a GitHub org.

This is **Forge's first Ubuntu-base image**. Every prior image has been Debian trixie (per `memory/design-decisions.md`). The decision is justified case-by-case: the GHA runner's hard dep on libicu74 vs libicu76 (what Debian trixie ships) makes Ubuntu 24.04 the lowest-friction base. Adding Ubuntu to Forge's base-distribution set is explicitly a precedent — documented in the updated `memory/design-decisions.md`.

## 9 canonical answers

1. **Who** — homelab operator (me) first, using a self-hosted GitHub Actions runner on server2 for the `lint` CI job (per `~/git/homelab/docs/github-runner-plan.md`). Secondary: any future Forge consumer wanting a pre-baked CI runner (`beaconry` uses GHA; could consume the same image). Tertiary: any future Forge-signed image needing an Ubuntu rather than Debian base (grafana-slim? n8n-slim? — all still speculative, but the pre-builder is ready).

2. **When** — fires every time homelab's compose (`docker/github-runner/docker-compose.yml`) resolves its image. Today that's a `build: .` + `image: github-runner:latest` combo → rebuild on every `docker compose up`. Post-FG-051 + homelab's follow-up migration: `image: ghcr.io/bboortz/github-runner-noble:latest` + no `build:` key → just a pull. Daily cron publishes refreshed images (with new runner version + patched Ubuntu base).

3. **What success looks like**:
   - `ghcr.io/bboortz/ubuntu-slim-noble:24.04` publishes with cosign + SBOM + scan attestations. `docker run --rm --entrypoint=/bin/sh <ref> -c 'cat /etc/os-release'` shows `UBUNTU_CODENAME=noble`.
   - `ghcr.io/bboortz/github-runner-noble:latest` publishes with cosign + SBOM + scan. `docker run --rm --entrypoint=/home/runner/bin/Runner.Listener <ref> --version` prints the resolved GHA runner version. `hadolint --version` prints 2.15.1. `terraform --version` prints 1.17.2. `ansible --version` prints a version. `ansible-lint --version`, `ruff --version`, `yamllint --version`, `pytest --version`, `shellcheck --version` all exit 0.
   - homelab's `docker/github-runner/Dockerfile` either (a) deletes entirely in favor of `image: ghcr.io/bboortz/github-runner-noble:latest` in compose, or (b) becomes a 3-line wrapper for custom entrypoint overlay. Deploy time for the runner service drops from minutes → seconds.
   - Entrypoint behaves identically to homelab's current entrypoint.sh: reads `GITHUB_ORG` / `GITHUB_RUNNER_PAT` / `RUNNER_NAME` / `RUNNER_LABELS`; first-start registration via GitHub API; subsequent starts skip to `run.sh`.
   - `libicu74` fix: GHA runner's `installdependencies.sh` run during build completes successfully (prior to libicu74 pre-install, it would warn "missing libicu70-72").

4. **Urgency** — quality-of-life, but blocking homelab's current deploy latency pain. Not security-critical today; becomes security-material once the fleet depends on it (daily cron apt-upgrade bakes current trixie-security patches — same model as every other Forge image).

5. **Happy path**:
   1. Branch `feat/FG-051-ubuntu-base-and-github-runner` from `dev`.
   2. Create `images/ubuntu-slim-noble/` (Dockerfile + image.yaml + PROMISES.yaml + tests). `tag: "24.04"`, `publish-pre-builders` tier.
   3. Create `images/github-runner-noble/` (Dockerfile + image.yaml + PROMISES.yaml + tests + `entrypoint.sh` + vendored `requirements-dev.txt` + `ansible-requirements.yml`). `tag: "latest"`, resolve runner version via GitHub API.
   4. Wire `scripts/build-image.sh` auto-build + ref resolution for `UBUNTU_SLIM_NOBLE_REF`. Update `scripts/discover-images.sh` `_PRE_BUILDERS` array. Update `.github/workflows/build.yml` publish-pre-builders comment.
   5. Add 2 new CAPs to `docs/CAPABILITIES.md`: `build.ubuntu-base-noble` + `image.github-runner-noble-pre-baked`. Update `memory/design-decisions.md` with the Ubuntu precedent.
   6. Red acceptance test `test_FG_051_ubuntu-base-and-github-runner.sh` — both images build, smokes pass, standard entrypoint registers correctly.
   7. `make check-smart-strict` green locally.
   8. PR to `dev` → CI full-check → auto-merge on green per workflow.md step 8.
   9. Daily cron publishes both images; homelab migrates via a follow-up homelab PR (doc at `docs/forge-fg-051-github-runner-image-migration.md` provided).

6. **Edge cases / failure modes**:
   - **Ubuntu 24.04 EOL in April 2029** — need to add ubuntu-slim-oracular (25.04 if LTS) or ubuntu-slim-questing (26.04 LTS) before then. ~3 years out, plenty of warning.
   - **Runner version :latest resolves mid-day on a release day** — upstream GHA runner releases weekly-ish. Daily cron picks up new versions within 24h. Risk: a broken upstream release lands → self-hosted runners fail to start. Mitigation: `--build-arg RUNNER_VERSION=v2.XXX.X` override lets homelab pin a known-good version locally if upstream ever ships a broken build.
   - **libicu bumps in Ubuntu 24.04** — unlikely within the LTS window; if Canonical ships libicu75 or 76 as a backport, our `apt-get install libicu74` would fail. Mitigation: smoke test asserts libicu is present (catches); switch to an apt-style wildcard (`libicu7?`) or dynamic resolution if observed.
   - **homelab bumps a Python dep version** — Forge's vendored `requirements-dev.txt` drifts. CI continues to work; homelab's tests might pass with a slightly older pin than they're testing locally. Mitigation: drift smoke (optional — see below).
   - **Entrypoint called without env vars (GITHUB_ORG unset)** — runner fails to register. Entrypoint should print a clear error and exit nonzero (not hang). Smoke covers.
   - **Volume gotcha from homelab's README**: `/home/runner` named volume shadowing the baked runner binary after first start. Operator responsibility, not image concern; document in the homelab migration doc.
   - **Ubuntu switches to systemd-only runtime inside Docker** (hypothetical) — our image runs as PID 1 via entrypoint, no systemd needed. Resistant to this.

7. **Out of scope**:
   - **Multi-arch (arm64)**: amd64-only, matches every other Forge image.
   - **Ephemeral runners / pool scaling**: single persistent runner is sufficient for homelab's volume. Future story if N>1.
   - **Running GHA runner as nonroot**: runner itself refuses UID 0 without `RUNNER_ALLOW_RUNASROOT=1`; homelab + our image both set this env. Switching to a nonroot UID is a non-trivial filesystem-perms change (named volume at /home/runner would need chown init).
   - **Chainguard-style stripped image**: the point of this image is CI-tool availability, not minimalism.
   - **Debian-trixie-based variant** (`github-runner-trixie`): the libicu74 vs libicu76 friction is the reason we picked Ubuntu. Could ship a trixie variant later but no consumer asking.
   - **Runtime shell**: Ubuntu brings its own; we don't strip it. CI jobs expect `/bin/bash` + coreutils. `apt` kept.
   - **`absence.os-cves` promise**: slim image has an apt+dpkg database. Nonzero scan baseline accepted.
   - **Scratch runtime**: nonsensical for a CI runner.

8. **How we know it's done** — see Gherkin below.

9. **Capabilities delivered or extended**:
   - NEW `build.ubuntu-base-noble` — Forge's first Ubuntu base. `ubuntu-slim-noble:24.04` published with apt-upgrade + CA + libicu74, available as a FROM reference for any downstream Ubuntu-needing image. Published in the `publish-pre-builders` tier. Single-upstream-consumer rule (FG-042): `FROM ubuntu:24.04` consumed by exactly one forge image (this one); downstream Ubuntu-based images must FROM `ubuntu-slim-noble`, not `ubuntu:24.04`.
   - NEW `image.github-runner-noble-pre-baked` — GitHub Actions self-hosted runner image with homelab-compatible CI toolset pre-baked (runner binary + hadolint + terraform + shellcheck + make + jq + unzip + ansible + ansible-lint + ruff + yamllint + pytest + pytest-xdist + PyJWT + fastapi + ansible.posix + community.general). First-start registration via env-driven entrypoint.sh matching homelab's existing shape. Eliminates homelab's deploy-time image-build latency.
   - EXT `build.ref-latest-release` — now covers the GHA runner binary too. Adds `actions/runner` to the consumer list.
   - EXT `image.has-shell` — now lists `github-runner-noble` + `ubuntu-slim-noble` (slim contract applies).
   - EXT `scan.nonzero-accepted` — new slim image, accepts the Ubuntu apt baseline CVE count.

## Gherkin acceptance

```
Scenario: ubuntu-slim-noble:24.04 publishes with the standard triple
  Given a successful build.yml publish cycle
  When ghcr.io/bboortz/ubuntu-slim-noble:24.04 resolves on GHCR
  Then cosign verify succeeds with the standard --certificate-identity
   And the SBOM lists ubuntu-noble packages + their resolved versions
   And the grype scan is attached
   And /etc/os-release reports UBUNTU_CODENAME=noble

Scenario: ubuntu-slim-noble is apt-upgraded + has CA + libicu74
  Given the built ubuntu-slim-noble image
  When `docker run --rm <ref> -c "test -f /etc/ssl/certs/ca-certificates.crt && dpkg -l libicu74"` runs
  Then both the CA bundle exists and libicu74 is installed
   And /var/lib/apt/lists/ is empty (apt-upgrade cleanup done)

Scenario: github-runner-noble:latest publishes with the standard triple
  Given a successful build.yml publish cycle
  When ghcr.io/bboortz/github-runner-noble:latest resolves on GHCR
  Then cosign verify succeeds
   And the SBOM lists the apt + pip + ansible-galaxy dep graph

Scenario: github-runner-noble bakes the full homelab-compatible CI toolset
  Given the built github-runner-noble image
  When each of the following tools is probed with --version:
       git, curl, jq, unzip, make, python3, pip, shellcheck, hadolint,
       terraform, ansible, ansible-lint, ruff, yamllint, pytest
  Then each prints its version line and exits 0
   And hadolint reports 2.15.1
   And terraform reports v1.17.2

Scenario: GitHub Actions runner binary is the resolved upstream latest
  Given the built github-runner-noble image
  When /home/runner/bin/Runner.Listener --version runs
  Then stdout reports a version matching v[0-9]+\.[0-9]+\.[0-9]+
   And the version matches the upstream actions/runner latest release at build time
   And the resolved version is baked into org.opencontainers.image.revision

Scenario: entrypoint.sh handles first-start registration + subsequent restart
  Given the built github-runner-noble image
  When the container starts with GITHUB_ORG + GITHUB_RUNNER_PAT + RUNNER_NAME + RUNNER_LABELS set
       AND /home/runner/.runner does NOT exist
  Then entrypoint reads the env, requests a runner registration token via the GitHub API,
       runs config.sh --unattended --replace, then execs run.sh
  When the container restarts with the same env
       AND /home/runner/.runner DOES exist
  Then entrypoint skips config.sh and execs run.sh directly

Scenario: ansible-galaxy collections are pre-installed
  Given the built github-runner-noble image
  When `ansible-galaxy collection list` runs
  Then the output includes `ansible.posix` and `community.general`

Scenario: Homelab can consume the image directly
  Given homelab's docker/github-runner/docker-compose.yml is updated to
       `image: ghcr.io/bboortz/github-runner-noble:latest`
       AND the `build:` key is removed
  When `docker compose up -d github-runner` runs on server2
  Then no `docker build` step occurs (just pull)
   And the runner registers and starts within the existing `start_period: 90s` healthcheck window
   And homelab's existing CI jobs targeting [self-hosted, linux, server2] execute with unchanged behavior
```

## References

- Plan: `docs/plan/FG-051-ubuntu-base-and-github-runner-plan.md`
- Red test: `tests/acceptance/test_FG_051_ubuntu-base-and-github-runner.sh`
- Homelab migration doc (companion): `~/git/homelab/docs/forge-fg-051-github-runner-image-migration.md` (written at ship time)
- Precedents: FG-042 (forge-rooted slim bases) — this is the Ubuntu-world analog of debian-slim-trixie. FG-050 (`build.ref-latest-release`) — the resolve-upstream-latest pattern used for the runner binary. FG-046 (`forge-builder-go-trixie`) — same shape of dedicated-toolchain exemption.
- Upstream: [actions/runner](https://github.com/actions/runner), [hadolint/hadolint](https://github.com/hadolint/hadolint), [hashicorp/terraform](https://github.com/hashicorp/terraform).
- Homelab plan the pain stems from: `~/git/homelab/docs/github-runner-plan.md` (explicitly non-goaled a forge image at story time; FG-051 reverses that decision after measured deploy-time pain).
