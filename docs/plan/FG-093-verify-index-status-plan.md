# FG-093 — Plan: adopt shepherd SH-056 `verify-index-status`

**Story**: [`docs/stories/FG-093-verify-index-status.md`](../stories/FG-093-verify-index-status.md) — mirrors the shepherd-side [SH-056](https://github.com/bboortz/shepherd/blob/main/docs/stories/SH-056-verify-index-status.md)
**Status**: in-progress
**Branch**: `feat/FG-093-verify-index-status`

## Design delta

Forge gains a new fleet-canonical drift gate catching `docs/stories/INDEX.md` ↔ story frontmatter status mismatches. Shepherd's `scripts/verify-index-status.sh` is copied byte-identical (fleet convention — the script is the contract) and wired into `check-docs` as a fourth sibling delegate.

- `scripts/verify-index-status.sh` — byte-identical copy from shepherd (chmod +x).
- `.PHONY: … verify-index-status` — declared alongside the existing verify-* family.
- `verify-index-status:` target — one-line recipe shelling out to the script.
- `check-docs:` — gains `verify-index-status` as a fourth sibling prerequisite.
- `docs/stories/INDEX.md` — column order flipped to the fleet-canonical `ID | Status | Slug | One-liner` (shepherd shape) + 50+ status cells synced to frontmatter + 8 missing rows added (FG-056, FG-067, FG-068, FG-069, FG-074, FG-088, FG-089, FG-090). This drift sync is an unavoidable prerequisite — the script wouldn't pass otherwise and the whole point of landing it is to keep INDEX honest going forward.

Zero changes to the existing drift gates, step targets, workflows, or `.shepherd.yml`-equivalent. Pure addition + a one-shot INDEX sync.

## Alternatives rejected

- **Non-byte-identical script with forge-native status column** — deviates from fleet convention. Shepherd + the other fleet repos converge on one column order (`ID | Status | Slug | One-liner`); flipping forge is cheap and makes `shepherd-bump --verify-contract` future-work trivial. The invisible-to-humans column reorder costs nothing.
- **Add `verify-index-status` to `test-fast` directly** — `check-docs` already runs on pre-push + CI (FG-092); adding to `test-fast` would duplicate the delegate and break FG-092's "pure composition without doubling" shape.
- **Fix only some of the 50+ INDEX drift rows** — a half-synced INDEX ships the script in an immediately-failing state. Fleet onboarding stories always require a one-shot bring-to-zero pass.
- **Hold FG-093 until FG-092 lands** — FG-092 is `ready` on the same branch tree; wiring `verify-index-status` into its `check-docs:` line in-place is additive and keeps the shepherd-side SH-055 → SH-056 ordering intact without blocking either.

## Breaking changes

- [ ] Yes
- [x] No — strictly additive. `verify-index-status` is a new target; existing targets unchanged. `check-docs:` grows by one prerequisite. The INDEX column reorder is layout-only; row content stays. Downstream hooks + CI pick up the new delegate automatically.

## Rollout plan

Merge to `dev`. Forge contributors + agents can immediately use `make verify-index-status` or `make check-docs`. Pre-push hook picks up the extended `check-docs` delegate on next run; next PR triggers `ci-branch` with the same. No downstream notice needed.

## Shipping evidence

| Gherkin scenario | Test assertion | Status |
|---|---|---|
| Script is byte-identical to shepherd's | Section 1 | ✅ |
| `.PHONY` declares verify-index-status | Section 2 | ✅ |
| verify-index-status target exists + dry-run cleanly | Section 3 | ✅ |
| check-docs includes verify-index-status as a fourth sibling | Section 4 | ✅ |
| verify-index-status passes on the current tree | Section 5 | ✅ |
| CAP registered + bidirectional link | Section 6 + `verify-traceability` | ✅ |

Three lenses:

- **Gherkin coverage**: each scenario pinned to a test section. ✅
- **Behaviour symmetry**: shepherd ships the same shape (`verify-index-status` script + Makefile target + CAP); forge's test file mirrors shepherd's with forge-native expectations. The script itself is byte-identical across both. ✅
- **Self-consistency**: no workflow edits, no step renames, no §12-protected files touched. INDEX.md drift sync is caught + fixed in the same PR that introduces the gate — the tree lands green and stays green. ✅