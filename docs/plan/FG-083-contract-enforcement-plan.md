# FG-083 — Plan: contract enforcement (no orphan smokes, CAP-has-promise, promise-add bumps version)

**Story**: [`docs/stories/FG-083-contract-enforcement.md`](../stories/FG-083-contract-enforcement.md)
**Status**: ready → shipped
**Branch**: `feat/FG-083-contract-enforcement`

## Design delta

Three new mechanical gates. Zero image behaviour changes.

### (a) `scripts/verify-no-orphan-smokes.py`

- Walk `images/*/tests/smoke_*.sh` + `images/*/*/tests/smoke_*.sh`.
- Walk all `PROMISES.yaml` under `images/`, collect every path in `tests:`.
- `orphans = all_smokes − referenced − _ALLOWLIST`
- Exit 1 on non-empty `orphans`, printing each.
- `_ORPHAN_SMOKES_ALLOWLIST: set[str]` starts empty.

### (b) Extend `scripts/verify-traceability.sh` with Rule 4

- Collect known CAPs from `docs/CAPABILITIES.md` (already done at top).
- Collect every CAP id mentioned in any `caps: [...]` entry in any `PROMISES.yaml`.
- Compute `uncovered = known − promised − _CAPS_WITHOUT_PROMISES_ALLOWLIST`.
- Fail on non-empty uncovered.

Meta-CAP allowlist content (empirically from the current tree):
- `build.two-stage-scratch` — build-shape invariant, not image-level
- `test.smoke-server-helper` — pattern CAP, not promised per-image
- `test.size-budget` — generic size-budget pattern
- `test.sidecar-init` — pattern CAP for sidecar-initdb flows
- `test.scratch-contents` — pattern CAP for contents-only validation
- plus any post-audit additions.

Will audit at implement-time and seed allowlist from current green state.

### (c) `scripts/verify-promises-version-bump.sh`

- Resolve base: `${GIT_DIFF_BASE:-origin/dev}`; if that fails, try `$GITHUB_BASE_REF`; if that fails, skip with `⚠ skipped (no base)` + exit 0.
- `git diff --name-only ${BASE}..HEAD -- '**/PROMISES.yaml'`
- For each changed PROMISES.yaml:
  - Count `^  - id:` lines at HEAD + at BASE
  - If counts differ → check the `^version:` line differs too
  - If version unchanged → fail with specific path + current/expected shape
- Shellcheck-clean.

## Alternatives rejected

- **Three single-purpose scripts** vs. **one mega-script** — one would conflate concerns + mask which invariant fired. Three scripts, named for their job. Cheap to run in sequence.
- **Pre-commit on `-W unreferenced smokes`** vs. **test-fast** — pre-commit would only see staged changes, miss drift from main. `test-fast` walks the full tree + is already run pre-push.
- **Promise `- id:` set hash instead of count** — count-based is simpler; the actual failure mode we're guarding is "add/remove without bump" not "swap names". Count suffices. Future FG can tighten if desired.
- **CAP-has-promise as a NEW standalone script** vs. extending `verify-traceability` — the existing script already owns CAP⇆test traceability; adding CAP⇆PROMISES there keeps the invariant family in one place.

## Breaking changes

None — introduces NEW gates. Current tree is clean under all three (pre-ship audit will verify).

## Merge plan

Full `memory/workflow.md § Blocking gates`. `make test-fast` + PR CI. No image rebuilds.

## Rollout plan

1. PR → dev (auto-merge on green CI)
2. `release.yml` → main
3. Daily cron picks up re-sign tomorrow (no image bits changed; not critical to re-publish immediately).

## Tooling updates (concrete list)

| File | Change |
|---|---|
| `scripts/verify-no-orphan-smokes.py` | NEW — 3-pass Python script |
| `scripts/verify-traceability.sh` | ADD Rule 4: CAP-has-promise; seed meta-CAP allowlist |
| `scripts/verify-promises-version-bump.sh` | NEW — git-diff-aware shell script |
| `Makefile` | `test-fast` gains 3 new lines (one per gate); `lint` optionally includes verify-no-orphan-smokes under a non-slow target |

## Shipping evidence

| Item | Pointer | Status |
|------|---------|--------|
| Current tree exits 0 under all 3 gates | test §1 | ✅ pre-ship |
| Artificial orphan smoke fails (a) | test §2 | ✅ |
| Artificial orphan CAP fails (b) | test §3 | ✅ |
| Artificial promise-add without bump fails (c) | test §4 | ✅ |
| NEW CAP `arch.verify-no-orphan-smokes` | CAPABILITIES + PROMISES | ✅ |
| NEW CAP `arch.verify-cap-has-promise` | CAPABILITIES + PROMISES | ✅ |
| NEW CAP `arch.verify-promises-version-bump` | CAPABILITIES + PROMISES | ✅ |
