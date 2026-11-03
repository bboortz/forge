---
id: FG-003
slug: python-scratch-runtime
status: shipped
owner: bboortz
created: 2026-11-03
---

# FG-003 — python scratch runtime + central build/test scripts

Delivers Forge's differentiator #3 (minimal attack surface via `FROM scratch`) and consolidates two per-image mechanisms into central shell scripts. Introduces a second python variant — `python:3.13-scratch-trixie` — side-by-side with the existing `python:3.13-slim-trixie`. The scratch runtime has no shell, no `apt`, no `dpkg` database; grype against it finds zero Debian-package matches, so every finding that survives into a consumer's scan is a PyPI dep they installed themselves — actionable noise-free output.

The slim variant stays untouched behaviourally. The directory moves from `images/python/` → `images/python-slim-trixie/` to match the new one-dir-per-variant convention, and a new `images/python-scratch-trixie/` lands as its sibling. Both variants publish under the same GHCR package (`ghcr.io/bboortz/python`) with different tag suffixes.

Two refactors land with the story: `scripts/build-image.sh` replaces the per-image `build.sh` and reads an `image.yaml` metadata file per variant; `scripts/test-images.sh` replaces the Makefile's inline test loop. `.github/workflows/build.yml` gains a matrix driven by a new `scripts/discover-images.sh` so adding future variants (nginx, postgres) auto-expands the publish pipeline.

## 9 canonical answers

See `_9-questions.md`.

1. **Who** — Python consumer who runs grype against their base image and wants zero OS-noise findings. Security engineer verifying "actually minimal." Forge maintainer adding future scratch-runtime variants (nginx, postgres).
2. **When** — Pre-commit, pre-push, CI full-check, daily `build.yml` cron (now matrix over every image dir), on `workflow_dispatch`.
3. **What success looks like** —
   - `docker pull ghcr.io/bboortz/python:3.13-scratch-trixie` anonymous pull succeeds
   - `cosign verify --certificate-identity .../build.yml@refs/heads/main ... python:3.13-scratch-trixie` exits 0
   - `grype ghcr.io/bboortz/python:3.13-scratch-trixie -o json | jq '[.matches[] | select(.artifact.type == "deb")] | length' == 0`
   - `docker run --rm --entrypoint=/bin/sh ...` **fails** (no shell in scratch)
   - `docker image inspect ... --format={{.Size}}` ≤ 60 MB
   - `docker run --rm ... pip install --target /tmp/pkg requests` succeeds and the installed wheel imports
   - Both variants share the same smoke suite source where they can; scratch has its own additional assertions
4. **Urgency** — product tier. First real test of differentiator #3; blocks nothing downstream but unlocks the full Forge pitch.
5. **Happy path** —
   1. Rename `images/python/` → `images/python-slim-trixie/`, add `image.yaml`.
   2. Create `images/python-scratch-trixie/` with Dockerfile (two-stage, FROM scratch runtime), image.yaml, empty sid-pins/, tests/.
   3. Factor `scripts/build-image.sh`, `scripts/test-images.sh`, `scripts/discover-images.sh`; Makefile delegates.
   4. Iterate the scratch Dockerfile: `strace` of a representative Python session inside the builder, enumerate explicit COPY lines, iterate until every smoke script passes against the scratch image.
   5. Add scratch-specific smoke scripts: `smoke_scratch_no_shell.sh`, `smoke_scratch_zero_os_cves.sh`. Both variants get `smoke_pip_runtime_install.sh` (real install + import check, supersedes the dry-run test).
   6. `.github/workflows/build.yml` runs a matrix driven by `discover-images.sh`.
   7. README's Images table + Quick Start extended with the scratch row and its verify command.
6. **Edge cases / failure modes** —
   - `import hashlib` or `import ssl` subtly fails because a libcrypto version mismatch (builder trixie vs scratch): COPY exact file, not a symlink
   - `zoneinfo` lookup fails: scratch missing `/usr/share/zoneinfo`
   - TLS handshake fails: `/etc/ssl/certs/ca-certificates.crt` missing or `SSL_CERT_FILE` env-default mismatch
   - `getaddrinfo` fails: missing `libnss_dns.so.2` + `libnss_files.so.2` + `/etc/nsswitch.conf`
   - `pip install` runtime fails because `setuptools` not bundled, or PYPI cert chain rejected due to missing CA bundle at runtime
   - subprocess calls assuming shell: not something we fix; scratch deliberately omits shell, consumers must use `subprocess.run([...])` form, not `shell=True`
   - Image size creeps past 60 MB because pip's wheels are large: budget bumped from the preview's 50 MB to 60 MB to give headroom
7. **Out of scope** — multi-arch (arm64); any sid pin (FG-004); `nginx` / `postgres` scratch variants; image-size *regression* gate vs. previous `:latest`; retiring the slim variant.
8. **Gherkin** — see below.
9. **Capabilities** —
   - NEW `build.two-stage-scratch` — two-stage Dockerfile with `FROM scratch` runtime stage
   - NEW `image.no-shell` — scratch runtime has no `/bin/sh` or other shells
   - NEW `image.zero-os-cves` — grype finds zero Debian-source matches against the scratch runtime
   - NEW `build.central-script` — single `scripts/build-image.sh` drives every image's build via `image.yaml`
   - NEW `test.central-script` — single `scripts/test-images.sh` discovers every `images/*/tests/smoke_*.sh`
   - NEW `publish.matrix-auto-discovery` — `.github/workflows/build.yml` matrix is populated by `scripts/discover-images.sh`, so new image dirs auto-enroll
   - EXT `test.image-smoke-suite` — now owned by multiple image dirs sharing a contract
   - EXT `test.size-budget` — scratch adds a hard 60 MB ceiling in addition to the existing base × 1.1 rule

## Gherkin acceptance

```
Scenario: Slim dir is renamed; scratch dir exists
  Given the repo at HEAD
  Then images/python-slim-trixie/ exists with Dockerfile + image.yaml
   And images/python-scratch-trixie/ exists with Dockerfile + image.yaml
   And images/python/ does not exist

Scenario: Central build script resolves image.yaml
  Given images/python-scratch-trixie/image.yaml with repo: python and tag: 3.13-scratch-trixie
  When scripts/build-image.sh python-scratch-trixie runs
  Then docker builds the image at forge-local/python:3.13-scratch-trixie

Scenario: Central test script runs every variant's suite
  Given both image dirs with tests/
  When scripts/test-images.sh runs
  Then every images/*/tests/smoke_*.sh executes against its respective image
   And aggregate exit code is 0

Scenario: Scratch image has no shell
  Given forge-local/python:3.13-scratch-trixie
  When docker run --rm --entrypoint=/bin/sh fails
  Then smoke_scratch_no_shell.sh exits 0

Scenario: grype against scratch finds zero Debian matches
  Given forge-local/python:3.13-scratch-trixie
  When grype -o json runs
  Then matches[] | select(.artifact.type == "deb") | length == 0

Scenario: Scratch image fits under 60 MB
  Given scratch runtime built
  When docker image inspect size is read
  Then size ≤ 60_000_000 bytes

Scenario: Both variants pass the common smoke suite
  Given forge-local/python:3.13-slim-trixie and forge-local/python:3.13-scratch-trixie
  When common smoke scripts run against each
  Then imports, TLS, CA bundle, entrypoint, size all pass for each variant

Scenario: pip install works at runtime for wheels
  Given either variant's image
  When `pip install --target /tmp/pkg requests` runs in the container
  Then the install succeeds
   And `python3 -c "import sys; sys.path.insert(0,'/tmp/pkg'); import requests"` exits 0

Scenario: GHA matrix auto-discovers image dirs
  Given scripts/discover-images.sh
  When it runs
  Then it emits a JSON matrix listing every images/*/image.yaml
   And build.yml's job matrix consumes it

Scenario: Both variants publish side-by-side
  Given build.yml ran via workflow_dispatch
  Then ghcr.io/bboortz/python has tags 3.13-slim-trixie AND 3.13-scratch-trixie
   And each is independently signed + attested + verifiable
```

## References

- Plan: [`docs/plan/FG-003-python-scratch-runtime-plan.md`](../plan/FG-003-python-scratch-runtime-plan.md)
- Red test: [`tests/acceptance/test_FG_003_python-scratch-runtime.sh`](../../tests/acceptance/test_FG_003_python-scratch-runtime.sh)
- Capabilities: see [`docs/CAPABILITIES.md`](../CAPABILITIES.md)
