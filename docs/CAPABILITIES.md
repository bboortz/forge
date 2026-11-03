# Capabilities matrix

The source of truth for what Forge can do. Every entry has bidirectional links to the acceptance test(s) that exercise it; `make verify-traceability` enforces that both directions are present.

Format per entry:

```
### <cap.id>

One-line description.

- **Delivered by**: FG-NNN
- **Covered by**: `tests/acceptance/test_FG_NNN_<slug>.sh`
```

CAP id convention: `<domain>.<verb-or-shape>`. Domains in current use: `build`, `scan`, `sbom`, `sign`, `verify`, `publish`, `pins`.

---

### build.pr-ci

On push to `dev` or PR targeting `dev`, build the affected image(s) and run grype against each. Does not push to GHCR. Lives in `.github/workflows/ci.yml` as the full-check job.

- **Delivered by**: FG-001
- **Covered by**: `tests/acceptance/test_FG_001_python-slim-pipeline.sh`

### build.daily-publish

Daily 03:00 UTC cron (`workflow_dispatch` also available) builds every image with `--pull`, attaches attestations, signs, and pushes.

- **Delivered by**: FG-001
- **Covered by**: `tests/acceptance/test_FG_001_python-slim-pipeline.sh`

### sbom.cyclonedx-attest

syft produces a CycloneDX JSON SBOM for every built image. The SBOM is attached to the digest as an OCI attestation.

- **Delivered by**: FG-001
- **Covered by**: `tests/acceptance/test_FG_001_python-slim-pipeline.sh`

### scan.grype-attest

grype scans every built image. The JSON result is attached to the digest as an OCI attestation.

- **Delivered by**: FG-001
- **Covered by**: `tests/acceptance/test_FG_001_python-slim-pipeline.sh`

### sign.cosign-keyless-oidc

In GitHub Actions, cosign signs the digest keylessly, using the workflow's OIDC token.

- **Delivered by**: FG-001
- **Covered by**: `tests/acceptance/test_FG_001_python-slim-pipeline.sh`

### sign.cosign-local-dev

For out-of-CI development, `make sign-local` uses a local cosign key pair under `.cosign/` (gitignored). Locally signed digests are never pushed to `ghcr.io/bboortz/`.

- **Delivered by**: FG-001
- **Covered by**: `tests/acceptance/test_FG_001_python-slim-pipeline.sh`

### verify.consumer-cmd

`cosign verify --certificate-identity .../build.yml --certificate-oidc-issuer https://token.actions.githubusercontent.com <image>` succeeds against any Forge-published digest from any workstation with cosign installed.

- **Delivered by**: FG-001
- **Covered by**: `tests/acceptance/test_FG_001_python-slim-pipeline.sh`

### publish.ghcr-public-pull

`docker pull ghcr.io/bboortz/<image>:<tag>` succeeds without authentication.

- **Delivered by**: FG-001
- **Covered by**: `tests/acceptance/test_FG_001_python-slim-pipeline.sh`

### test.image-smoke-suite

Per-image contract tests live co-located with the recipe under `images/<name>/tests/*.sh`. Each image maintains its own guarantees; deleting the image removes its tests cleanly.

- **Delivered by**: FG-002
- **Covered by**: `tests/acceptance/test_FG_002_python-image-smoke-suite.sh`

### test.makefile-glob

`make test-images` (optionally scoped by `IMAGE_NAME=<name>`) discovers and runs every `images/*/tests/*.sh` against the just-built local image. Aggregated into `make check`.

- **Delivered by**: FG-002
- **Covered by**: `tests/acceptance/test_FG_002_python-image-smoke-suite.sh`

### test.size-budget

Every image asserts its final size is at most **upstream base × 1.1**, where "upstream base" is the `FROM` reference used in the Dockerfile. 10% headroom accommodates `apt upgrade` deltas.

- **Delivered by**: FG-002
- **Covered by**: `images/python/tests/smoke_size.sh`
