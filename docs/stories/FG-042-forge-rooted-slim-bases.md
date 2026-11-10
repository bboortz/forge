---
id: FG-042
slug: forge-rooted-slim-bases
status: shipped
owner: bboortz
created: 2026-11-10
---

# FG-042 — forge-rooted slim bases + build.yml pre-builders tier

Forge images today root on **5 separate Docker Hub trust anchors** (`python:3.14-slim-trixie`, `debian:trixie-slim`, `golang:1.27-trixie`, `node:22-trixie-slim`, `postgres:18`). Two of those are pulled by **multiple forge images in parallel** — `python:3.14-slim-trixie` is consumed by both `python-slim-trixie` and `forge-builder-trixie`, and `debian:trixie-slim` is consumed by both `cadvisor-slim-trixie` and `ipmi-exporter-slim-trixie`. In those four Dockerfiles, the upstream tag is grep-linked but structurally independent: `grep` can't enforce they stay in sync, so **version drift is a code-review discipline, not a structural guarantee**.

This story collapses the two multi-consumer anchors behind forge-owned pre-builder images (`debian-slim-trixie` NEW; `python-slim-trixie` already exists but gets a tier-reshuffle), then refactors the downstream Dockerfiles to FROM the forge image instead of Docker Hub directly. Result: **one Dockerfile per software version**, one cron re-resolve per upstream digest, scanner sees a single forge-signed base per family. The 5 Docker Hub anchors drop to 2 "used-in-parallel" ones (down to 0 effectively — each remaining is consumed by exactly one forge image).

Originally shelved as "cosmetic" on 2026-11-09 (narrow framing: trust anchor is still ultimately Docker Hub). Revived 2026-11-10 after the dependency graph made three stronger benefits visible that the original analysis missed — see `docs/image-dependency-graph.md` + the IDEAS.md entry revision.

## 9 canonical answers

1. **Who** — Forge maintainer (me). Secondary: every scanner / auditor who cares about reducing the forge-fleet's upstream-trust-anchor count, and every consumer who benefits from guaranteed-in-sync base versions across the slim fleet.

2. **When** — refactor fires at daily cron time. New ordering: `publish-pre-builders` (new tier 0) builds debian-slim-trixie + python-slim-trixie → existing tiers 1-3 consume them.

3. **What success looks like**:
   - `ghcr.io/bboortz/debian-slim-trixie:0.1` publishes with the standard triple (cosign + SBOM + scan).
   - `python-slim-trixie` moved from `publish-derivatives` (tier 3) to `publish-pre-builders` (new tier 0) — no Dockerfile change.
   - `forge-builder-trixie` Dockerfile: `FROM python:3.14-slim-trixie` → `FROM python-slim-trixie` (dogfood).
   - `cadvisor-slim-trixie` + `ipmi-exporter-slim-trixie` Dockerfiles: `FROM debian:trixie-slim` → `FROM debian-slim-trixie`.
   - Build.yml: new `publish-pre-builders` tier gates `publish-builders`.
   - Every existing acceptance test (FG-001/025/034/035/036/037/043/044 and especially FG-046's split cells) passes unchanged — behavior is preserved, only the FROM chain shifts.
   - **Dependency graph** (post-shipping): 5 → 2 Docker Hub anchors with a multi-forge-consumer arrow count; `docs/image-dependency-graph.md` regenerated.
   - **Grep check**: `grep -c "debian:trixie-slim\|python:3.14-slim-trixie" images/*/Dockerfile` drops from 4 to 2 (only the new forge-rooted bases reference upstream directly).

4. **Urgency** — quality-of-life + supply chain hygiene. Not emergency. Three concrete wins the dependency graph made visible:
   - **Version drift prevention**: today `python:3.14-slim-trixie` appears in 2 Dockerfiles that `grep` can't link. FG-032's Python 3.13 → 3.14 bump required editing both in parallel; a future bump (3.15) would require the same discipline. Post-FG-042: one place to bump, atomic propagation.
   - **Fewer upstream pulls per cron**: daily cron currently re-resolves 5 Docker Hub digests. Post-FG-042: 2 digests per family.
   - **Smaller scanner surface**: Beaconry / grype track one forge-signed base per family instead of multiple parallel-pulled upstreams.

5. **Happy path**:
   1. Daily cron: publish-pre-builders builds debian-slim-trixie + python-slim-trixie (both FROM their respective Docker Hub upstream + apt-upgrade).
   2. publish-builders: forge-builder-trixie builds FROM forge-local python-slim-trixie; forge-builder-go-trixie unchanged (stays on golang:1.27-trixie — Go-toolchain-version-pinning concern, see out-of-scope).
   3. publish-base: scratch-base-trixie unchanged (still FROMs forge-builder-trixie).
   4. publish-derivatives: everything else. cadvisor-slim + ipmi-exporter-slim pick up forge-local debian-slim-trixie.
   5. Consumer `docker pull` behavior unchanged; wire-level image contract for every runtime image is untouched.

6. **Edge cases / failure modes**:
   - **python-slim-trixie promoted from orphan to critical-path**. Today a python-slim-trixie build failure is isolated. Post-FG-042: a python-slim-trixie build failure cascades (no forge-builder-trixie → no scratch base → nothing downstream builds). Mitigation: python-slim-trixie has always been covered by FG-001's acceptance + runs in the same cron that would have failed anyway if upstream `python:3.14-slim-trixie` broke.
   - **debian-slim-trixie circular dependency risk**. It must NOT depend on forge-builder-trixie (which FROMs python-slim-trixie which FROMs python:3.14-slim-trixie, logically "above" debian-slim-trixie in the trust chain). Keep debian-slim-trixie simple: FROM debian:trixie-slim + apt-upgrade + CA + syft directly. No builder abstraction needed; its own builder stage is itself.
   - **Scratch baseline semantics unchanged**. `scratch-base-trixie` still composes via `COPY --from=scratch_base / /`; its builder stage uses forge-builder-trixie (which now dogfood-FROMs python-slim-trixie). Transitively: baseline inherits python-slim-trixie's apt-upgrade state. This is actually the *point*.
   - **build.yml daily-cron wall clock**: adding a 4th sequential tier adds ~2 min (python-slim-trixie build + debian-slim-trixie build in parallel; next tier gated behind both). Acceptable given existing cron runs ~10-12 min.
   - **CI publish ordering**: `build.yml` currently has `publish-builders needs: []`, `publish-base needs: [publish-builders]`, `publish-derivatives needs: [publish-base]`. New: `publish-pre-builders needs: []`, `publish-builders needs: [publish-pre-builders]`, rest unchanged.
   - **Tier-0 image publishing order within pre-builders**: debian-slim-trixie + python-slim-trixie are peers (neither FROMs the other); they publish in parallel within the tier.

7. **Out of scope**:
   - **forge-builder-go-trixie dogfood** (keep it on `golang:1.27-trixie` direct). golang:X-trixie provides the specific Go version we need (1.27+); building Go on debian-slim-trixie ourselves would mean either downloading the Go release tarball or apt-installing trixie's 1.24 (which is the whole reason FG-046 exists). Not worth it; forge-builder-go-trixie stays as-is.
   - **uptime-kuma-slim-trixie `node:22-trixie-slim` migration** (would need a `node-slim-trixie` sibling to debian-slim-trixie). Single consumer, not in the "multi-consumer drift risk" category. Defer to IDEAS.md until a 2nd Node-source image appears.
   - **postgres-slim-trixie `postgres:18` migration**. Postgres is externally-maintained; dogfood would mean rebuilding postgres from source (far bigger than this story). Defer.
   - **python-slim-trixie FROM debian-slim-trixie** (deeper dogfood). Python 3.14 isn't in Debian trixie's apt (trixie ships 3.13); python-slim-trixie necessarily FROMs upstream `python:3.14-slim-trixie` until we're willing to build Python from source. Defer indefinitely — upstream python docker image is Debian-based already, so the trust-anchor transitivity is clean enough.
   - **Scan-regression gate flaking from apt-upgrade drift**: debian-slim-trixie's first-ever publish may surface previously-filtered CVEs that cadvisor + ipmi-exporter-slim now inherit. That's fine — scan-baseline.json gets regenerated in the PR.

8. **How we know it's done** — see Gherkin below.

9. **Capabilities delivered or extended**:
   - NEW `build.pre-builder-tier` — four-tier daily-cron publish ordering: `publish-pre-builders` → `publish-builders` → `publish-base` → `publish-derivatives`. Each tier gated on the previous completing. Replaces the current three-tier model.
   - NEW `image.forge-rooted-slim-bases` — forge owns the Debian + Python slim bases consumed by every other slim/scratch image. Trust anchor per family consolidated to 1 forge image + 1 upstream digest.
   - EXT `build.shared-builder` (FG-025) — forge-builder-trixie now FROMs `python-slim-trixie` (dogfood) instead of Docker Hub directly.
   - EXT `image.has-shell` (FG-001+) — slim-base images (debian-slim-trixie) also carry shell + apt; already covered by the CAP but mention for completeness.

## Gherkin acceptance

```
Scenario: debian-slim-trixie:0.1 publishes with the standard triple
  Given a successful build.yml publish cycle
  When the image resolves on GHCR
  Then cosign verify succeeds with the standard --certificate-identity
   And the SBOM lists dpkg packages from debian:trixie-slim + apt-upgrade
   And the grype scan is attached

Scenario: forge-builder-trixie dogfoods python-slim-trixie
  Given the rebuilt forge-builder-trixie image
  When its Dockerfile is inspected
  Then it FROMs python-slim-trixie (not python:3.14-slim-trixie upstream)
   And `docker history` resolves the base layer to a forge-local digest during local builds
   And FG-025's existing acceptance test passes unchanged

Scenario: cadvisor-slim-trixie + ipmi-exporter-slim-trixie FROM debian-slim-trixie
  Given the rebuilt images
  When their Dockerfiles are inspected
  Then both FROM debian-slim-trixie (not debian:trixie-slim upstream)
   And FG-044's + FG-037's acceptance tests pass unchanged

Scenario: 4-tier publish ordering is enforced in build.yml
  Given .github/workflows/build.yml
  When the job graph is inspected
  Then publish-pre-builders has `needs: []`
   And publish-builders has `needs: [publish-pre-builders]`
   And publish-base has `needs: [publish-builders]`
   And publish-derivatives has `needs: [publish-base]`

Scenario: python-slim-trixie moved to publish-pre-builders tier
  Given scripts/discover-images.sh
  When it emits the matrix for the publish-pre-builders tier
  Then python-slim-trixie AND debian-slim-trixie appear
   And python-slim-trixie does NOT appear in publish-derivatives

Scenario: upstream grep count drops
  Given all forge Dockerfiles
  When `grep -E "^FROM (debian:trixie-slim|python:3.14-slim-trixie)"` runs across images/*/Dockerfile
  Then exactly 2 Dockerfiles match (debian-slim-trixie/Dockerfile + python-slim-trixie/Dockerfile)
   And no other Dockerfile references these upstream tags

Scenario: dependency graph regenerates
  Given FG-042 merges
  When docs/image-dependency-graph.md is inspected
  Then debian:trixie-slim is consumed by exactly 1 forge image (debian-slim-trixie)
   And python:3.14-slim-trixie is consumed by exactly 1 forge image (python-slim-trixie)
   And cadvisor-slim-trixie + ipmi-exporter-slim-trixie FROM debian-slim-trixie
   And forge-builder-trixie FROMs python-slim-trixie

Scenario: every migrated image's smoke suite + acceptance test passes
  Given the rebuilt forge-builder-trixie, cadvisor-slim-trixie, ipmi-exporter-slim-trixie, python-slim-trixie
  When their smoke suites + FG-NNN acceptance tests run
  Then every assertion passes (behavior preservation)
```

## References

- Plan: `docs/plan/FG-042-forge-rooted-slim-bases-plan.md`
- Red test: `tests/acceptance/test_FG_042_forge-rooted-slim-bases.sh`
- Dependency graph (motivation): `docs/image-dependency-graph.md`
- IDEAS.md entry revision (2026-11-10): the original FG-042 shelving was narrow; this story addresses the three real benefits (version drift, pull count, scanner surface) the diagram made visible
- Related shipped: FG-025 (forge-builder-trixie), FG-046 (forge-builder-go-trixie — same "shared builder" pattern)
- Related deferred: node-slim-trixie + postgres-slim-trixie dogfoods (IDEAS.md, same motivation but single-consumer so lower-value)
