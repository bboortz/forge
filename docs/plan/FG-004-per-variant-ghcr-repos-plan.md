# FG-004 — Plan: one GHCR repo per variant + arch-explicit tag siblings + :latest

**Story**: [`docs/stories/FG-004-per-variant-ghcr-repos.md`](../stories/FG-004-per-variant-ghcr-repos.md)
**Status**: shipped (pending post-publish evidence)
**Branch**: `feat/FG-004-per-variant-ghcr-repos`

## Design delta

Variant identity moves from tag suffix to repo name:

| Before | After |
|---|---|
| `ghcr.io/bboortz/python:3.13-slim-trixie` | `ghcr.io/bboortz/python-slim-trixie:3.13` |
| `ghcr.io/bboortz/python:3.13-scratch-trixie` | `ghcr.io/bboortz/python-scratch-trixie:3.13` |

Each variant publishes a **4-tag family per run**, all pointing at the same digest today:

- `:3.13` — primary version
- `:3.13-amd64` — arch-explicit sibling
- `:latest` — floating pointer for consumers who want "current stable"
- `:latest-amd64` — floating + arch-explicit

Four tags, one digest, one cosign signature, one SBOM attestation, one grype attestation. The signature and attestations are attached to the digest, so every tag inherits them.

`image.yaml` simplifies — drop `repo:`. Scripts derive it from the directory name (`basename $IMAGE_DIR`). Single source of truth; new image dirs enroll with zero metadata beyond `tag:` and `platforms:`.

## Alternatives rejected

- **Keep `repo:` explicit** — flexibility we don't currently use. YAGNI. If a future image needs a non-matching repo name, we add an explicit override then.
- **Grace period on the old `python` package** — adds matrix complexity (dual publish to old + new for N days). Forge has essentially no external consumers; hard cut is clean.
- **Skip `:latest`** — users and tooling (incl. Beaconry's scout) expect `:latest` to resolve. Publishing it is nearly free and matches universal container-registry convention. README explicitly documents the `:latest` → silent-roll behaviour so no one is surprised.
- **Arch suffix = `linux-amd64`** — chose `amd64` to match Docker's `TARGETARCH` value (what everyone else in the ecosystem uses — `python:3.13-amd64`, `nginx:stable-amd64`).
- **Fold with FG-005 arm64** — bundles two independent concerns; harder to review and revert. FG-005 lands much cleaner on top of a stable repo structure.

## Breaking changes

- Consumer pulls of `ghcr.io/bboortz/python:3.13-slim-trixie` or `:3.13-scratch-trixie` return the old digest until the `python` GHCR package is manually deleted; no new daily builds land there post-merge.
- Consumer `cosign verify` command now takes a different final `<image>` argument. Workflow `--certificate-identity` is unchanged.
- `make build IMAGE_DIR=python-slim-trixie` still resolves correctly (dir name unchanged). Makefile targets are backwards-compatible from the caller's perspective.

## Merge plan

Fast tier (local `make check`) — lint, verify-sid-pins (vacuous), verify-traceability, test-acceptance (FG-001/002/003/004), test-images. Pre-push `make check` gates the push. PR CI `Full check` runs the same.

The FG-004 acceptance test does the pure-source verifications (no `image.yaml` has `repo:`, scripts derive it, matrix JSON shape, memory file section exists, no stale refs in docs). The post-publish "4 tags resolve to one digest" scenario is skipped unless `PUBLISHED=1` — same gate shape as FG-001's section 6.

## Rollout plan

1. Merge to `dev` (Claude auto-merges on green CI).
2. Operator triggers `release.yml` → `main` fast-forwards.
3. Operator triggers `build.yml` (`workflow_dispatch`). Matrix runs — each variant pushes to its new repo, then tags + pushes `:3.13-amd64`, `:latest`, `:latest-amd64`.
4. **Flip GHCR package visibility to public — twice** (one per new package: `python-slim-trixie`, `python-scratch-trixie`). One-time manual action, same as FG-001's step.
5. Run `PUBLISHED=1 bash tests/acceptance/test_FG_004_per-variant-ghcr-repos.sh` locally against the new repos.
6. **Delete old `ghcr.io/bboortz/python` GHCR package** via UI (Settings → Packages → python → Delete this package). One-time, destroys the old tags that would otherwise serve stale digests forever.
7. Flip the three post-publish Shipping-evidence rows ✅. Story → shipped.

## Shipping evidence

| Item | Pointer | Status |
|------|---------|--------|
| Scenario: image.yaml drops `repo:` | `tests/acceptance/test_FG_004_per-variant-ghcr-repos.sh` (section 1) | ✅ |
| Scenario: scripts derive repo from dir name | `tests/acceptance/test_FG_004_per-variant-ghcr-repos.sh` (section 2) | ✅ |
| Scenario: matrix JSON `repo` = dir name | `tests/acceptance/test_FG_004_per-variant-ghcr-repos.sh` (section 3) | ✅ |
| Scenario: no stale `python:` refs in docs | `tests/acceptance/test_FG_004_per-variant-ghcr-repos.sh` (section 4) | ✅ |
| Scenario: design-decisions locks repo naming | `tests/acceptance/test_FG_004_per-variant-ghcr-repos.sh` (section 5) | ✅ |
| Scenario: both variants publish 4 tags → 1 digest (post-publish) | `tests/acceptance/test_FG_004_per-variant-ghcr-repos.sh` (section 6, PUBLISHED=1) | ⚠️ post-publish |
| Scenario: cosign verify primary tag per variant (post-publish) | same section 6 | ⚠️ post-publish |
| EXT `publish.ghcr-public-pull` | two new GHCR packages, both visibility-flipped | ⚠️ post-publish |
| EXT `verify.consumer-cmd` | README Quick Start + section 6 | ⚠️ post-publish |
| EXT `build.central-script` | scripts/*.sh derive repo from dir | ✅ |
| EXT `publish.matrix-auto-discovery` | discover-images.sh emits dir-name as repo | ✅ |
| README + docs updated | `README.md`, no stale refs | ✅ |
| design-decisions.md § Repo naming | `memory/design-decisions.md` | ✅ |
| Old `python` GHCR package deleted | manual, one-time | ⚠️ post-publish |

Local rows flip to ✅ on `make check` green. Post-publish rows flip after step 4–7 of rollout.
