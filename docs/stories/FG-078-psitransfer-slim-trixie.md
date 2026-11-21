---
id: FG-078
slug: psitransfer-slim-trixie
status: draft
owner: bboortz
created: 2026-11-21
---

# FG-078 — Forge builds `psitrax/psitransfer` so homelab drops its local Dockerfile

Homelab currently maintains its own `docker/psitransfer/` build recipe to deploy psitransfer (self-hosted file-share, upstream `psi-4ward/psitransfer`, Docker Hub `psitrax/psitransfer`). FG-078 moves that build into Forge: a forge-published `ghcr.io/bboortz/psitransfer-slim-trixie:latest` image that homelab consumes with a one-liner `image:` in compose — no local Dockerfile, no local build-at-deploy, inherited CVE-patch cadence + cosign-verifiable identity.

Best outcome: after FG-078 ships + the paired homelab PR lands, `homelab/docker/psitransfer/` is deleted and compose reads `image: ghcr.io/bboortz/psitransfer-slim-trixie:latest`.

## 9 canonical answers

1. **Who** — Homelab operator (gains daily-cron patches + cosign-verify); Forge maintainers (one more L4 runtime to maintain, net-zero vs homelab's existing recipe).
2. **When** — Fires every time a new psitransfer release ships OR a dependency CVE lands. Today: homelab operator rebuilds manually. Post-FG-078: Forge's daily cron handles it.
3. **What success looks like** —
   - `images/psitransfer-slim-trixie/` exists in Forge with Dockerfile, image.yaml, PROMISES, EXPECTATIONS, scan-baseline, smoke tests.
   - `ghcr.io/bboortz/psitransfer-slim-trixie:latest` published daily by main-cron.
   - Homelab's `docker-compose.yml` reads `image: ghcr.io/bboortz/psitransfer-slim-trixie:latest`; `docker/psitransfer/` is deleted.
   - Smoke tests prove the service starts + serves HTTP 200 on its `/` endpoint + accepts an upload (if practical to automate).
   - Published digest is cosign-verifiable against `bboortz/forge`'s workflow identity.
4. **Urgency** — Quality-of-life for homelab. Moderate: no CVE pressure today, but homelab's current build path has no CVE scanning.
5. **Happy path** —
   1. Decide construction shape (two options, see below).
   2. Scaffold `images/psitransfer-slim-trixie/` with the chosen shape.
   3. Red test (`tests/acceptance/test_FG_078_*.sh`): image builds, smoke scripts pass, homelab's deployed service equivalence can be asserted via a start-then-curl probe.
   4. Register with `_UPSTREAM_SOURCES` (if Option B) or add runtime-exemption (if Option A).
   5. Dep graph + CAPs + `make test-fast`.
   6. PR → dev → merge → release → build.yml publishes the tag.
   7. Homelab PR: delete `docker/psitransfer/`, flip compose to the new image.
6. **Edge cases / failure modes** —
   - Upstream psi-4ward/psitransfer repo availability — if GitHub is down during daily cron, the build fails gracefully; last-published digest stays fetchable.
   - Persistent storage: psitransfer stores uploads under `/app/data`. The image must declare a `VOLUME` so homelab's bind-mount survives image upgrades.
   - Port: psitransfer serves on `:3000` by default; expose as `EXPOSE 3000`.
   - Config mode: psitransfer reads `config.production.json` from `/app/config/`. Mount as volume; don't bake in.
   - Upstream's own Dockerfile may use an alpine base — FG-078 would bias toward Forge's `base/node-slim-trixie` (post-FG-077) for supply-chain consistency even if that drifts from upstream's packaging choice.
7. **Out of scope** —
   - A `psitransfer-scratch-trixie` variant (scratch Node runtime blocked by chain depth cap — see FG-077).
   - An HTTPS-terminating reverse proxy sidecar (homelab's nginx handles that).
   - Multi-arch (amd64-only for now; matches current Forge policy).
   - Deleting homelab's `docker/psitransfer/` — that happens in a paired homelab PR after FG-078 publishes.
8. **How we know it's done** — see Gherkin + `tests/acceptance/test_FG_078_psitransfer-slim-trixie.sh`. Published tag resolves on GHCR. Homelab's smoke (manual: upload a test file, download it) works end-to-end after the paired migration.
9. **Capabilities delivered or extended** —
   - NEW `image.psitransfer-slim` — forge-signed psitransfer runtime; daily-cron patched; cosign-verifiable.
   - EXT `arch.base-tier-public-api` — one more L4 consumer FROMing `base/node-slim-trixie`.

## Two construction options (decide in plan doc)

| | Option A — FG-012 externally-sourced | Option B — from-source via builder/node-trixie |
|---|---|---|
| **Shape** | `image.yaml source: block` cloning `psi-4ward/psitransfer` at build time + upstream's own Dockerfile does the build | Local Dockerfile: `FROM builder/node-trixie AS builder` + `npm ci` + `npm run build` → `FROM base/node-slim-trixie` + COPY artifacts |
| **Runtime shape** | Whatever upstream's Dockerfile produces (likely their alpine base + their Node version) | Forge-controlled: `base/node-slim-trixie` + ~10 MB app |
| **Chain depth** | Not applicable (external build) | 5 hops at FG-042 cap (Node family at cap post-FG-077) |
| **Maintenance** | ≈ zero — tracks upstream's own packaging choices via `ref: "latest"` | Occasional attention when upstream changes build process |
| **Supply chain** | Partial — forge signs the digest + scans, but runtime provenance is upstream's | Full forge-controlled (Node version + apt-upgrade we control) |
| **Pattern precedent** | Beaconry (FG-012) — `beaconry-hub`, `beaconry-scout`, `beaconry-telegram-mock` | Prometheus/alertmanager/node-exporter — FG-046 / FG-048 |

**Recommendation**: **Option A** first ship (minimum-touch, matches homelab's "just use the upstream image" expectation). Keep Option B as a future FG if: (a) upstream's Node version lags behind security patches, (b) upstream's Dockerfile shape changes and breaks something, (c) we want tighter apt-upgrade control. For a static file-share service the extra from-source overhead probably isn't worth it today.

## Gherkin acceptance

```
Scenario: image dir exists with the standard forge shape
  Given FG-078 has shipped
  When I ls images/psitransfer-slim-trixie/
  Then I see Dockerfile OR image.yaml with source: block (Option A or B)
   And I see PROMISES.yaml, EXPECTATIONS.yaml (if option B + depends_on), scan-baseline.json, tests/

Scenario: image builds + smoke tests pass
  Given FG-078 has shipped
  When I run `bash scripts/build-image.sh psitransfer-slim-trixie`
  Then the image is built
   And every smoke test under images/psitransfer-slim-trixie/tests/ exits 0

Scenario: service starts + serves HTTP 200
  Given FG-078 has shipped + image built
  When I `docker run -d -p 3000:3000 forge-local/psitransfer-slim-trixie:latest` and curl :3000/
  Then I get HTTP 200 (the psitransfer upload page)

Scenario: published tag resolves
  Given FG-078 has shipped + main-cron ran
  When I docker manifest inspect ghcr.io/bboortz/psitransfer-slim-trixie:latest
  Then it resolves

Scenario: homelab PR can delete docker/psitransfer/
  Given FG-078 has shipped
  When I open the paired homelab PR
  Then docker/psitransfer/ is deleted
   And docker-compose.yml reads `image: ghcr.io/bboortz/psitransfer-slim-trixie:latest`
   And the service behaves identically to the pre-migration local build
```

## References

- Upstream repo: `github.com/psi-4ward/psitransfer`
- Upstream Docker Hub: `psitrax/psitransfer`
- Homelab current recipe: `homelab/docker/psitransfer/` (to be deleted in paired PR)
- Pattern precedent for Option A: FG-012 (beaconry), FG-014 (beaconry-hub)
- Pattern precedent for Option B: FG-046 (cadvisor-slim-trixie), FG-048 (prometheus-scratch-trixie's Node UI builder)
- Plan: `docs/plan/FG-078-psitransfer-slim-trixie-plan.md` (to be created when FG-078 enters ready state — decides Option A vs B)
- Red test: `tests/acceptance/test_FG_078_psitransfer-slim-trixie.sh`
