# FG-089 — Plan: adopt shepherd SH-029 branching convergence (default = dev)

**Story**: [`docs/stories/FG-089-sh029-branching-convergence.md`](../stories/FG-089-sh029-branching-convergence.md) — mirrors the shepherd-side [SH-029](https://github.com/bboortz/shepherd/blob/main/docs/stories/SH-029-fleet-branching-convergence.md)
**Status**: ready
**Branch**: `feat/SH-029-branching-convergence`

## Design delta

Forge already uses `dev` as its integration branch but GitHub's default branch is still `main`. SH-029 flips it. This PR adds:

- `ci-release-promote` target in Makefile (~15 lines). Asserts on `dev`; FF main to dev; tags from VERSION; pushes.
- `ci-release` body now depends on `ci-release-promote`; retains note that nightly `build.yml` continues to publish images (unchanged).
- `.github/workflows/ci-release.yml` (new, 33 lines). Byte-identical to shepherd's template. `ref: dev` checkout + `git config` user + `timeout-minutes: 15`.

No changes to: `test-fast` / `check` / `check-strict` / `check-smart` / `smart-check.sh` / `build-image.sh` / `build.yml` (nightly publish).

## Alternatives rejected

- **Replace nightly `build.yml` with ci-release.yml** — scope creep; `build.yml` handles multi-image publishing which the simple ci-release-promote doesn't. Co-exist for now; retire build.yml in a follow-up if desired.
- **Inline FF logic in ci-release.yml workflow** — bypasses the shared contract. Keep `ci-release-promote` as a Makefile target so other fleet repos mirror the shape.
- **Leave default=main** — contradicts the 2026-11-22 decision to converge all fleet repos on `default=dev`.

## Breaking changes

- `make ci-release` now MUTATES git state when run on `dev` (FF + tag + push). Previously printed a placeholder. Safe on non-dev branches (exit 1). Interactive use on dev would actually promote.

## Merge plan

- `make check-smart` (pre-push) runs the full suite — forge has no fast-path for Makefile-only changes.
- No `check-strict` regression — recipe unchanged.

## Rollout plan

Merge to `main` (current default). Then operator:

```sh
gh repo edit bboortz/forge --default-branch dev
# verify rulesets: dev requires CI + reviews; main FF-only
gh workflow run ci-release.yml -R bboortz/forge --ref dev   # smoke the FF-promote path
```

## Shipping evidence

| Item | Pointer | Status |
|------|---------|--------|
| `make -n ci-release` resolves to ci-release-promote | local dry-run | ✅ |
| `make -n ci-release-promote` exits 1 on feat branch | local run | ✅ |
| ci-release.yml `ref: dev` on checkout | file inspection | ✅ |
| Existing `check-strict` / `smart-check.sh` / `build.yml` byte-identical | git diff | ✅ |
| CAP `shepherd.branching-convergence` extension documented | `docs/specs/CAPABILITIES.md` extension in follow-up (shepherd umbrella CAP already tracks this per repo) | ⚠️ (deferred — shepherd's `dev-cycle.fleet.branching-convergence` already enumerates forge; no separate FG-side CAP) |
