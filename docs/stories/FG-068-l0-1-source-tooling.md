---
id: FG-068
slug: l0-1-source-tooling
status: in-progress
owner: bboortz
created: 2026-11-20
---

# FG-068 — L0.1 upstream-source tooling

Formalize L0.1 — the upstream source repositories and release tarballs that Forge builds clone/download at build time — as a first-class tier in the Forge model. Introduces `scripts/_upstream_sources.py` (the inventory), `scripts/verify-source-inventory.py` (two-way drift check), and an L0.1 subgraph in the dep-graph emitter. No image moves.

The original FG-068 scope ("move beaconry + healthy-scratch into `images/source/`") was retired when the user chose "L4 absorbs from-source runtimes; upstream source repos become L0.1" — see `docs/plan/tier-layering-model.md` §7 FG-068 revision note.

## 9 canonical answers

1. **Who** — Forge maintainer + any contributor wanting to add a new from-source image. The inventory becomes the single place that answers "what upstream source does the build actually fetch?" + enforces that every source has a declared consumer.

2. **When** — Fires at every `make test-fast` + every pre-commit. Also fires every time a Dockerfile adds a new `RUN git clone` or `image.yaml source.git:` — the verifier makes forgetting-to-register-the-source a lint failure.

3. **What success looks like**:
   - `scripts/_upstream_sources.py` exists with `_UPSTREAM_SOURCES` dict + `canonical_url()` helper.
   - `scripts/verify-source-inventory.py` exists and does the two-way sync check; wired into `make test-fast` via a new `verify-source-inventory` target.
   - Inventory starts with 10 entries covering every actual source reference in today's fleet.
   - `scripts/image_from_graph.py` emits an **L0.1 subgraph** with dashed edges to each source's declared consumers; dep graph regenerated in `docs/image-dependency-graph.{md,svg}`.
   - `docs/CAPABILITIES.md` registers `build.l0-1-source-inventory` + `arch.l4-absorbs-from-source` (both NEW).
   - `memory/docker-standard.md` notes the L0.1 inventory + enforcement.
   - `tests/acceptance/test_FG_068_l0-1-source-tooling.sh` asserts: inventory present + exits cleanly + synthetic drift detection + dep-graph L0.1 subgraph present + traceability.
   - `make test-fast` + `make check` green on dev.
   - **Zero image directory moves.** `images/` tree byte-identical to pre-FG-068.

4. **Urgency** — Prerequisite for FG-069 (base/ migration — the `base/python-trixie` consumers include beaconry, which uses L0.1 source). FG-068 lands the tooling + inventory that FG-069+ will reference.

5. **Happy path**:
   1. Branch `feat/FG-068-l0-1-source-tooling` from `dev` (which has FG-067 Rule 11 landed).
   2. Red acceptance test exercising each deliverable.
   3. Implementation — 10 files touched: inventory module, verifier, Makefile, dep-graph emitter, docs/CAPABILITIES.md, memory/docker-standard.md, 2 regenerated dep-graph artifacts, plan, test.
   4. `make test-fast` green → PR → CI → auto-merge.

6. **Edge cases / failure modes**:
   - **Multi-line `RUN git clone` continuations**: the verifier reads whole-file content (not line-by-line) so backslash-continued clone invocations are caught.
   - **Non-source github URLs** (hadolint release install, cosign CLI install, forge self-reference in OCI labels): explicit `_SKIP` set in the verifier. Documented top-of-file.
   - **Release-tarball-download vs clone**: `github.com/actions/runner/releases/download/` normalizes to `github.com/actions/runner`. `verify-source-inventory.py`'s canonicalization handles both forms.
   - **ziglang.org tarball versioning**: inventory key is `ziglang.org/download` (the host + base path). The version is in the Dockerfile ARG; inventory tracks the host/path only.
   - **Dep-graph degradation**: if `_upstream_sources.py` is missing (should never happen in-repo, but safety), `image_from_graph.py` falls back to empty inventory + skips the L0.1 subgraph. No crash.

7. **Out of scope**:
   - Any image directory move — those land in FG-069+.
   - Changing how any image fetches its upstream (pinning strategy stays as-is; FG-068 only catalogs).
   - A CI `publish-source` tier (retired per tier-plan §O9).
   - A `source/` directory tree under `images/` (retired per tier-plan §O8).
   - CVE scanning of L0.1 sources at Forge-side — the derived L4 image's SBOM covers it; FG-068 just inventories.

8. **How we know it's done** — see Gherkin below.

9. **Capabilities delivered or extended**:
   - NEW `build.l0-1-source-inventory` — centralized inventory + bidirectional drift check for every upstream source referenced by Forge builds.
   - NEW `arch.l4-absorbs-from-source` — architectural invariant: L4 absorbs from-source + externally-sourced consumer-facing runtimes; the construction mechanism is a build-time detail, not a tier.

## Gherkin acceptance

```
Scenario: inventory module exists + exports the expected shape
  Given current HEAD
  Then scripts/_upstream_sources.py exists
  And `python3 -c "from scripts._upstream_sources import _UPSTREAM_SOURCES; print(len(_UPSTREAM_SOURCES))"`
      prints an integer ≥ 10
  And the dict's values are lists of consumer image-dir names

Scenario: verify-source-inventory runs clean on current HEAD
  Given current HEAD
  When `python3 scripts/verify-source-inventory.py` runs
  Then it exits 0
  And stdout contains "verify-source-inventory: ok"

Scenario: verifier catches synthetic drift (missing inventory entry)
  Given a tmp copy of images/ with an added Dockerfile that `RUN git clone`s
      a URL NOT in _UPSTREAM_SOURCES
  When the verifier runs against that tmp root
  Then it exits 1
  And stderr mentions "not in inventory"

Scenario: verifier catches synthetic drift (undeclared consumer)
  Given an existing inventory entry like github.com/google/cadvisor
      referenced by a Dockerfile under an image name NOT in that entry's
      consumer list
  When the verifier runs
  Then it exits 1
  And stderr mentions "consumer drift"

Scenario: dep graph emits L0.1 subgraph with edges
  Given regenerated docs/image-dependency-graph.md
  Then the mermaid block contains `subgraph L0_1_sources`
  And it contains at least one `SRC_GH_BBOORTZ_BEACONRY -.->` dashed edge
  And it contains at least one `SRC_ZIGLANG_ORG_DOWNLOAD -.->` dashed edge
  And the L0.1 subgraph lists ≥ 10 source nodes

Scenario: Makefile wires the new verifier into test-fast
  Given current HEAD
  Then Makefile contains a `verify-source-inventory:` target
  And the `test-fast:` target depends on `verify-source-inventory`

Scenario: capabilities + memory documented
  Given current HEAD
  Then docs/CAPABILITIES.md contains "### build.l0-1-source-inventory"
  And it contains "### arch.l4-absorbs-from-source"
  And memory/docker-standard.md contains "L0.1 inventory"

Scenario: no image directory moved
  Given the diff between dev and this PR
  Then no file under images/ is created, deleted, or renamed
```

## References

- Plan: `docs/plan/FG-068-l0-1-source-tooling-plan.md`
- Red test: `tests/acceptance/test_FG_068_l0-1-source-tooling.sh`
- Tier model: `docs/plan/tier-layering-model.md` §3 L0.1 + §7 FG-068 revision note
- Downstream: FG-069 (base/) references the same inventory; FG-070 (pre-builder/) too; FG-071 (builder/) too.
