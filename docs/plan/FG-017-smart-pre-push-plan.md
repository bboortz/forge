# FG-017 — Plan: smart pre-push

**Story**: [`docs/stories/FG-017-smart-pre-push.md`](../stories/FG-017-smart-pre-push.md)
**Status**: in-progress
**Branch**: `feat/FG-017-smart-pre-push`

## Design delta

### New: `scripts/smart-check.sh`

```
#!/usr/bin/env bash
# Orchestrates the smart gate. Three outcomes:
#   (1) test-fast only                       — docs/doc-only diff
#   (2) full-run bailout → make check-strict — tooling/baseline/>4-images
#   (3) scoped run                           — else

# Determine BASE ref (same ladder as homelab):
#   GITHUB_BASE_REF (PR) → origin/dev → HEAD^

# Dispatch:
#   changed_paths=$(git diff --name-only $BASE..HEAD)
#   non_doc=$(echo "$changed_paths" | grep -vE '\.md$|^docs/' || true)
#   if $non_doc empty → test-fast only, exit
#   if $changed_paths matches FULL_RUN_PATHS → delegate to check-strict, exit
#
#   affected_images=$(python3 scripts/affected_images.py $BASE)
#   if |affected_images| > 4 → delegate to check-strict, exit
#
#   test-fast
#   for image in affected_images:
#     docker rmi forge-local/<image>:<tag> 2>/dev/null
#     bash scripts/build-image.sh <image>
#     bash scripts/test-images.sh <image>
#     accept=tests/acceptance/test_FG_*_<slug>.sh
#     [[ -f $accept ]] && _FORGE_IN_CHECK=1 bash $accept
#   python3 scripts/verify-contracts.py
```

### New: `scripts/affected_images.py`

Reuses `scripts/verify-contracts.py`'s PROMISES/EXPECTATIONS loader. Given a `$BASE..HEAD` diff:

1. **Direct**: images with any changed file under `images/<X>/*`.
2. **Transitive** (PROMISES delta cascade):
   - Load current + HEAD-side PROMISES for each image via `git show`.
   - If any promise was **removed** or **modified-same-id**, every dependent (per their EXPECTATIONS.yaml) is also affected.
   - Pure addition of a new promise: no fan-out required (semver-gated additive change).
3. Deduplicate + emit newline-separated image dir names to stdout.

Output format matches homelab's hash-collection style — plain lines, no JSON.

### New: FULL_RUN_PATHS regex

```
^scripts/
^Makefile$
^\.pre-commit-config\.yaml$
^\.github/workflows/
^images/scratch-base-trixie/
```

### Modified: `scripts/lint.sh` (new, or inline in Makefile)

Replace glob-based lint inputs with `git ls-files`-sourced sets:

```
hadolint $(git ls-files 'images/*/Dockerfile')
shellcheck $(git ls-files 'tests/acceptance/*.sh' 'images/*/tests/*.sh' 'scripts/*.sh')
yamllint -d <config> $(git ls-files '.github/*.ya?ml' 'images/*/*.yaml')
# Exec-bit check
for f in $(git ls-files '*.sh'); do
  [[ -x "$f" ]] || { echo "✗ $f missing exec bit" >&2; exit 1; }
done
```

Benefit: pre-push lint sees exactly what CI will see post-push (same git-tracked set).

### Modified: `Makefile`

```
.PHONY: check-smart check-smart-strict

check-smart:        ; @bash scripts/smart-check.sh
check-smart-strict: ; @_FORGE_FORCE_IMAGE_WIPE=affected bash scripts/smart-check.sh

check: ; @_FORGE_IN_CHECK=1 $(MAKE) test-fast test-acceptance test-images
```

(Add `_FORGE_IN_CHECK=1` export on the `check` target so Part B dedup kicks in.)

### Modified: `.pre-commit-config.yaml`

```yaml
- id: make-check-strict-pre-push     # existing name retained for history
  entry: bash -c 'make check-smart-strict'    # was: make check-strict
```

### Modified: every `tests/acceptance/test_FG_*.sh` that calls `scripts/test-images.sh`

Wrap the call:

```bash
if [[ "${_FORGE_IN_CHECK:-0}" != "1" ]]; then
  bash scripts/test-images.sh <image>
fi
```

Sections affected (from earlier grep):
- test_FG_003: 5 build-image calls (likely wraps all scratch derivatives; keep some for direct scenario validation)
- test_FG_005: 3 calls
- test_FG_008: 2 calls
- test_FG_006, test_FG_007, test_FG_004: 2 calls each
- test_FG_010, test_FG_011, test_FG_012, test_FG_013, test_FG_014, test_FG_015, test_FG_016, test_FG_009: 1 call each

Mechanical change; keep direct calls that are NOT delegating to test-images.sh (e.g., calls that build intentionally-mutated images for negative tests).

### New: `tests/acceptance/test_FG_017_smart-pre-push.sh`

Encodes every Gherkin scenario via git worktree + temp-commits that simulate each diff shape, then invokes `scripts/smart-check.sh --dry-run` and asserts the planned action matches.

`--dry-run` flag on smart-check.sh prints the dispatch decision + scope without executing — same as homelab's.

## Alternatives rejected

- **Hand-maintained path manifest like homelab's `lib/role-paths.sh`**: unnecessary since the FG-010 contracts graph already captures the image dependency structure authoritatively. Reusing it keeps one source of truth.
- **Scope lint too**: directly caused by the user's "homelab CI lint failures" pain point. Lint is cheap enough (~15 sec) that full-repo lint is the right default.
- **Skip the `>4` cap**: without the cap, a refactor touching many images runs each one serially — slower than full-check-strict with no coverage benefit.
- **Make `check-smart` the default `make check` target**: breaks the "sum of tests" semantics that acceptance tests rely on when invoked directly. Keep `make check` = full (for CI PR + nightly cron), add `make check-smart` as a new target.

## Breaking changes

- `.pre-commit-config.yaml` pre-push hook entry changes target from `check-strict` → `check-smart-strict`. Devs who bypass pre-commit (`--no-verify`) unaffected.
- Any acceptance test that depended on `_FORGE_IN_CHECK` NOT being set in the `make check` environment: there are none today.

## Merge plan

Single PR to `dev`. One logical commit for A+B+C (tightly coupled — smart-check's acceptance scenarios need the dedup env to pass).

## Rollout

- Pre-push hook: active immediately after merge; devs get fast pre-push on next push.
- Nightly cron: add a new `.github/workflows/nightly.yml` or extend existing — runs `make check-strict` on `dev` every night. Catches "smart gate was wrong" drift. **This is a prerequisite**: without the nightly, the safety net isn't in place.
- CI PR gate: unchanged (`make check`). Move to smart in a follow-up story if telemetry shows it's safe.

## Shipping evidence

| Item | Pointer | Status |
|------|---------|--------|
| Scenario: docs-only → test-fast only | FG-017 acceptance § section 1 | ⏳ |
| Scenario: 1 image → scoped run | FG-017 acceptance § section 2 | ⏳ |
| Scenario: scratch-base → full-run bailout | FG-017 acceptance § section 3 | ⏳ |
| Scenario: scripts/ → full-run bailout | FG-017 acceptance § section 3 | ⏳ |
| Scenario: >4 images → full-run bailout | FG-017 acceptance § section 3 | ⏳ |
| Scenario: PROMISES promise-removed cascades | FG-017 acceptance § section 4 | ⏳ |
| Scenario: unscoped-lint catches untouched file | FG-017 acceptance § section 5 | ⏳ |
| Scenario: exec-bit check | FG-017 acceptance § section 5 | ⏳ |
| Scenario: standalone acceptance keeps full behavior | FG-017 acceptance § section 6 | ⏳ |
| Scenario: in-check dedup | FG-017 acceptance § section 6 | ⏳ |
| `make check-strict` green on cold cache | local | ⏳ |
| Nightly cron workflow added | `.github/workflows/nightly.yml` | ⏳ |
| IDEAS.md records deferred Part D | `docs/plan/IDEAS.md` | ✅ |
