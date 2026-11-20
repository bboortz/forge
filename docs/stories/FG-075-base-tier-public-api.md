---
id: FG-075
slug: base-tier-public-api
status: ready
owner: bboortz
created: 2026-11-21
---

# FG-075 — base/ becomes Forge's public API (slim + scratch sub-shapes)

Reshape `base/*` from "scratch-overlay runtime foundation with ≥1 forge-internal consumer" into "Forge-signed consumer-facing runtime foundation, shape-agnostic." The rework establishes a clean public/internal boundary: external consumers (homelab bots, Beaconry, future adopters) FROM `base/*` or flat L4 images; `pre-builder/*`, `builder/*`, `mirror/*` become explicitly Forge-internal and reserved for build-time machinery.

Ships three concrete moves atomically:
1. Reworked Rule 12 in `verify-dockerfile-conformance.py` (drops the FROM-scratch + ≥1-forge-consumer requirements; adds a "consumer-facing foundation" positive requirement validated by presence of `image.yaml` + `PROMISES.yaml` + CI publishing).
2. Rename `base/python-trixie` → `base/python-scratch-trixie` for naming symmetry with the new slim sibling + update the 3 beaconry consumers' `depends_on:`.
3. New `base/python-slim-trixie` — slim consumer-facing foundation with apt + pip + CA + dumb-init + `/hc` + nonroot uid baseline + clean `python3` entrypoint. Serves dual duty: final runtime for slim Python apps AND builder stage for consumers who want a scratch runtime via `base/python-scratch-trixie` overlay.

Explicitly out-of-scope (follow-up FGs):
- Homelab bot migration (FG-074 revision — 7 bots flip FROM to `base/*`).
- Beaconry upstream migration (separate PR in `bboortz/beaconry`).
- node + go base/ siblings.

## 9 canonical answers

1. **Who** — Forge maintainers (shape the new public API); homelab operators + Beaconry maintainers (consumer migration unblocked).
2. **When** — Fires when an external consumer needs a Python foundation. Today homelab reaches into `pre-builder/python-slim-trixie` (coupling to internal machinery); Beaconry FROMs pre-FG-069/FG-071 flat paths (stale frozen digests). This story gives both a clean target.
3. **What success looks like** —
   - `images/base/python-slim-trixie/` + `images/base/python-scratch-trixie/` exist; the old `images/base/python-trixie/` is gone.
   - Each `image.yaml` carries explicit `repo:`; PROMISES `image:` field uses the leaf name (`python-slim-trixie` / `python-scratch-trixie`).
   - 3 beaconry `image.yaml` files point `depends_on:` at `base/python-scratch-trixie`.
   - Rule 12 reworked: no longer requires FROM scratch; no longer requires ≥1 forge-internal consumer. Documents the new public-API role.
   - `docs/LAYERING.md` names the public/internal boundary explicitly.
   - `verify-no-upstream-drift _EXPECTED=6` unchanged.
   - Dep graph regen'd; CAPABILITIES extended.
4. **Urgency** — Quality-of-life for the design + concrete fix for staleness. Moderate: no CVE pressure, but homelab + beaconry are paying for the gap daily (frozen digests).
5. **Happy path** —
   1. `git mv images/base/python-trixie images/base/python-scratch-trixie`
   2. Update rename target's `image.yaml` + `PROMISES.yaml` + `EXPECTATIONS.yaml` (new `repo:` + `image:` field; smoke script paths)
   3. Update 3 beaconry `image.yaml depends_on:` to `base/python-scratch-trixie`
   4. Create `images/base/python-slim-trixie/` — Dockerfile FROM `pre-builder/python-slim-trixie` + apt `python3-pip` + COPY `/hc` + USER 65532 + ENTRYPOINT `python3`
   5. Rework Rule 12 in `verify-dockerfile-conformance.py`
   6. Add to `_BASELINE` in `discover-images.sh` + conformance script + dep-graph emitter
   7. CAPs + dep graph + docs
6. **Edge cases / failure modes** —
   - Chain depth: `base/python-slim-trixie` sits at hop 4 (`debian:trixie-slim` → `python:3.14-slim-trixie` → `pre-builder/python-slim-trixie` → `base/python-slim-trixie`); consumer runtime hits 5 — still at the FG-042 cap.
   - `_BASELINE` set in 3 scripts must stay in sync (same pattern as FG-069's base/scratch-trixie addition).
   - Rule 12 drop risks silent re-introduction of zero-consumer scratch bases; mitigated by "L3 image must have image.yaml + PROMISES + daily-cron matrix entry" existence check (what Rule 1 already enforces).
7. **Out of scope** — No node/go base/ siblings. No homelab bot updates. No beaconry upstream updates. No `base/python-slim-trixie` extras beyond the named conveniences (/hc, nonroot, python3 entrypoint).
8. **How we know it's done** — Red test green + `make test-fast` green + 2 new base/* tags live on GHCR after main-cron.
9. **Capabilities delivered or extended** —
   - NEW `arch.base-tier-public-api` — `base/*` is Forge's consumer-facing FROM surface; `pre-builder/*`, `builder/*`, `mirror/*` are forge-internal only.
   - EXT `arch.base-tier-images` — shape-agnostic post-Rule-12-rework (slim and scratch both allowed).
   - NEW `image.python-slim-foundation` — `base/python-slim-trixie` is published, apt-upgraded, carries `/hc` + nonroot baseline + python3 entrypoint; suitable for both runtime and builder-stage consumption.

## Gherkin acceptance

```
Scenario: rename lands cleanly
  Given FG-075 has shipped
  When I ls images/base/
  Then I see python-slim-trixie and python-scratch-trixie
   And images/base/python-trixie/ does NOT exist

Scenario: new slim foundation builds + smokes pass
  Given FG-075 has shipped
  When I run bash scripts/build-image.sh base/python-slim-trixie
  Then forge-local/base/python-slim-trixie:0.1 exists in the docker daemon
   And every smoke script under images/base/python-slim-trixie/tests/ exits 0

Scenario: Rule 12 reworked — slim L3 passes conformance
  Given FG-075 has shipped
  When I run python3 scripts/verify-dockerfile-conformance.py
  Then it exits 0
   And base/python-slim-trixie (not FROM scratch) does not trigger a Rule 12 violation

Scenario: beaconry consumers point at the rename
  Given FG-075 has shipped
  When I grep "base/python-trixie\|base/python-scratch-trixie" across images/beaconry-*/image.yaml
  Then only base/python-scratch-trixie appears; no bare base/python-trixie remains

Scenario: public API documented
  Given FG-075 has shipped
  When I read docs/LAYERING.md
  Then it carries a section naming base/* and flat L4 as public API
   And it names pre-builder/*, builder/*, mirror/* as forge-internal

Scenario: verify-no-upstream-drift unchanged
  Given FG-075 has shipped
  Then verify-no-upstream-drift.sh has _EXPECTED=6 and passes
```

## References

- Plan: `docs/plan/FG-075-base-tier-public-api-plan.md`
- Red test: `tests/acceptance/test_FG_075_base-tier-public-api.sh`
- Capabilities: `docs/CAPABILITIES.md`
- Layering: `docs/LAYERING.md` (reworked §3 L3 + new §public-vs-internal subsection)
