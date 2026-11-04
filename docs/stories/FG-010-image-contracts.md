---
id: FG-010
slug: image-contracts
status: shipped
owner: bboortz
created: 2026-11-04
---

# FG-010 — Image-to-image contracts (PROMISES + EXPECTATIONS + verifier)

Every Forge image gains a declarative **contract** with the images that depend on it:

- `images/<name>/PROMISES.yaml` — what consumers can rely on, linked to the tests that enforce it.
- `images/<name>/EXPECTATIONS.yaml` — only on images that depend on another Forge image; names the baseline version + each surface the derivative relies on + a preflight test.
- `scripts/verify-contracts.py` — lints the full graph: every expectation resolves to a declared promise, every promise has ≥1 test, every preflight exists and is picked up by `make test-images`, every version constraint is satisfied by the dependency's declared version.
- `scripts/contracts-semver-check.py` — runs as a pre-commit hook; diffs `PROMISES.yaml` edits against `HEAD` and refuses to commit if the inferred bump (add / remove / modify) doesn't match the declared `version:` bump.

No manual maintenance beyond authoring the PROMISES/EXPECTATIONS themselves. Everything else (traceability, semver, test linkage, graph validity, CI gating) is automated.

Motivated by FG-009: the ENV-doesn't-propagate trap silently broke python-scratch TLS. If an EXPECTATIONS entry had said *"I expect baseline promise `files.tls-stack`, preflight = `smoke_tls_https_real.sh`"*, the problem would have surfaced on the first PR rather than in Beaconry's production.

## 9 canonical answers

1. **Who** — Forge maintainers (adding new images / bumping baseline); auditors (one static-checkable surface per image); future-us (zero-cost discovery of what each image guarantees).
2. **When** — on every PR, pre-push, and daily cron. New promise / changed promise / new dependency → semver pre-commit hook runs. Any smoke-test or Dockerfile change → verify-contracts cross-checks the graph.
3. **What success looks like** —
   - 5 PROMISES.yaml files (one per image), 3 EXPECTATIONS.yaml files (one per scratch derivative), all validated.
   - `make verify-contracts` passes on main. Hard gate in `make check`.
   - **Red replay**: strip `ENV SSL_CERT_FILE` from python-scratch Dockerfile → `make verify-contracts` + test-images fail with a diagnostic naming the broken expectation and the preflight that caught it.
   - **Red replay 2**: remove `/etc/localtime` from baseline → every derivative EXPECTATIONS that references `files.time` fires a specific error in `verify-contracts`.
   - **Semver**: touching a PROMISES.yaml without bumping `version:` fails the pre-commit hook with a diff of what changed.
   - Zero new hand-maintained indexes. CAPABILITIES.md stays the canonical CAP registry; PROMISES.yaml `caps:` entries are cross-checked against it.
4. **Urgency** — quality-of-life + regression-prevention tier. Not security-critical by itself. Prevents the next FG-009-class silent failure.
5. **Happy path** —
   1. Scaffold `scripts/verify-contracts.py` + `scripts/contracts-semver-check.py`. Red: no YAML files yet, every image's smoke-suite "covered-by promise" lookup errors.
   2. Write `images/scratch-base-trixie/PROMISES.yaml` — one promise per baseline surface (ld-linux, core-glibc, tls-stack, compression, dns, network-data, time, identities, writable-dirs) + inverse promises (no-shell, no-pkgmgr, no-libutil).
   3. Write `images/python-slim-trixie/PROMISES.yaml` — conventional python image contract (interp, pip, apt, shell).
   4. Write `images/<scratch-derivative>/PROMISES.yaml` for python-scratch, nginx-scratch, postgres-scratch — each lists what their own users get.
   5. Write `images/<scratch-derivative>/EXPECTATIONS.yaml` — declares `scratch-base-trixie@>=0.2` + one entry per baseline promise consumed with a preflight test pointer.
   6. Wire into Makefile: `make verify-contracts`, included in `check`.
   7. Wire pre-commit: semver check on PROMISES.yaml edits.
   8. Red-test FG-010: `tests/acceptance/test_FG_010_image-contracts.sh` encodes the Gherkin.
   9. CAPs: register `contracts.promises`, `contracts.expectations`, `contracts.verify-gate`, `contracts.semver-enforcement`. Wire them into docs/CAPABILITIES.md.
   10. Pass `make check-strict`.
6. **Edge cases / failure modes** —
   - Baseline bumps major (0.x → 1.x) → every derivative EXPECTATIONS must update constraint OR verify-contracts fails with named derivatives.
   - Promise removed but still referenced → specific per-expectation error with file:line.
   - Promise description mutated with same id → semver hook flags "modify" and requires either a new id or `--allow-modify` override (committed with the change so audit trail is explicit).
   - Preflight file doesn't exist / isn't executable → named in the error.
   - Expectation references a known promise but the preflight doesn't actually run (not under `images/*/tests/`) → flagged.
   - A test file disappears → every promise/expectation referencing it errors with the referencing file.
7. **Out of scope** —
   - Contracts against *upstream* bases (`python:3.13-slim-trixie`) — we don't own them; Debian ships release notes.
   - Runtime attestation (image boots and checks baseline contract). Static CI-time check is enough.
   - Auto-generation of CAPABILITIES.md — keeps dual-source-of-truth risk at bay.
   - Signing PROMISES.yaml cryptographically. The repository is the audit trail.
8. **How we know it's done** — see Gherkin + FG-010 acceptance test.
9. **Capabilities** —
   - NEW `contracts.promises` — every image declares its guarantees via `images/<name>/PROMISES.yaml`
   - NEW `contracts.expectations` — every scratch derivative declares its baseline dependency surface via `images/<name>/EXPECTATIONS.yaml`
   - NEW `contracts.verify-gate` — `make verify-contracts` is a blocking gate in `make check`
   - NEW `contracts.semver-enforcement` — PROMISES.yaml edits are auto-classified (add / modify / remove) and gated against the declared `version:` bump via a pre-commit hook
   - EXT `docs.baseline-contract` — `docs/baseline-contract.md` keeps its narrative shape but references `images/scratch-base-trixie/PROMISES.yaml` as the authoritative surface

## Gherkin acceptance

```
Scenario: current graph is consistent
  Given every images/*/PROMISES.yaml and images/*/EXPECTATIONS.yaml on main
  When `make verify-contracts` runs
  Then it exits 0 with no errors

Scenario: FG-009 regression replay
  Given python-scratch EXPECTATIONS lists promise files.tls-stack with preflight smoke_tls_https_real.sh
  When I remove ENV SSL_CERT_FILE from python-scratch Dockerfile
  Then `make test-images IMAGE_DIR=python-scratch-trixie` fails in smoke_tls_https_real.sh with CERTIFICATE_VERIFY_FAILED

Scenario: baseline surface shrinks
  Given python/nginx/postgres scratch derivatives all expect baseline promise files.time
  When I remove files.time from scratch-base-trixie's PROMISES.yaml
  Then `make verify-contracts` fails with 3 errors, one per derivative, naming the broken expectation

Scenario: promise id used in an expectation does not exist
  Given a derivative EXPECTATIONS entry references promise nonexistent.widget
  When `make verify-contracts` runs
  Then it fails with "image-X expects promise nonexistent.widget but scratch-base-trixie does not declare it"

Scenario: semver gate catches an unbumped change
  Given scratch-base-trixie PROMISES.yaml version 0.2 with promise identity.nonroot
  When I add a new promise files.new-widget without bumping version
  Then the pre-commit semver hook refuses the commit with "added 1 promise(s); bump version to at least 0.3"

Scenario: removed promise requires dependents to re-attest
  Given promise files.time is depended on by python/nginx/postgres scratch
  When I remove files.time from PROMISES.yaml and bump version 0.2 → 1.0
  Then the semver hook requires the same commit to either (a) update every dependent EXPECTATIONS to no longer reference files.time, OR (b) add --allow-breaking to the commit message
```

## References

- Plan: [`docs/plan/FG-010-image-contracts-plan.md`](../plan/FG-010-image-contracts-plan.md)
- Red test: [`tests/acceptance/test_FG_010_image-contracts.sh`](../../tests/acceptance/test_FG_010_image-contracts.sh)
- Verifier: `scripts/verify-contracts.py`
- Semver gate: `scripts/contracts-semver-check.py`
- Capabilities: [`docs/CAPABILITIES.md`](../CAPABILITIES.md)
