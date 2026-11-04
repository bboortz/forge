# FG-010 — Plan: image-to-image contracts

**Story**: [`docs/stories/FG-010-image-contracts.md`](../stories/FG-010-image-contracts.md)
**Status**: shipped
**Branch**: `feat/FG-010-image-contracts`

## Design delta

Every image in `images/<name>/` gains:

- `PROMISES.yaml` — authoritative, machine-checkable list of what the image guarantees. Each entry has:
  - `id` (dot-namespaced, e.g. `files.tls-stack`)
  - `description` (human-readable)
  - `caps` (list of CAP ids from `docs/CAPABILITIES.md` — cross-checked)
  - `tests` (list of smoke-test file paths that prove the promise)
  - `inverse: true` (optional; for anti-promises like `no-shell`)
- `EXPECTATIONS.yaml` (derivatives only) — declares each baseline dependency:
  - `image` (the depended-on Forge image dir name)
  - `version` (semver constraint, e.g. `>=0.2`)
  - `expectations[]`
    - `promise` (id from the dependency's PROMISES.yaml)
    - `reason` (why this derivative needs it)
    - `preflight` (list of smoke tests that fail loudly if the baseline deviates)

Both files carry a top-level `spec_version: 1` + `image:` (must match directory name) + `version:` (must match `image.yaml` tag for PROMISES; semver string for the dependency's declared version).

### Shape summary (illustrative — not final content)

```yaml
# images/scratch-base-trixie/PROMISES.yaml
spec_version: 1
image: scratch-base-trixie
version: "0.2"
promises:
  - id: files.tls-stack
    description: libssl.so.3 + libcrypto.so.3 + /etc/ssl/certs/ca-certificates.crt (Debian trust store)
    caps: [build.scratch-baseline]
    tests:
      - images/scratch-base-trixie/tests/smoke_contents_required_files.sh
```

```yaml
# images/python-scratch-trixie/EXPECTATIONS.yaml
spec_version: 1
image: python-scratch-trixie
dependencies:
  - image: scratch-base-trixie
    version: ">=0.2"
    expectations:
      - promise: files.tls-stack
        reason: urllib / requests / pip verify TLS peers against baseline CA bundle (SSL_CERT_FILE env re-declared locally; ENV doesn't propagate through COPY --from=)
        preflight:
          - images/python-scratch-trixie/tests/smoke_tls_https_real.sh
```

### Tooling

- `scripts/verify-contracts.py` — pure stdlib Python. Reads every `images/*/PROMISES.yaml` + `images/*/EXPECTATIONS.yaml`, builds the DAG, lints every edge. Exits non-zero + prints structured diagnostics on any violation. Runtime target: <2s.
- `scripts/contracts-semver-check.py` — pre-commit hook. Diffs staged `PROMISES.yaml` vs `HEAD`; classifies change as `add` (minor), `remove` (major), or `modify` (requires explicit override). Enforces that `version:` bump matches the change class. Rejects "silently modified promise description with same id" without `--allow-modify` in commit message.
- `make verify-contracts` — delegates to the Python script. Added as a hard gate to `make check` (via `test-fast` or its own line).
- `.pre-commit-config.yaml` — new `contracts-semver` hook (fires on `images/*/PROMISES.yaml` changes) + `verify-contracts` hook (fires on any `images/*/PROMISES.yaml`, `images/*/EXPECTATIONS.yaml`, or smoke-test edit).

### YAML parsing strategy

Pure stdlib Python using `tomllib`/`yaml`-is-not-stdlib — so we add a minimal in-repo YAML parser? **No** — we use Python's `yaml` module which is universally installed via `python3-yaml` or `pyyaml`. Prerequisite documented in `make tools`. Keeps the verifier ~150 lines + readable.

Fallback for CI: if `yaml` isn't importable, the script prints a one-liner install instruction and exits 2 (distinct from validation failure exit 1).

## Alternatives rejected

- **Markdown-only PROMISES.md + EXPECTATIONS.md** — ambiguous to parse, no machine-enforced schema. We lose the semver gate entirely.
- **JSON Schema with jq** — equivalent power, worse human diff. YAML wins on commit-review ergonomics.
- **Auto-generate `docs/CAPABILITIES.md` from PROMISES union** — would create dual-source-of-truth risk and churn. Keep CAPABILITIES.md hand-maintained; just cross-check that every `caps:` reference from PROMISES resolves to a CAP that exists there. Less automation, less risk.
- **One contracts dir at repo root** — breaks the FG-002 invariant that `images/<name>/` is self-contained. Co-located files win.
- **Deferring the semver gate to a follow-up story** — the gate is the biggest value-add. Without it, PROMISES can silently rot. Must ship with the first cut.
- **Non-stdlib YAML (yq / tomli-w)** — new tool install surface. `python3 -c "import yaml"` keeps the dependency footprint at zero new binaries.

## Breaking changes

- None at the published-image level.
- Internal: `docs/baseline-contract.md` prose gains a header note pointing at `images/scratch-base-trixie/PROMISES.yaml` as authoritative; existing narrative sections remain but some bulleted lists (file enumeration) are replaced by *"see PROMISES.yaml"* pointers so we don't dual-maintain.

## Merge plan

Single PR to `dev`, two logical commits:

1. **Scaffold**: verify-contracts.py + contracts-semver-check.py + Makefile integration + pre-commit entries + **empty acceptance test** (every assertion red). Adds no YAML files. PR is in a broken state intentionally — nothing consumes contracts yet.
2. **Backfill + flip**: write all 5 PROMISES.yaml + 3 EXPECTATIONS.yaml + 4 new CAPs in CAPABILITIES.md + update baseline-contract.md references + acceptance test now green. `make check` passes.

Each commit is buildable in isolation; the first just doesn't do anything useful. The gate becomes blocking after the second.

## Rollout

- No published-digest change; CI gets stricter.
- Pre-commit gate on PROMISES.yaml semver is strict from merge — maintainers learn it the first time they touch a promise. Diagnostic text is self-explanatory.
- First-time setup: `make install-hooks` picks up the new hook automatically (existing invocation).

## Shipping evidence

| Item | Pointer | Status |
|------|---------|--------|
| Scenario: current graph consistent | `tests/acceptance/test_FG_010_image-contracts.sh` § section 1 | ✅ |
| Scenario: FG-009 replay (SSL env stripped) | Acceptance § section 2 | ✅ |
| Scenario: baseline surface shrinks | Acceptance § section 3 | ✅ |
| Scenario: nonexistent promise reference | Acceptance § section 4 | ✅ |
| Scenario: semver gate catches unbumped change | Acceptance § section 5 | ✅ |
| Scenario: removed promise needs dependent re-attestation | Acceptance § section 6 | ✅ |
| NEW CAP `contracts.promises` | 5 PROMISES.yaml files + CAPABILITIES.md | ✅ |
| NEW CAP `contracts.expectations` | 3 EXPECTATIONS.yaml files + CAPABILITIES.md | ✅ |
| NEW CAP `contracts.verify-gate` | Makefile + .pre-commit-config.yaml + CAPABILITIES.md | ✅ |
| NEW CAP `contracts.semver-enforcement` | contracts-semver-check.py + CAPABILITIES.md | ✅ |
| EXT `docs.baseline-contract` → references PROMISES.yaml | docs/baseline-contract.md top matter | ✅ |
| Verifier runtime | `time make verify-contracts` | ✅ <2s target |
| `make check-strict` green cold-cache | local | ✅ |

## Local measurements target

- `make verify-contracts` runtime: < 2 seconds (stdlib Python, no subprocess per file).
- Total new files: 5 PROMISES.yaml + 3 EXPECTATIONS.yaml + 2 scripts + 1 acceptance test = **11** (+ story + plan + CAPABILITIES edits).
- Diagnostic quality: every error names the (file, line/entry id, referenced thing). No "contract violated somewhere."
