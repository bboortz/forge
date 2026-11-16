---
id: FG-059
slug: smart-check-dep-graph
status: ready
owner: bboortz
created: 2026-11-16
---

# FG-059 — smart-check: Dockerfile FROM-graph fan-out + finer `scripts/` triage

Forge's `make check-smart-strict` already scopes well per FG-017 (direct dir change + EXPECTATIONS fan-out). Two gaps still cause avoidable full-runs and avoidable misses:

**Gap A — `scripts/` bailout is too coarse.** Any change under `scripts/` triggers `make check-strict` (every image rebuild). Script set includes image-specific helpers (`smoke-server.sh`, `stamp-image.sh`, `install-tool-from-docker.sh`) that only a subset of images invoke — but today they all cost the same full-run.

**Gap B — Dockerfile `FROM` graph isn't tracked for scope.** EXPECTATIONS is contract-based (semver-tracked PROMISES). If I bump `images/forge-builder-python-trixie/Dockerfile` without changing a promise, smart-check's affected set is `{forge-builder-python-trixie}` only. Every scratch image that `FROM`s this builder is NOT re-tested in the PR — breakage shows up at next daily cron. Homelab's PATHS mapping approach captures this via explicit lists; Forge can derive it automatically from the Dockerfiles themselves.

FG-059 ships both:

- **(A) Finer `scripts/` triage** — replace blanket `^scripts/` full-run with a per-file allowlist of "always-full" core scripts; everything else runs scoped-to-callers.
- **(B) Dockerfile FROM-graph fan-out** — a new `scripts/image_from_graph.py` parses every `images/*/Dockerfile` for `ARG *_REF=ghcr.io/bboortz/<image>:...` + bare `FROM ghcr.io/bboortz/<image>:...` lines. Builds a reverse-dep graph that `affected_images.py` consumes. Bumping `forge-builder-python-trixie` fans out to every scratch image that FROMs it.

## 9 canonical answers

1. **Who** — any dev working on a cross-cutting change (shared builder bump, `scripts/` tweak, scratch-base change). Current pain: full-run every time → PR CI takes 30-60 min even for a one-line Dockerfile edit in `forge-builder-python-trixie`.

2. **When** — fires on every PR to `dev` and every pre-push. `make check-smart-strict` reads the new graph + the finer scripts classification.

3. **What success looks like**:
   - **Gap A**: `scripts/<X>.sh` where `<X>` is NOT in the core allowlist → smart-check scopes to images that call `<X>` (if detectable) OR falls through to `test-fast + test-acceptance` for safety. `scripts/<X>.sh` where `<X>` IS core (`build-image.sh`, `affected_images.py`, `smart-check.sh`, `_image_yaml.sh`, `discover-images.sh`, `stamp-image.sh`, `scan-regression.py`, `verify-*.sh`, `install-tool-from-docker.sh`) → full-run (unchanged).
   - **Gap B**: `scripts/image_from_graph.py` enumerates every forge-local dependency edge from the Dockerfiles. `affected_images.py` uses it to fan out: if image X is affected, every image whose Dockerfile `FROM`s X is also affected (recursively, up to a capped depth).
   - `test_FG_059_smart-check-dep-graph.sh` encodes both scenarios: one asserting the finer `scripts/` behavior (dry-run dispatch), one asserting `affected_images.py --dry-run` reports the correct fan-out for a simulated `forge-builder-python-trixie` change.

4. **Urgency** — moderate. Every slow PR cycle is lost dev time. FG-017 already captured the big wins; FG-059 captures the remaining two edges.

5. **Happy path**:
   1. Branch `feat/FG-059-smart-check-dep-graph` from `dev`.
   2. New `scripts/image_from_graph.py` — parses Dockerfiles, emits JSON `{<image>: [<images that depend on it>]}`.
   3. Extend `scripts/affected_images.py` — read the FROM-graph; fan-out from each directly-affected image; cap recursion depth at 3 (matches memory/docker-standard.md's chain-depth invariant).
   4. Extend `scripts/smart-check.sh` — replace the `^scripts/` bailout with:
      - If changed script is in `_CORE_SCRIPTS` allowlist → full-run.
      - Else: pass through to the normal affected-images path (empty-AFFECTED → `test-fast + test-acceptance`; shouldn't bailout).
   5. Red acceptance test `test_FG_059_smart-check-dep-graph.sh` — 6 sections (graph output shape, forge-builder fan-out, scratch-base fan-out, core-script still triggers full-run, non-core-script skips full-run, affected_images.py full flow).
   6. `make check-smart-strict` green locally.
   7. PR to `dev` → CI full-check → auto-merge on green.

6. **Edge cases / failure modes**:
   - **Cycles in the FROM graph** — Dockerfile layers can't be cyclic (base must exist before dependent), but a bug in the parser could create one. Guard with cycle-detection; abort cleanly.
   - **Unresolvable refs** — a Dockerfile `ARG FORGE_BUILDER_REF=ghcr.io/bboortz/nonexistent:latest` would be a stale reference. Parser logs a warning, skips the edge.
   - **Multi-stage Dockerfiles** — graph uses the RUNTIME stage's `FROM` + the builder-stage ARG refs. Both count as dependencies.
   - **`scripts/` triage classifies wrong** — if `_CORE_SCRIPTS` is overly narrow, a core-affecting change silently scopes narrow. Conservative default: start with the known-core set; expand on evidence.
   - **New image dir added without re-running graph** — `affected_images.py` re-parses each run; no stale cache.
   - **FG-023 stamp invariance** — this FG doesn't change the stamp-rebuild path; stamps still invalidate correctly when `FROM` target's digest changes.

7. **Out of scope**:
   - **Explicit PATHS_* arrays per image** (homelab's exact mechanism) — derivation from Dockerfiles is cleaner; no second source of truth.
   - **Parallelizing the per-image loop in smart-check** — separate FG if we want it; today we rely on docker daemon's single-build serialization anyway.
   - **Stamp-based test caching** (homelab's `.make/test/<role>` idea) — Forge images' tests involve docker build, which has its own cache. Skipping tests entirely is a bigger invariant change (not in this FG).
   - **Updating GHA workflow caps** — `FG-038` timeouts already generous; no change needed.

8. **How do we know it's done** — see Gherkin below.

9. **Capabilities delivered or extended**:
   - EXT `tooling.smart-check` — scope now includes Dockerfile FROM-dependent fan-out; `scripts/` bailout is finer.
   - EXT `build.pr-ci` — PR CI reuses the same smart-check logic (FG-018); fan-out improvements propagate.
   - No new CAPs.

## Gherkin acceptance

```
Scenario: image_from_graph.py reports each image's reverse-dependency set
  Given current HEAD state
  When scripts/image_from_graph.py runs
  Then the JSON output includes forge-builder-python-trixie → every scratch image whose Dockerfile declares FORGE_BUILDER_REF=...forge-builder-python-trixie...
  And scratch-base-trixie → every image that declares SCRATCH_BASE_REF=...scratch-base-trixie...
  And python-slim-trixie → forge-builder-python-trixie (dogfood edge)
  And debian-slim-trixie → every image declaring DEBIAN_SLIM_REF=...debian-slim-trixie...

Scenario: affected_images.py fans out via FROM-graph
  Given a simulated diff that touches only images/forge-builder-python-trixie/Dockerfile
  When scripts/affected_images.py <BASE> runs with the FROM-graph enabled
  Then the output includes forge-builder-python-trixie
    AND every scratch image that FROMs it (python-scratch, nginx-scratch, postgres-scratch,
        redis-scratch, mosquitto-scratch, healthy-scratch)
  And the output does NOT include unrelated images (e.g. cadvisor-slim-trixie — FROMs forge-builder-go-trixie, not python)

Scenario: finer scripts/ triage — core script still triggers full-run
  Given a diff that modifies scripts/build-image.sh
  When smart-check.sh --dry-run runs
  Then dispatch is "full" with reason=tooling-core

Scenario: finer scripts/ triage — non-core script does not force full-run
  Given a diff that modifies scripts/smoke-server.sh (image-helper, not core)
  When smart-check.sh --dry-run runs
  Then dispatch is "scoped" or "non-image-diff" — NOT the forced "full"

Scenario: cycle protection
  Given a (hypothetical) Dockerfile that creates a cyclic FROM-graph edge
  When scripts/image_from_graph.py runs
  Then it exits nonzero with a clear error — does not loop

Scenario: unchanged behaviour on image-only changes (regression guard)
  Given a diff that only touches images/github-runner-noble/Dockerfile
  When smart-check.sh --dry-run runs
  Then dispatch is "scoped" with AFFECTED=[github-runner-noble] — no spurious fan-out
```
