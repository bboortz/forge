# FG-001 — Plan: python-slim end-to-end publish pipeline

**Story**: [`docs/stories/FG-001-python-slim-pipeline.md`](../stories/FG-001-python-slim-pipeline.md)
**Status**: in-progress
**Branch**: `feat/FG-001-python-slim-pipeline`

## Design delta

Wire the full publish pipeline on the simplest possible image: `python:3.13-slim-trixie` with `apt upgrade` applied, published 1:1 to `ghcr.io/bboortz/python:3.13-slim-trixie`. The scope of this change is pipeline wiring, not image engineering — a consumer who swaps `docker pull python:3.13-slim-trixie` for the Forge equivalent gets effectively the same image plus three attestations and a signature.

The single source directory is `images/python/`. A single Dockerfile (not two-stage; the runtime stage is the upstream slim image itself after `apt upgrade`). The build is amd64-only via plain `docker build` — buildx is not required because arm64 is explicitly out of scope. Multi-arch adoption is deferred to the arm64 story.

Keyless cosign + GHA OIDC is the publish-time signing path; `make sign-local` with a `.cosign/` key pair (gitignored) is the dev-time path. Attestations use `cosign attest --predicate <file> --type <cyclonedx|vuln>`.

## Alternatives rejected

- **Start with `FROM scratch` runtime** — three unknowns at once (ldd closure + attestation attach + GHCR auth). Hard to debug in isolation; a failure in any one would stall the others.
- **Start with a sid pin against a current CVE** — attacks the differentiator first, which is attractive, but needs a working publish pipeline underneath anyway. Better to split the risk.
- **Multi-arch from day one** — QEMU arm64 on GHA shared runners adds 20–40 minutes of build time and masks real signal. Deferred.
- **Buildx + registry buildcache** — nice ergonomic win, but a dependency unknown. Not needed for FG-001 build times.
- **Scan-regression gate from day one** — needs a `:latest` baseline to compare against. We don't have one yet. Deferred until after the first publish.

## Breaking changes

None. This is the initial publish of this image.

Public verify command locked at:

```
cosign verify \
  --certificate-identity https://github.com/bboortz/forge/.github/workflows/build.yml \
  --certificate-oidc-issuer https://token.actions.githubusercontent.com \
  ghcr.io/bboortz/python:3.13-slim-trixie
```

Downstream consumers depend on the exact certificate-identity path. Moving the workflow file is a breaking change for every verifier.

## Merge plan

Fast tier (local `make check`): hadolint, shellcheck, yamllint, actionlint, verify-sid-pins (vacuous — no pins yet), verify-traceability, test-acceptance. For image-touching changes also: `make build && make scan && make sign-local && make verify` locally. See `memory/workflow.md § Blocking gates` for the full matrix.

PR CI (`.github/workflows/pr.yml`) runs the real build + scan on the GHA runner.

## Rollout plan

1. Merge PR to `dev`.
2. Dev → `main` fast-forward (CI promotion; manual in this phase while CI promotion isn't wired yet).
3. Trigger `.github/workflows/build.yml` via `workflow_dispatch` to publish the first digest immediately.
4. Flip the newly created GHCR package visibility to `public` (one-time manual action; TODO: automate via `octokit`-style step once we add a second image).
5. Confirm `cosign verify` succeeds against the just-published digest from an external workstation.
6. Next 03:00 UTC cron confirms the daily rebuild path.

## Shipping evidence

One row per Gherkin scenario + one per CAP delivered. Filled during the pre-ship audit (step 6a).

| Item | Pointer | Status |
|------|---------|--------|
| Scenario: Image builds locally | `tests/acceptance/test_FG_001_python-slim-pipeline.sh` (section 1) | ✅ |
| Scenario: SBOM is CycloneDX | `tests/acceptance/test_FG_001_python-slim-pipeline.sh` (section 2) | ✅ |
| Scenario: grype scan JSON | `tests/acceptance/test_FG_001_python-slim-pipeline.sh` (section 3) | ✅ |
| Scenario: Local sign+verify round-trip | `tests/acceptance/test_FG_001_python-slim-pipeline.sh` (section 4) | ✅ |
| Scenario: External cosign verify | `tests/acceptance/test_FG_001_python-slim-pipeline.sh` (section 6, PUBLISHED=1) | ⚠️ post-publish |
| Scenario: Daily cron rebuild | `.github/workflows/build.yml` (schedule block) | ⚠️ post-publish |
| Scenario: PR CI scans without publishing | `.github/workflows/pr.yml` | ✅ |
| CAP `build.pr-ci` | `.github/workflows/pr.yml` + test section 1–3 | ✅ |
| CAP `build.daily-publish` | `.github/workflows/build.yml` | ⚠️ post-publish |
| CAP `sbom.cyclonedx-attest` | test section 2 + `build.yml` attest step | ✅ |
| CAP `scan.grype-attest` | test section 3 + `build.yml` attest step | ✅ |
| CAP `sign.cosign-keyless-oidc` | `build.yml` sign step (OIDC permissions block) | ⚠️ post-publish |
| CAP `sign.cosign-local-dev` | test section 4 + `make sign-local` target | ✅ |
| CAP `verify.consumer-cmd` | test section 6 + README Quick Start | ⚠️ post-publish |
| CAP `publish.ghcr-public-pull` | manual: GHCR package visibility flip | ⚠️ post-publish |

**⚠️ post-publish** rows require the first `workflow_dispatch` publish to transition to ✅. Shipping to `dev` is allowed with these rows pending; promotion to shipped status requires them to transition after step 4 of the rollout plan.
