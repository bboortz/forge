# FG-009 — Plan: python-scratch hardening + SSL fix

**Story**: [`docs/stories/FG-009-python-scratch-hardening.md`](../stories/FG-009-python-scratch-hardening.md)
**Status**: shipped
**Branch**: `feat/FG-009-python-scratch-hardening`

## Design delta

Addresses four of Beaconry's six verified claims against `python-scratch-trixie`:

| Claim | Fix | Scope |
|-------|-----|-------|
| 1. HTTPS broken (CERTIFICATE_VERIFY_FAILED) | `ENV SSL_CERT_FILE` + `SSL_CERT_DIR` re-declared in each derivative Dockerfile | python + nginx + postgres |
| 2. nonroot uid missing | Already added to baseline in FG-008; this story consumes it | python-scratch |
| 3. No USER / runs as root | `USER 65532:65532` + `WORKDIR /nonroot` | python-scratch |
| 4. No ENTRYPOINT | `ENTRYPOINT ["python3"]` + `CMD []` | python-scratch |
| 5. PYTHON* env absent | `ENV PYTHONDONTWRITEBYTECODE=1 PYTHONFAULTHANDLER=1` | python-scratch |

Claim 6 (`python3` symlink stability) was already correct — baseline ships `python3 → python3.13` + `python → python3`.

The HTTPS fix matters beyond python: nginx (proxy_pass SSL verification) and postgres (postgres_fdw remote TLS, extensions issuing HTTPS) also fail silently without `SSL_CERT_FILE`. All three derivatives get the env re-declaration.

Smoke-test evolution:
- `smoke_tls_handshake.sh` (lazy `ssl.create_default_context()` — slipped silent-SSL failures past us) → replaced by `smoke_tls_https_real.sh` (`urllib.request.urlopen('https://example.com')` returning 200)
- New `smoke_user_nonroot.sh` — `docker inspect`-level + runtime verification of USER = 65532:65532
- `smoke_entrypoint.sh` rewritten for the new ENTRYPOINT=python3 shape
- `smoke_imports.sh` / `smoke_ca_bundle.sh` / `smoke_pip_runtime_install.sh` use `--entrypoint=python3` explicit override — portable across any future entrypoint change

## Alternatives rejected

- **Publish a separate `:3.13-nonroot` tag** alongside `:3.13` with USER root — user's "follow defaults" answer explicitly rejected the two-tag approach. Making the whole image nonroot means one consumer migration (acknowledged) instead of a proliferating tag surface.
- **Fix only the SSL claim and defer hardening to a future story** — the other four claims are small changes; batching them reduces total churn.
- **Set SSL_CERT_FILE in the baseline's ENV** — baseline already does, but ENVs don't propagate through `COPY --from=scratch_base`. The real fix is in each derivative. Documented in `memory/scratch-closures.md`.
- **Move pip to the ENTRYPOINT** (`ENTRYPOINT ["python3", "-m", "pip"]`) — restricts the image to pip-only usage. python-general with ENTRYPOINT=python3 is more flexible.

## Breaking changes

- Consumers who ran `docker run python-scratch-trixie:3.13 pip install ...` must now use `docker run --entrypoint=pip python-scratch-trixie:3.13 install ...` or `docker run python-scratch-trixie:3.13 -m pip install ...`.
- Consumers who relied on being root inside the container must add `USER root` in their derived Dockerfile. `pip install --target /tmp/pkg` (what Beaconry uses) still works as nonroot because `/tmp` is 1777.
- `docker run python-scratch-trixie:3.13 python3 ...` becomes awkward (ENTRYPOINT already provides python3). Consumers migrate to `docker run <image> -c "..."` or `docker run <image> <script.py>`.

These are all documented in the FG-009 commit message and will be called out in release notes once we have them.

## Merge plan

Fast tier (`make check-strict`): lint, verify-sid-pins, verify-traceability, test-acceptance (incl. FG-009 + existing FG-001–008), test-images (now 34 scripts: python-scratch grows from 8 → 9 via the user_nonroot/tls_https_real swap; others unchanged).

## Rollout plan

Standard: merge to `dev`; operator triggers `release.yml` → `main`, then `build.yml` publishes. Each of the three scratch derivative GHCR packages picks up the new env on the first rebuild.

Post-publish, Beaconry's Dockerfile drops the `ENV SSL_CERT_FILE` workaround they had to add and starts USING the image's own defaults.

## Shipping evidence

| Item | Pointer | Status |
|------|---------|--------|
| Scenario: python-scratch HTTPS works | `images/python-scratch-trixie/tests/smoke_tls_https_real.sh` | ✅ |
| Scenario: python-scratch USER 65532 | `images/python-scratch-trixie/tests/smoke_user_nonroot.sh` | ✅ |
| Scenario: python-scratch ENTRYPOINT=python3 | `images/python-scratch-trixie/tests/smoke_entrypoint.sh` | ✅ |
| Scenario: python-scratch Env fields present | FG-009 acceptance test | ✅ |
| Scenario: every scratch derivative sets SSL_CERT_FILE | FG-009 acceptance (grep Dockerfiles) | ✅ |
| Scenario: scratch-closures.md documents the ENV trap | FG-009 acceptance (grep memory file) | ✅ |
| NEW CAP `image.ssl-cert-env` | all three derivative Dockerfiles + `docs/CAPABILITIES.md` | ✅ |
| NEW CAP `image.python-scratch-nonroot` | python-scratch-trixie Dockerfile + `docs/CAPABILITIES.md` | ✅ |
| Scenario: post-publish Beaconry adopts without workarounds | external verification | ⚠️ post-publish |

Local measurements:
- python-scratch size: ~45.3 MB (unchanged; only ENV + USER metadata adds)
- nginx + postgres sizes unchanged
- 34 smoke scripts across 5 images, 0 failures under `make check-strict`
- Beaconry's 3 reproducible claims (HTTPS, nonroot getpwuid, image Config) all verified fixed against the local build
