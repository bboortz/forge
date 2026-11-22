# FG-088 — Plan: adopt shepherd dev-cycle contract

**Story**: [`docs/stories/FG-088-sh019-contract-adoption.md`](../stories/FG-088-sh019-contract-adoption.md) — mirrors the shepherd-side [SH-019 (fleet contract rollout)](https://github.com/bboortz/shepherd/blob/main/docs/stories/SH-019-fleet-contract-rollout.md) under the [SH-014 umbrella](https://github.com/bboortz/shepherd/pull/23)
**Status**: ready
**Branch**: `feat/SH-019-contract-adoption`

## Design delta

Forge gets the shepherd dev-cycle contract — eight canonical `make` targets. Anchors on forge's native idioms (the dev-cycle doc flagged forge as having "an early start for a mechanism like this" — `scripts/affected_images.py` + `scripts/smart-check.sh`). 

The dev-cycle doc's explicit forge prescription was: "Forge add `make test` (alias of `test-fast`)". Done here. The affected-only mechanism (`smart-check.sh`) is wired into `test-affected`. The ci-* tier bodies call `lint test-affected` / `smoke` / `check-strict` without touching any existing recipe.

Changes to the root `Makefile` (33 lines appended under a new `##@ Shepherd dev-cycle contract (SH-014 / SH-019)` section):

- `test: test-fast` — new. Dev-cycle-doc prescription; was missing.
- `test-affected: ; bash scripts/smart-check.sh` — the affected-only scoped run (FG-017).
- `smoke: test-fast` — fast lint + verify-* without image builds.
- `release-artifacts: build` — forge's build target builds images; promote-by-digest arrives with SH-022.
- `ci-branch: lint test-affected` — 5-min PR gate.
- `ci-patch: smoke` — post-merge smoke (fast; no rebuild).
- `ci-release` — prints a note (forge publishes via nightly `build.yml`; SH-022 will add promote-by-digest).
- `ci-nightly: ci-nightly-body` → `check-strict` — nightly: full 83-test matrix from cold.

## Alternatives rejected

- **Alias `test-affected` to `check-smart` or `check-smart-strict`** — those wrap `smart-check.sh` with docker-wipe behaviour. Keep `test-affected` as a direct `smart-check.sh` call to match the contract's "fast, clean" semantic.
- **Promote-by-digest in this PR** — belongs in SH-022 (forge-specific speedup). This PR is minimum-contract-shape only.
- **Rename `test-fast` → `test-affected`** — breaks pre-push hook, docs, CI references. Aliases keep both names.

## Breaking changes

None. All new targets are additive. Existing `test-fast`, `check`, `check-strict`, `check-smart`, `build`, `lint` keep working.

## Merge plan

- `make lint` on changed Makefile.
- No test-code change; no CI config change.
- Pre-push: `check-smart` runs; passes because `smart-check.sh` is a docs-only diff for this change.

## Rollout plan

Merge to `dev` → fast-forward to `main` (CI gate). No image rebuild required.

Next PRs on this track:
- **SH-022** (shepherd): extend `ci-release` with `docker buildx imagetools create` promote-by-digest from `sha-<commit>` to version tag.
- **SH-017** (shepherd): `shepherd-bump --verify-contract` passes on forge after this.

## Shipping evidence

| Item | Pointer | Status |
|------|---------|--------|
| `make -n test` resolves | `test-fast` body | ✅ |
| `make -n test-affected` resolves | `bash scripts/smart-check.sh` | ✅ |
| `make -n smoke` resolves | `test-fast` body | ✅ |
| `make -n release-artifacts` resolves | `build` body | ✅ |
| `make -n ci-branch` resolves | `lint` + `smart-check.sh` | ✅ |
| `make -n ci-patch` resolves | `test-fast` | ✅ |
| `make -n ci-release` resolves | echo note | ✅ |
| `make -n ci-nightly` resolves | `check-strict` | ✅ |
| Existing `test-fast` / `check` / `check-strict` behaviour unchanged | manual inspection | ✅ |
| Contract spec stable | https://github.com/bboortz/shepherd/blob/main/docs/specs/dev-cycle-contract.md | ✅ |
