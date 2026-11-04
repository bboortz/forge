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

Every image asserts its final size is at most **upstream base × 1.1**, where "upstream base" is the `FROM` reference used in the Dockerfile. 10% headroom accommodates `apt upgrade` deltas. Scratch variants add an additional hard byte-ceiling (60 MB for python-scratch-trixie).

- **Delivered by**: FG-002 (base × 1.1)
- **Extended by**: FG-003 (scratch hard ceiling)
- **Covered by**: `images/python-slim-trixie/tests/smoke_size.sh`, `images/python-scratch-trixie/tests/smoke_size.sh`

### build.two-stage-scratch

Two-stage Dockerfile pattern: builder stage on a conventional Debian base, runtime stage `FROM scratch` with explicit COPY lines enumerating the ldd closure + CA bundle + zoneinfo + nss.

- **Delivered by**: FG-003
- **Covered by**: `tests/acceptance/test_FG_003_python-scratch-runtime.sh`

### image.no-shell

Scratch-runtime variants contain no `/bin/sh` or other shells. Attempting `docker run --rm --entrypoint=/bin/sh <image>` fails.

- **Delivered by**: FG-003
- **Covered by**: `images/python-scratch-trixie/tests/smoke_scratch_no_shell.sh`

### image.zero-os-cves

grype run against a scratch-runtime image reports zero matches whose source is a Debian package. Every surviving finding is a PyPI dep the consumer installed — no OS-package noise.

- **Delivered by**: FG-003
- **Covered by**: `images/python-scratch-trixie/tests/smoke_scratch_zero_os_cves.sh`

### build.central-script

Single `scripts/build-image.sh <image-dir>` drives every image build. Reads `images/<dir>/image.yaml` for the publishable repo + tag.

- **Delivered by**: FG-003
- **Covered by**: `tests/acceptance/test_FG_003_python-scratch-runtime.sh`

### test.central-script

Single `scripts/test-images.sh [image-dir]` discovers every `images/*/tests/smoke_*.sh` and runs it with the correct `IMAGE_NAME`/`IMAGE_TAG`/`REGISTRY` env from the image's `image.yaml`.

- **Delivered by**: FG-003
- **Covered by**: `tests/acceptance/test_FG_003_python-scratch-runtime.sh`

### publish.matrix-auto-discovery

`.github/workflows/build.yml` matrix job is driven by `scripts/discover-images.sh`, which emits a JSON matrix listing every `images/*/image.yaml`. Adding a new image dir auto-enrolls it in the daily publish pipeline — no workflow edit needed.

- **Delivered by**: FG-003
- **Covered by**: `scripts/discover-images.sh` + `.github/workflows/build.yml`

### image.nginx-serves-http

`nginx-scratch-trixie` answers `curl http://localhost/` with HTTP 200 and the default welcome page out of the box. Minimal self-contained config shipped at `/etc/nginx/nginx.conf`.

- **Delivered by**: FG-006
- **Covered by**: `tests/acceptance/test_FG_006_nginx-scratch-trixie.sh`, `images/nginx-scratch-trixie/tests/smoke_serves_200.sh`

### test.smoke-server-helper

`scripts/smoke-server.sh` is the reusable start-wait-probe-stop harness for server images. Takes `--image`, `--port`, `--ready`, `--test`, substitutes `__HOST_PORT__` from the docker-assigned ephemeral host port, polls readiness, runs the test command, always cleans up.

- **Delivered by**: FG-006
- **Covered by**: `tests/acceptance/test_FG_006_nginx-scratch-trixie.sh` (and FG-007 postgres consumes the same helper)

### image.postgres-serves-sql

`postgres-scratch-trixie` starts and answers `psql -c 'SELECT 1'` end-to-end against an externally-initialized cluster. Binary-compatible with Debian postgres data directories (uid 999 pinned to match Docker Hub).

- **Delivered by**: FG-007
- **Covered by**: `tests/acceptance/test_FG_007_postgres-scratch-trixie.sh`, `images/postgres-scratch-trixie/tests/smoke_server_accepts.sh`

### test.sidecar-init

Test pattern for images whose one-time initialization needs a shell (e.g. postgres' `initdb` uses `system()` internally). A shelled sidecar image (Docker Hub's `postgres:17`) writes initial state into a named volume; the scratch image then runs against that volume. Documented limitation: scratch images cannot initialize in-container for workflows that invoke a shell.

- **Delivered by**: FG-007
- **Covered by**: `images/postgres-scratch-trixie/tests/smoke_server_accepts.sh`

### build.scratch-baseline

Shared signed foundation for every Forge scratch image. `scratch-base-trixie` ships a documented common standard: dynamic linker, core glibc (sans `libutil.so.1`), TLS trust, common compression, DNS resolution, network-resolution data (`/etc/services` + `/etc/protocols` + `/etc/hosts`), `/etc/localtime` → UTC, zoneinfo, standard identities (root + nonroot 65532 + nobody), and writable `/tmp` + `/var/tmp` + `/nonroot`. See `docs/baseline-contract.md` for the authoritative API. Derivatives preserve their literal `FROM scratch` runtime line and compose via `COPY --from=scratch_base / /` + an image-specific overlay.

- **Delivered by**: FG-005
- **Extended by**: FG-008 (nonroot identity + network data + /etc/localtime + /var/tmp)
- **Covered by**: `tests/acceptance/test_FG_005_scratch-base-trixie.sh`, `tests/acceptance/test_FG_008_baseline-standard.sh`

### test.scratch-contents

Scratch images have no exec, so smoke suites validate contents by extracting the image via `docker save | tar tf` and asserting required paths are present (or absent). Reusable pattern for any image without a shell / binary that can be probed interactively.

- **Delivered by**: FG-005
- **Extended by**: FG-008 (users/network/time/writable-dirs contracts)
- **Covered by**: `images/scratch-base-trixie/tests/smoke_contents_*.sh`

### docs.baseline-contract

`docs/baseline-contract.md` documents the file-layout API, reserved UIDs, composition contract, ENV re-declaration requirement, non-guarantees, and versioning policy for `scratch-base-trixie`. Authoritative audit surface for current and future consumers of Forge scratch images.

- **Delivered by**: FG-008
- **Covered by**: `tests/acceptance/test_FG_008_baseline-standard.sh`

### image.ssl-cert-env

Every Forge scratch derivative re-declares `ENV SSL_CERT_FILE=/etc/ssl/certs/ca-certificates.crt` and `ENV SSL_CERT_DIR=/etc/ssl/certs` in its own Dockerfile. Baseline sets them too but ENV directives don't propagate through `COPY --from=scratch_base` — this convention closes the trap that broke HTTPS for every scratch derivative before FG-009. Memory: [`memory/scratch-closures.md`](../memory/scratch-closures.md) § ENV does not propagate.

- **Delivered by**: FG-009
- **Covered by**: `tests/acceptance/test_FG_009_python-scratch-hardening.sh`

### image.python-scratch-nonroot

`python-scratch-trixie` defaults to `USER 65532:65532`, `WORKDIR /nonroot`, `ENTRYPOINT ["/usr/local/bin/python3"]`, `CMD []`, with `PYTHONDONTWRITEBYTECODE=1` + `PYTHONFAULTHANDLER=1` baked. Distroless convention: `docker run <image> script.py` just works; `docker run <image> pip install ...` needs `--entrypoint=pip`.

- **Delivered by**: FG-009
- **Covered by**: `tests/acceptance/test_FG_009_python-scratch-hardening.sh`, `images/python-scratch-trixie/tests/smoke_user_nonroot.sh`, `images/python-scratch-trixie/tests/smoke_tls_https_real.sh`, `images/python-scratch-trixie/tests/smoke_entrypoint.sh`

### contracts.promises

Every image declares what it guarantees to consumers in a machine-checkable `images/<name>/PROMISES.yaml` file. Each promise carries an id, description, CAP cross-references, and a non-empty list of smoke tests that enforce it. `scripts/verify-contracts.py` lints the graph on every CI run.

- **Delivered by**: FG-010
- **Covered by**: `tests/acceptance/test_FG_010_image-contracts.sh`

### contracts.expectations

Every image that depends on another Forge image declares its consumption surface in `images/<name>/EXPECTATIONS.yaml`. Each expectation names (a) the dependency image + version constraint, (b) the specific promise id it relies on, (c) a human-readable reason, (d) preflight smoke test(s) that fail loudly if the baseline ever deviates. The FG-009 ENV-doesn't-propagate trap would have been caught at PR time under this discipline.

- **Delivered by**: FG-010
- **Covered by**: `tests/acceptance/test_FG_010_image-contracts.sh`

### contracts.verify-gate

`make verify-contracts` is a blocking gate in `make check`. It resolves every expectation against its dependency's promises, checks version constraints, and asserts that every test pointer (PROMISES.tests and EXPECTATIONS.preflight) names an existing executable smoke under `images/*/tests/`. Diagnostics are fully qualified — every error names the file, the id, and the referenced thing.

- **Delivered by**: FG-010
- **Covered by**: `tests/acceptance/test_FG_010_image-contracts.sh`

### contracts.semver-enforcement

`scripts/contracts-semver-check.py` runs as a pre-commit hook on `PROMISES.yaml` edits. It classifies each change as `add` (minor), `remove` (major), or `modify` (same id, changed description — requires `--allow-modify` in commit message). Enforces the `version:` bump is at least as large as the change class; refuses commits that silently rot the contract. Removing a promise requires either (a) same-commit update to every dependent EXPECTATIONS.yaml, or (b) `--allow-breaking` override.

- **Delivered by**: FG-010
- **Covered by**: `tests/acceptance/test_FG_010_image-contracts.sh`

### image.manylinux-wheel-compat

`python-scratch-trixie` ships the `/lib/x86_64-linux-gnu/librt.so.1` ABI stub (14.5 KB, as shipped by Debian trixie — empty since glibc 2.34 merged librt into libc). Required so manylinux2014 / manylinux_2_17 wheels (numpy, scipy, pandas, pillow, cryptography, …) that carry `NEEDED librt.so.1` in their ELF dynamic section dlopen successfully at runtime. Baseline is deliberately not affected — this is a Python-ecosystem concern.

- **Delivered by**: FG-011
- **Covered by**: `tests/acceptance/test_FG_011_librt-manylinux-compat.sh`, `images/python-scratch-trixie/tests/smoke_librt_manylinux.sh`
