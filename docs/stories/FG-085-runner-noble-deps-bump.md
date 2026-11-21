---
id: FG-085
slug: runner-noble-deps-bump
status: ready
owner: bboortz
created: 2026-11-21
---

# FG-085 — Bump 5 pinned versions in `images/github-runner-noble/requirements-dev.txt`

Post-FG-084 audit extended to the vendored `requirements-dev.txt` found 5 safe bumps (plus 2 packages already at latest). **Zero mandatory security bumps** — every pinned version is advisory-free per OSV.dev. This is pure QoL hygiene.

## Bump table

| Package | Current | Target | Gap | Risk |
|---|---|---|---|---|
| `ansible-lint` | 26.4.0 | **26.11.0** | 7 minor | Low — stable project |
| `fastapi` | 0.136.3 | **0.165.0** | 29 minor on 0.x | Medium — 0.x minors can break. Blast radius limited to the runner webhook; smoke-test the image. |
| `PyJWT` | 2.15.0 | **2.15.1** | 1 patch | Low |
| `pytest` | 9.0.3 | **9.2.0** | 2 minor | Low — mature |
| `ruff` | 0.15.22 | **0.17.6** | 2 minor on 0.x | Low — each ruff version adds lint rules; no API surface used by consumers |
| `pytest-xdist` | 3.8.0 | 3.8.0 | — | ✅ already latest |
| `yamllint` | 1.38.0 | 1.38.0 | — | ✅ already latest |

## Vendored-source caveat

The file header says this is a **vendored copy of `bb-claw/homelab`'s `requirements-dev.txt`** (snapshot 2026-11-14). Sync strategy: "chore PR when homelab's drifts." FG-085 **inverts** that direction — forge leads, homelab follows. Acknowledged. Paired homelab PR to resync is out of scope for forge (homelab is maintained separately).

## 9 canonical answers

1. **Who** — Forge maintainer (hygiene); CI maintainer who pulls `github-runner-noble:latest` and expects current tool versions.
2. **When** — Fires every time the audit shows the gap. Deferring gets no benefit; the OSV baseline is clean so there's no window-of-vulnerability either way.
3. **What success looks like** — All 5 bumps applied; `github-runner-noble` builds locally; its smokes pass; `make test-fast` green; new FG-085 acceptance red→green.
4. **Urgency** — Quality-of-life; low. No CVE.
5. **Happy path** —
   1. Edit 5 lines in `requirements-dev.txt`.
   2. Rebuild `github-runner-noble` locally; run its smoke suite.
   3. `make test-fast` + FG-085 acceptance green.
   4. PR → dev → release → build cron.
6. **Edge cases / failure modes** —
   - **fastapi 0.136→0.165 breaks the runner's webhook**: if the smokes caught it, revert fastapi + ship the other 4; otherwise ship together.
   - **ruff adds a rule that fails internal code**: forge's own code isn't linted by this ruff (that pin applies to homelab consumers). Non-issue.
   - **pytest 9.0→9.2 removes a deprecated API**: homelab's tests only — not forge's. Non-issue for forge-side acceptance.
7. **Out of scope** —
   - Homelab PR to resync (paired work; homelab is under its own maintenance).
   - Bumping `pytest-xdist` or `yamllint` — already at latest.
   - The 18 stale `scan-baseline.json` files not covered by FG-084 (separate hygiene story if desired).
8. **How we know it's done** — see Gherkin + `tests/acceptance/test_FG_085_runner-noble-deps-bump.sh`.
9. **Capabilities delivered or extended** —
   - EXT `image.github-runner-noble-pre-baked` — the 7 pinned packages in the pre-baked CI toolset get refreshed. PROMISES.yaml doesn't declare version floors, so no `version:` bump needed.

## Gherkin acceptance

```
Scenario: 5 lines bumped to target versions
  Given FG-085 has shipped
  Then images/github-runner-noble/requirements-dev.txt reads:
       ansible-lint==26.11.0
       fastapi==0.165.0
       PyJWT==2.15.1
       pytest==9.2.0
       ruff==0.17.6
   And pytest-xdist + yamllint lines are unchanged (already latest)

Scenario: image builds + smokes pass with new pins
  Given FG-085 has shipped
  When I bash scripts/build-image.sh github-runner-noble
  Then the build succeeds
   And every smoke_*.sh exits 0

Scenario: all remaining OSV advisories are zero
  Given FG-085 has shipped
  Then OSV returns 0 advisories for each bumped version
```

## References

- Audit source: post-FG-084 full version sweep (OSV.dev + PyPI latest check)
- Plan: `docs/plan/FG-085-runner-noble-deps-bump-plan.md`
- Red test: `tests/acceptance/test_FG_085_runner-noble-deps-bump.sh`
