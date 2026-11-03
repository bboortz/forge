---
id: FG-004
slug: per-variant-ghcr-repos
status: shipped
owner: bboortz
created: 2026-11-03
---

# FG-004 — one GHCR repo per variant + arch-explicit tag siblings + :latest

Pure publish-identity restructure, no new features. Moves variant identity from the tag suffix into the repo name — `ghcr.io/bboortz/python-slim-trixie:3.13` instead of `ghcr.io/bboortz/python:3.13-slim-trixie`. Dir name becomes the single source of truth; `image.yaml`'s `repo:` field is dropped entirely. Both variants grow a 4-tag family per publish (`:latest`, `:latest-amd64`, `:3.13`, `:3.13-amd64`) all pointing at the same digest today; when arm64 lands (FG-005) `:3.13-arm64` joins and `:3.13` + `:latest` become manifest lists transparently.

Hard-cuts the old `ghcr.io/bboortz/python` package — Forge is pre-public, no dual-publish grace period.

## 9 canonical answers

1. **Who** — consumer pulling Forge images; auditor who wants per-variant pull analytics / independent GHCR visibility; Forge maintainer adding a new image dir (who gets zero-config repo derivation from here on).
2. **When** — fires exactly once, on the FG-004 PR merge + first matrix publish. After that, the convention is just "how Forge publishes."
3. **What success looks like** —
   - `docker pull ghcr.io/bboortz/python-slim-trixie:3.13` and `:3.13-amd64` and `:latest` and `:latest-amd64` all succeed anonymously and resolve to the same digest
   - Same four tags under `python-scratch-trixie`
   - `cosign verify` succeeds against the primary tag (`:3.13`) for each variant
   - `images/*/image.yaml` no longer carries `repo:`
   - `scripts/discover-images.sh` emits `.include[].repo == <dir-name>` for every entry
   - `memory/design-decisions.md` has a `## Repo naming` section locking the convention
   - Old `ghcr.io/bboortz/python` package is deleted (manual, one-time, flagged in rollout)
4. **Urgency** — foundation for FG-005 (arm64). Arm64 is dramatically cleaner on per-variant repos: `:3.13` becomes a manifest list, `:3.13-amd64` and `:3.13-arm64` remain direct arch digests.
5. **Happy path** —
   1. Drop `repo:` from both image.yamls; version only — `tag: "3.13"`.
   2. `scripts/_image_yaml.sh` gains `image_yaml_repo()` that reads `repo:` if present, else returns `basename` of the image dir.
   3. `scripts/{build-image,test-images,discover-images}.sh` use it; derivation is invisible to callers.
   4. `Makefile` already delegates — no changes needed to targets, help text refreshed.
   5. `.github/workflows/build.yml` push step tags+pushes 4 tags per variant per run (primary push to `:3.13`, then `docker tag` → `:3.13-amd64`, `:latest`, `:latest-amd64` → `docker push` each). Cosign signs the digest once; attestations attach once.
   6. `README.md` Images table + Quick Start + verify command updated for the new repo + tag shape.
   7. `tests/acceptance/test_FG_001_python-slim-pipeline.sh` updated for the new repo path in the `PUBLISHED=1` section.
   8. `memory/design-decisions.md` § `Repo naming` added.
6. **Edge cases / failure modes** —
   - First publish to new repo is private by default; need to flip visibility to public *twice* (once per new package). Same one-time step as FG-001, now × 2.
   - Someone pulling the old `ghcr.io/bboortz/python:3.13-slim-trixie` tag gets a stale digest until the old package is deleted — expected, documented.
   - `docker tag` + 4 pushes multiplies publish time slightly; cosign signs the digest once (shared) so sig overhead is unchanged.
   - `:latest` moves with every publish — consumers who pin `:latest` get surprise rolls. This is universally expected behaviour for `:latest`; README calls it out.
   - Arm64 transition risk: when `:3.13` flips to a manifest list in FG-005, consumers pulling `:3.13-amd64` are unaffected (that tag stays a direct amd64 digest). The manifest-list transition is transparent for `:3.13` consumers.
7. **Out of scope** — arm64 build (FG-005); sid pins; retiring the slim variant; date-tagged aliases (`:3.13-2026-11-03`) — deferred until there's a reproducibility ask.
8. **How we know it's done** — see Gherkin below.
9. **Capabilities** — no new CAPs. Extensions:
   - EXT `publish.ghcr-public-pull` — now per variant; two packages to visibility-flip
   - EXT `verify.consumer-cmd` — repo paths updated in docs + acceptance test
   - EXT `build.central-script` — derives repo from dir name when `image.yaml` omits it
   - EXT `publish.matrix-auto-discovery` — matrix entry's `repo` is the dir name

## Gherkin

```
Scenario: image.yaml no longer carries repo
  Given images/python-slim-trixie/image.yaml and images/python-scratch-trixie/image.yaml
  Then neither contains a `repo:` line

Scenario: scripts derive repo from dir name
  Given no `repo:` in image.yaml
  When scripts/build-image.sh python-slim-trixie runs
  Then docker builds forge-local/python-slim-trixie:3.13

Scenario: matrix JSON reflects derived repo
  Given scripts/discover-images.sh
  When it runs
  Then jq '.include[] | .repo' emits dir names verbatim

Scenario: both variants publish 4 tags each to their own GHCR package (post-publish)
  Given build.yml ran post-merge
  Then ghcr.io/bboortz/python-slim-trixie has tags :3.13, :3.13-amd64, :latest, :latest-amd64
   And ghcr.io/bboortz/python-scratch-trixie has the same tag set
   And each all-four-tags set resolves to a single digest
   And all tags pull anonymously

Scenario: cosign verify works against each primary tag (post-publish)
  When cosign verify --certificate-identity ...build.yml@refs/heads/main ghcr.io/bboortz/python-slim-trixie:3.13 runs
  Then exit 0
  When cosign verify ... ghcr.io/bboortz/python-scratch-trixie:3.13 runs
  Then exit 0

Scenario: no stale python: repo references in docs
  Given HEAD of main
  When grep -R 'ghcr.io/bboortz/python:' docs/ README.md
  Then nothing matches

Scenario: design-decisions locks the convention
  Given memory/design-decisions.md
  Then it contains a "## Repo naming" (or similar) section
   And that section states one GHCR repo per variant + arch-explicit tag siblings + :latest is published
```

## References

- Plan: [`docs/plan/FG-004-per-variant-ghcr-repos-plan.md`](../plan/FG-004-per-variant-ghcr-repos-plan.md)
- Red test: [`tests/acceptance/test_FG_004_per-variant-ghcr-repos.sh`](../../tests/acceptance/test_FG_004_per-variant-ghcr-repos.sh)
- Capabilities: see [`docs/CAPABILITIES.md`](../CAPABILITIES.md)
