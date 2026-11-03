---
id: FG-001
slug: python-slim-pipeline
status: in-progress
owner: bboortz
created: 2026-11-03
---

# FG-001 — python-slim end-to-end publish pipeline

Wire the full Forge publish pipeline — build, SBOM, scan, keyless sign, push, verify — on the simplest possible image shape: `python:3.13-slim-trixie` with `apt upgrade` applied. No `FROM scratch` runtime (that's FG-002). No sid pin (that's FG-003). amd64 only. This story's purpose is to shake out all the pipeline wiring (GHA OIDC permissions, cosign attestation attach, GHCR public visibility, external cosign-verify command) on an image whose content is trivial, so subsequent stories debug one unknown at a time.

## 9 canonical answers

See `_9-questions.md` for the question set.

1. **Who** — primary consumer is the Forge maintainer wiring the pipeline. Secondary (post-publish): a Python dev or security engineer pulling `ghcr.io/bboortz/python:3.13-slim-trixie` and running `cosign verify` against it.
2. **When** — fires on three triggers: PR touching `images/`, `Makefile`, or `.github/workflows/` (runs `pr.yml` build + scan, no push); merge to `main` via `workflow_dispatch` (runs `build.yml` and publishes the first digest); daily 03:00 UTC cron (rebuilds with `--pull`, publishes a fresh digest under the same tag).
3. **What success looks like** — all five observable:
   - `docker pull ghcr.io/bboortz/python:3.13-slim-trixie` succeeds without authentication
   - `docker run --rm ghcr.io/bboortz/python:3.13-slim-trixie python3 -c "print('ok')"` prints `ok`
   - `cosign download attestation --predicate-type <cyclonedx|vuln> ghcr.io/bboortz/python:3.13-slim-trixie` returns a non-empty predicate for both types
   - `cosign verify --certificate-identity https://github.com/bboortz/forge/.github/workflows/build.yml --certificate-oidc-issuer https://token.actions.githubusercontent.com ghcr.io/bboortz/python:3.13-slim-trixie` exits 0
   - A second cron run on day 2 publishes a new digest under the same tag; both digests are independently signed and attested
4. **Urgency** — foundation tier. Nothing in FG-002, FG-003, or any later image story works without this pipeline existing.
5. **Happy path** —
   1. Feature branch `feat/FG-001-python-slim-pipeline` lands `images/python/{Dockerfile,build.sh,sid-pins/}`, `Makefile`, `.github/workflows/{pr,build}.yml`, `.pre-commit-config.yaml`, red `tests/acceptance/test_FG_001_python-slim-pipeline.sh`, plus the DD-TGD scaffolding (`docs/stories/_template.md`, `_9-questions.md`, `INDEX.md`; `docs/plan/_template.md`, `IDEAS.md`; `docs/CAPABILITIES.md`).
   2. PR to `dev`. Local `make check` + `make test-acceptance` green.
   3. Dev → main CI fast-forwards.
   4. Operator triggers `.github/workflows/build.yml` via `workflow_dispatch` (first publish).
   5. buildx-free `docker build` for `linux/amd64` from `python:3.13-slim-trixie` + `apt-get -y upgrade`.
   6. syft produces CycloneDX SBOM; attached via `cosign attest --predicate <sbom> --type cyclonedx`.
   7. grype scans the image; JSON result attached via `cosign attest --predicate <scan> --type vuln`.
   8. cosign signs the digest keylessly using the GHA OIDC token.
   9. Image + attestations pushed to `ghcr.io/bboortz/python:3.13-slim-trixie`. Package visibility set to public.
   10. External user runs the verify command on a clean workstation; exit code 0.
   11. Next 03:00 UTC cron publishes a fresh digest under the same tag.
6. **Edge cases / failure modes** —
   - `permissions: id-token: write` missing in `build.yml` → cosign keyless sign cannot acquire an OIDC token.
   - GHCR package visibility defaults to private → anonymous pull fails. Must be flipped to public after first publish.
   - `cosign attest` attaches predicates in the wrong OCI annotation format → `cosign download attestation --predicate-type ...` returns empty.
   - Certificate-identity string in the verify command does not match the workflow file path exactly → verify fails. Treat the path as a stable public interface.
   - Daily cron races a Docker Hub tag rotation on `python:3.13-slim-trixie` → rebuild should succeed; new upstream digest is desirable (that's the point of `--pull`).
   - Local developer runs `make sign-local` without a `.cosign/` key pair → `make verify` cannot complete locally. The Makefile `make tools` target generates one on first run.
7. **Out of scope** —
   - `FROM scratch` runtime (FG-002)
   - Any sid pin (FG-003)
   - Multi-arch / arm64 via buildx + QEMU (deferred; see `docs/plan/IDEAS.md`)
   - Multi-version matrix (3.12 / 3.14 variants) (deferred)
   - Scan-regression gate — PR CI runs `grype` but does not fail on new HIGH/CRITICAL yet (deferred)
   - Image-size gate (deferred)
   - Buildcache in registry (deferred)
   - `nginx-stable`, `postgres-18` images (deferred; roadmap)
8. **How we know it's done** — see Gherkin below.
9. **Capabilities delivered or extended** —
   - NEW `build.pr-ci` — PR builds + scans without publishing
   - NEW `build.daily-publish` — daily rebuild with `--pull`; publishes + attests + signs
   - NEW `sbom.cyclonedx-attest` — syft CycloneDX attached as OCI attestation
   - NEW `scan.grype-attest` — grype JSON attached as OCI attestation
   - NEW `sign.cosign-keyless-oidc` — keyless sign via GHA OIDC in `build.yml`
   - NEW `sign.cosign-local-dev` — stored-key signing path for out-of-CI dev via `make sign-local`
   - NEW `verify.consumer-cmd` — public cosign-verify command works from any clean workstation
   - NEW `publish.ghcr-public-pull` — anonymous pull from GHCR works

## Gherkin acceptance

```
Scenario: Image builds locally
  Given python:3.13-slim-trixie as the builder base
  When `make build IMAGE_NAME=python IMAGE_TAG=3.13-slim-trixie` runs
  Then a local image forge-local/python:3.13-slim-trixie exists
   And `docker run --rm` the image with `python3 -c "print('ok')"` prints "ok"

Scenario: SBOM is produced in CycloneDX format
  Given a built local image
  When `make scan` runs
  Then build/python-3.13-slim-trixie.sbom.json has `.bomFormat == "CycloneDX"`

Scenario: grype scan writes a parseable JSON report
  Given a built local image
  When `make scan` runs
  Then build/python-3.13-slim-trixie.grype.json has `.descriptor.name == "grype"`

Scenario: Local sign + verify round-trip
  Given a built local image
  When `make sign-local` runs and then `make verify` runs
  Then both exit 0
   And the signature is attached to the local-image digest

Scenario: External cosign verify succeeds against the published digest
  Given a Forge-published digest at ghcr.io/bboortz/python:3.13-slim-trixie
  When cosign verify runs with --certificate-identity bound to .github/workflows/build.yml
  Then verify exits 0
  (Published checks run only when PUBLISHED=1 is set — nightly / post-publish job.)

Scenario: Daily cron rebuilds the same tag
  Given a published digest D1 from day 1
  When the day-2 cron runs with --pull
  Then a new digest D2 is published under the same tag
   And D2 is independently signed and attested

Scenario: PR CI scans but does not publish
  Given a PR that touches images/python/
  When pr.yml runs
  Then build and scan succeed
   And nothing is pushed to GHCR
```

## References

- Plan: [`docs/plan/FG-001-python-slim-pipeline-plan.md`](../plan/FG-001-python-slim-pipeline-plan.md)
- Red test: [`tests/acceptance/test_FG_001_python-slim-pipeline.sh`](../../tests/acceptance/test_FG_001_python-slim-pipeline.sh)
- Capabilities: see [`docs/CAPABILITIES.md`](../CAPABILITIES.md)
