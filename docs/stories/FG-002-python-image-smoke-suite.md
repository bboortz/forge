---
id: FG-002
slug: python-image-smoke-suite
status: shipped
owner: bboortz
created: 2026-11-03
---

# FG-002 — python image smoke suite + per-image test convention

FG-001 proved the *pipeline* works: build, scan, sign, push, verify. It did not prove the *image* works — nothing exercises that `python3 -c "import ssl"` succeeds, that the CA bundle is present, that `pip` resolves wheels, that the image size didn't balloon. FG-002 introduces the `images/<name>/tests/` co-located convention and populates it for `python:3.13-slim-trixie` with 6 smoke scripts. Every future image inherits the pattern by convention — `images/nginx/tests/`, `images/postgres/tests/`, and critically the `FROM scratch` runtime story (FG-003) uses the same suite as its oracle.

## 9 canonical answers

See `_9-questions.md` for the question set.

1. **Who** — Forge maintainer adding or modifying any image; downstream Python consumer who needs assurance the image actually does Python things (import stdlib, open a TLS connection, install a wheel).
2. **When** — Pre-commit (if `images/<name>/tests/` touched), pre-push `make check`, PR CI full-check, push-to-dev CI; also runs automatically on any `apt upgrade`-driven image change.
3. **What success looks like** —
   - `images/python/tests/` contains ≥ 5 executable `.sh` smoke scripts
   - `make test-images IMAGE_NAME=python` discovers each one, runs it against the just-built `forge-local/python:3.13-slim-trixie`, reports per-script pass/fail, aggregate exit 0
   - Each smoke script is independently runnable: `bash images/python/tests/smoke_imports.sh`
   - `make check` includes `test-images` after `test-acceptance`
4. **Urgency** — foundation tier. FG-003's `FROM scratch` runtime cannot ship without an image-contract oracle: a scratch build whose ldd closure is subtly wrong (`import ssl` works but `import hashlib` does not) would otherwise pass every pipeline test and silently break every consumer.
5. **Happy path** —
   1. Scaffold `images/python/tests/` with six smoke scripts (shellcheck-clean, `set -euo pipefail` each).
   2. `Makefile` gains `test-images` target that globs `images/*/tests/*.sh` and runs each with the just-built image's env.
   3. `make check` adds `test-images` as a post-`test-acceptance` step.
   4. `memory/docker-standard.md` gets a `§ Per-image smoke tests` section documenting the convention.
   5. Red acceptance test at `tests/acceptance/test_FG_002_*.sh` asserts: dir present, discovery works, all scripts exit 0.
6. **Edge cases / failure modes** —
   - Image missing a stdlib module after a future `apt upgrade` → `smoke_imports` catches
   - CA bundle removed or moved → `smoke_ca_bundle` + `smoke_tls_handshake` catch
   - Image size regression from upstream apt-upgrade → `smoke_size` fails (base × 1.1 budget)
   - Network blip during `pip install --dry-run` → re-run; we accept this flakiness per decision
   - Running on non-x86_64 host → `docker run` emulates via QEMU; scripts are arch-neutral
   - Base image upstream doesn't exist locally when `smoke_size` runs → script pulls it explicitly
7. **Out of scope** —
   - `FROM scratch` runtime engineering (FG-003 — will extend this suite without new tests)
   - Any sid pin (FG-004)
   - `nginx` / `postgres` image smoke suites (inherit the convention; separate stories)
   - CVE-specific assertions (lands with FG-004)
   - Image-size *regression* gate comparing to previous `:latest` (this story enforces the absolute base × 1.1 budget only)
8. **How we know it's done** — see Gherkin below.
9. **Capabilities delivered or extended** —
   - NEW `test.image-smoke-suite` — per-image contract tests co-located under `images/<name>/tests/`; each image maintains its own guarantees
   - NEW `test.makefile-glob` — `make test-images` discovers and runs every `images/*/tests/*.sh` against the just-built local image
   - NEW `test.size-budget` — image-size assertion vs. upstream base × 1.1 (reusable constant for every future image)

## Gherkin acceptance

```
Scenario: Smoke suite lives next to the Dockerfile
  Given the image directory images/python/
  Then images/python/tests/ exists
   And contains at least 5 executable .sh files

Scenario: make test-images discovers and runs the suite
  Given a freshly built forge-local/python:3.13-slim-trixie
  When `make test-images IMAGE_NAME=python` runs
  Then every smoke script executes
   And the aggregate exit code is 0

Scenario: Each smoke script is independently runnable
  Given a freshly built forge-local/python:3.13-slim-trixie
  When bash images/python/tests/<name>.sh runs for each script
  Then each exits 0

Scenario: Python core stdlib is present
  Given the image is built
  When the container runs `python3 -c "import ssl, hashlib, json, urllib.request"`
  Then it exits 0

Scenario: TLS context initializes
  Given the image is built
  When the container runs `python3 -c "import ssl; ssl.create_default_context()"`
  Then it exits 0

Scenario: CA bundle is present and readable
  Given the image is built
  When the container runs `test -r /etc/ssl/certs/ca-certificates.crt`
  Then it exits 0

Scenario: pip resolves and dry-runs a real wheel
  Given the image is built
  When the container runs `pip install --dry-run requests`
  Then it exits 0

Scenario: Container entrypoint runs python3 by default
  Given the image is built
  When the container runs with default entrypoint and `-c "print('ok')"`
  Then stdout contains "ok"

Scenario: Image size is within budget (base × 1.1)
  Given the image is built
  And python:3.13-slim-trixie is available locally
  When sizes are compared
  Then our image size ≤ upstream base size × 1.1

Scenario: make check runs test-images
  Given no local changes
  When `make check` runs
  Then test-images executes after test-acceptance
   And both pass
```

## References

- Plan: [`docs/plan/FG-002-python-image-smoke-suite-plan.md`](../plan/FG-002-python-image-smoke-suite-plan.md)
- Red test: [`tests/acceptance/test_FG_002_python-image-smoke-suite.sh`](../../tests/acceptance/test_FG_002_python-image-smoke-suite.sh)
- Capabilities: see [`docs/CAPABILITIES.md`](../CAPABILITIES.md)
