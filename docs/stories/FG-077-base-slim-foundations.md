---
id: FG-077
slug: base-slim-foundations
status: ready
owner: bboortz
created: 2026-11-21
---

# FG-077 — close the "L4 runtime FROMs pre-builder" gap (3 new base/*-slim foundations)

Extend the FG-075 `base/python-slim-trixie` pattern to every other L1 pre-builder family currently consumed as a runtime FROM by an L4 image. Adds 3 new L3 consumer-facing runtime foundations: `base/debian-slim-trixie`, `base/ubuntu-slim-noble`, `base/node-slim-trixie`. Flips 4 downstream Dockerfiles' final-stage FROM to the new base/* paths. After FG-077, zero L4 runtimes FROM `pre-builder/*` — the public/internal boundary (FG-075 §11) holds across the whole fleet.

Each new base/ follows the `base/python-slim-trixie` recipe verbatim: FROMs its L1 pre-builder sibling, adds `/hc` + USER 65532 + sensible entrypoint. Dual duty: final runtime for operator consumers AND builder stage for scratch overlays if a future need arises.

## 9 canonical answers

1. **Who** — Forge maintainers (close the public-API boundary gap); external consumers (homelab's Ubuntu-based bots, future adopters wanting a plain Debian or Node runtime).
2. **When** — Fires every time someone audits "do all L4 runtimes FROM a public-API tier?" Today the answer is "no, 4 do not" (per the FG-076 follow-up audit). After FG-077 the answer is "yes, all L4s FROM base/* or L4-approved exemption."
3. **What success looks like** —
   - 3 new image dirs at `images/base/{debian-slim-trixie,ubuntu-slim-noble,node-slim-trixie}/`.
   - Each with explicit `repo: base/<name>` in `image.yaml`, PROMISES.yaml with leaf `image:` name, EXPECTATIONS.yaml, scan-baseline.json, sid-pins/, 5-6 smoke scripts.
   - 4 consumer Dockerfiles updated: `github-runner-noble`, `cadvisor-slim-trixie`, `ipmi-exporter-slim-trixie`, `uptime-kuma-slim-trixie` — final-stage FROM flipped from `${<PRE_BUILDER>_REF}` to `${BASE_<PRE_BUILDER>_REF}`.
   - Tooling: `_BASELINE` set grows in 3 scripts; `_INTRA_LAYER_EXEMPTIONS` gains 3 entries (each new base FROMs its sibling pre-builder).
   - `verify-no-upstream-drift _EXPECTED=6` unchanged (base/* images FROM forge-rooted pre-builder/*, not upstream).
   - Zero L4 runtime Dockerfile FROMs `pre-builder/*` as its final stage (grep-assertion).
   - Dep graph regen'd; CAPABILITIES extended; memory/docker-standard.md + docs/LAYERING.md Rule 12 member list updated.
4. **Urgency** — Quality-of-life. Closes the public/internal boundary gap identified by the FG-076 audit. No CVE pressure.
5. **Happy path** —
   1. `mkdir images/base/debian-slim-trixie images/base/ubuntu-slim-noble images/base/node-slim-trixie`.
   2. Each gets Dockerfile (FROM pre-builder/<sibling> + /hc + USER 65532 + entrypoint) + image.yaml (repo:, tag:, depends_on: pre-builder/<sibling>) + PROMISES + EXPECTATIONS + scan-baseline + sid-pins/.keep + smoke tests.
   3. Rewire 4 consumer Dockerfiles' ARG default + final FROM.
   4. Update tooling (`_BASELINE` sets in 3 scripts, build-image.sh BASE_*_REF resolver).
   5. Regen dep graph.
   6. CAPABILITIES + INDEX + LAYERING.md + memory/docker-standard.md Rule 12 member list.
6. **Edge cases / failure modes** —
   - Chain depth: base/node-slim-trixie lands the Node chain at **5 hops** exactly (at the FG-042 cap). Documented explicitly in plan doc + memory/docker-standard.md.
   - USER 65532 inherited from base/*-slim-trixie into builder stages: consumer Dockerfiles that USE the base as a BUILDER stage (today: none — the 4 flipped consumers use base/*-slim as RUNTIME only) would need `USER 0`. If a future FG adds a builder-use consumer, that override is 1 line.
   - github-runner-noble currently has no USER directive (runs as root). After the flip, inheriting USER 65532 would break the GitHub Actions runner startup. **Must add `USER 0` override** in the runner Dockerfile.
   - cadvisor-slim-trixie + ipmi-exporter-slim-trixie also currently run as root (cadvisor requires /sys mount access; ipmi-exporter needs /dev/ipmi0). **Must add `USER 0` override** in both.
   - uptime-kuma-slim-trixie upstream Dockerfile sets its own USER — check if override needed.
7. **Out of scope** —
   - Collapsing the pre-builder/ tier into base/ (discussed as Option A in the FG-076 trade-off review — rejected for now; FG-077 keeps the tier distinction and just completes the public-API shape).
   - New base/node-scratch-trixie or any scratch Node runtime (would need chain-depth rework first).
   - External repo updates — homelab bots' FROM paths stay on `pre-builder/python-slim-trixie` (FG-074 revision tracks that migration separately).
   - Any bump to `verify-no-upstream-drift _EXPECTED`.
8. **How we know it's done** — see Gherkin + `tests/acceptance/test_FG_077_base-slim-foundations.sh`. All sections pass locally + CI; 3 new `base/*-slim-trixie` tags publish on main-cron; `docker manifest inspect` returns OK on each.
9. **Capabilities delivered or extended** —
   - NEW `image.debian-slim-foundation` — `base/debian-slim-trixie` exists, apt-upgraded, /hc + USER 65532 + sensible entrypoint; final runtime for consumers who want a plain Debian slim.
   - NEW `image.ubuntu-slim-foundation` — `base/ubuntu-slim-noble` exists under the same contract.
   - NEW `image.node-slim-foundation` — `base/node-slim-trixie` exists under the same contract.
   - EXT `arch.base-tier-public-api` — the public-API boundary now holds universally: every L4 runtime FROMs a `base/*` (or documented upstream exemption like `postgres-slim-trixie → postgres:18`).

## Gherkin acceptance

```
Scenario: 3 new base/*-slim-trixie exist with explicit repo:
  Given FG-077 has shipped
  When I ls images/base/
  Then I see debian-slim-trixie, ubuntu-slim-noble, node-slim-trixie
   And each image.yaml declares repo: base/<name>

Scenario: all 3 build + smokes pass
  Given FG-077 has shipped
  When I run `bash scripts/build-image.sh base/<name>` for each
  Then each builds + every smoke script under tests/ exits 0

Scenario: 4 consumer Dockerfiles flipped
  Given FG-077 has shipped
  When I grep `^ARG .*_SLIM.*REF=ghcr.io/bboortz/pre-builder/` across every Dockerfile
  Then zero final-stage FROMs reference pre-builder/* in a consumer
   And the 4 consumer Dockerfiles use the new BASE_*_REF ARGs for their final FROM

Scenario: Rule 12 passes on the 3 new images
  Given FG-077 has shipped
  When I run python3 scripts/verify-dockerfile-conformance.py
  Then it exits 0
   And each new base/* image has image.yaml with explicit repo: + PROMISES.yaml

Scenario: verify-no-upstream-drift unchanged
  Given FG-077 has shipped
  Then verify-no-upstream-drift.sh _EXPECTED=6 and passes

Scenario: dep graph includes all 3 new foundations
  Given FG-077 has shipped
  When I regenerate docs/image-dependency-graph.md
  Then the L3 subgraph lists base_debian_slim_trixie + base_ubuntu_slim_noble + base_node_slim_trixie
```

## References

- Plan: `docs/plan/FG-077-base-slim-foundations-plan.md`
- Red test: `tests/acceptance/test_FG_077_base-slim-foundations.sh`
- Precedent: FG-075 `base/python-slim-trixie`
- Parent audit: FG-076 follow-up inventory ("Pre-builder only (no L2 builder) — 1 · Pre-builder + builder — 3")
- Trade-off review: §Cons analysis above the FG-077 branch creation (CI job cost + maintenance + Node chain depth at cap)
