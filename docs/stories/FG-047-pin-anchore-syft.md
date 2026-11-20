---
id: FG-047
slug: pin-anchore-syft
status: draft
owner: bboortz
created: 2026-11-10
---

# FG-047 — Pin `anchore/syft:latest` to a specific version

Three Forge builder images (`forge-builder-trixie`, `forge-builder-go-trixie`, `uptime-kuma-slim-trixie`) pull `docker.io/anchore/syft:latest` as a `COPY --from=syft-src /syft …` source. With `:latest` as the tag, every daily cron re-resolves the Docker Hub digest — 3 pulls per cron just for syft, before any other image build begins. On 2026-11-10 this session hit Docker Hub's unauthenticated 100-pulls/6h cap **twice**, blocking `make check-smart-strict` pre-push gates and forcing a `--no-verify` escape (committed with explicit operator approval, covered by CI's own rate budget).

Pinning syft to a specific version (`v1.57.1` at time of writing) cuts the daily re-resolve. Bumps become explicit (edit the ARG, let daily cron propagate). syft doesn't ship security fixes that we need within 24h — it's a builder-stage SBOM tool that's already rebuilt into every image's layer, not a runtime dep.

## 9 canonical answers

1. **Who** — Forge maintainer (me) + any CI/local operator who's hit a Docker Hub rate-limit on pre-push gate. Secondary: Beaconry (and any future scanner) that sees more stable SBOM-emitter provenance (one syft version baked per publish cycle instead of silently drifting between rebuilds within a single cron).

2. **When** — fires at every daily cron. Current behaviour re-resolves `syft:latest` 3× per cron. Post-FG-047: zero re-resolves (digest is pinned in the Dockerfile's ARG default).

3. **What success looks like**:
   - All three Dockerfiles' `ARG SYFT_SRC=docker.io/anchore/syft:latest` → `ARG SYFT_SRC=docker.io/anchore/syft:v1.57.1` (or whatever upstream stable is at ship time).
   - `grep -r "anchore/syft:latest" images/` returns zero hits post-FG-047.
   - Each image's existing acceptance test + smoke suite passes unchanged (syft binary behaviour is backwards-compatible within a minor; we're not downgrading).
   - Daily cron's Docker Hub pull count for syft drops from 3→0 per cycle.

4. **Urgency** — quality-of-life + supply-chain-infra resilience. Not emergency. Burned 90+ min of pre-push cycles this session alone retrying rate-limited builds. Compounded by `anchore/grype:latest` + `anchore/grype-db:latest` + `gcr.io/projectsigstore/cosign:v2.6.5` pulls all competing for the same per-IP cap during full-run gates.

5. **Happy path**:
   1. Operator edits 3 Dockerfiles, changing `ARG SYFT_SRC=…:latest` → `…:v1.57.1`.
   2. `make check-smart-strict` passes (no new acceptance tests needed — existing smokes exercise syft).
   3. Daily cron publishes the three builders with syft v1.57.1 baked in; downstream derivatives pick up new builder bases on their next cron cycle.
   4. Bumping syft later is a one-shot sed across 3 files + a PR (same shape as FG-041's cosign pin bump).

6. **Edge cases / failure modes**:
   - **Pinned version eventually unsupported** — upstream anchore/syft maintains a reasonable support window; if v1.57.1 is EOL before we re-pin, syft's own SBOM output format may change. Mitigation: pair with an FG-041-style drift-gate test (fails CI 7 days before a review date). Keeping scope tight for V1: pin without the drift gate, bump opportunistically.
   - **Other Docker Hub tool images still unpinned** — `anchore/grype:latest`, `gcr.io/projectsigstore/cosign:v2.6.5` (cosign already pinned via FG-041), `hadolint/hadolint:latest-debian`. This story is scoped to syft only. Grype is tracked in IDEAS as follow-up.
   - **Daily cron syft-bump drift** — pinning means we no longer auto-pick up syft CVE fixes. Syft is a build-stage tool: a syft CVE doesn't affect runtime; it affects SBOM accuracy. Low risk.
   - **Beaconry SBOM diff** — each published image's SBOM now lists `syft v1.57.1` as the generator. If an operator diffs SBOMs across the fleet they'll see uniformity instead of (previously) unpredictable minor drift. Positive signal, not a regression.

7. **Out of scope**:
   - **Pinning grype, cosign (already pinned), hadolint** — one tool at a time per story. Grype queued in IDEAS.
   - **Syft-pin drift gate** — mirror FG-041's cosign-pin-drift-gate. Deferred to a follow-up (extract the gate into a reusable helper, then apply to syft + grype at once).
   - **Mirror syft to GHCR** — deeper structural fix. IDEAS entry if operator ever asks for full Docker Hub divorce.
   - **Multi-arch** — amd64-only matches every other Forge image.

8. **How we know it's done** — see Gherkin below.

9. **Capabilities delivered or extended**:
   - EXT `build.shared-builder` (FG-025) — now notes the pinned syft.
   - EXT `build.shared-go-builder` (FG-046) — same.
   - NEW `tooling.pinned-syft` — one-line CAP recording the pin version + which images carry it. Enables future operators to grep CAPABILITIES.md for the current syft pin.

## Gherkin acceptance

```
Scenario: no Dockerfile references anchore/syft:latest
  Given the forge repo
  When `grep -rn "anchore/syft:latest" images/` runs
  Then no matches are found

Scenario: all three affected Dockerfiles pin the same syft version
  Given forge-builder-trixie, forge-builder-go-trixie, uptime-kuma-slim-trixie Dockerfiles
  When their ARG SYFT_SRC= lines are inspected
  Then all three carry an identical pinned tag of the form docker.io/anchore/syft:v<X.Y.Z>

Scenario: each affected image still produces a working SBOM
  Given the three affected images are rebuilt with the pin applied
  When `docker run <image> syft version` runs (for the two builder images)
   And the builder stages of uptime-kuma-slim-trixie successfully emit /sbom.json
  Then the pinned syft version banner is reported
   And the emitted SBOMs are valid CycloneDX

Scenario: daily cron Docker Hub pull count drops to zero for syft
  Given a daily cron publish cycle
  When the three affected image builds run
  Then zero of them re-resolve docker.io/anchore/syft:latest (operator-side observation — check CI log for cache hits)
```

## References

- Plan: `docs/plan/FG-047-pin-anchore-syft-plan.md`
- Red test: `tests/acceptance/test_FG_047_pin-anchore-syft.sh`
- Precedent: FG-041 (cosign pin v2.4.3 → v2.6.5 + drift gate)
- Upstream: [anchore/syft releases](https://github.com/anchore/syft/releases) — current stable v1.57.1 (2026-11-09)
- Rate-limit context: 2026-11-10 session hit Docker Hub's 100-pulls/6h cap twice during FG-042 pre-push cycles
