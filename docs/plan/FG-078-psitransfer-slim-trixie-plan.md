# FG-078 — Plan: psitransfer-slim-trixie (Option B, from-source)

**Story**: [`docs/stories/FG-078-psitransfer-slim-trixie.md`](../stories/FG-078-psitransfer-slim-trixie.md)
**Status**: ready → shipped
**Branch**: `feat/FG-078-psitransfer-slim-trixie`

## Design delta

Picked **Option B** from the story: from-source build via `builder/node-trixie` (frontend + backend stages) → `base/node-slim-trixie` runtime. Chain at Node family's 5-hop cap.

5-stage Dockerfile:

| # | Stage | FROM | Role |
|---|---|---|---|
| 0 | `src` | `builder/node-trixie` | `git clone https://github.com/psi-4ward/psitransfer` + pin resolved commit SHA in `/src/REVISION` |
| 1 | `frontend` | `builder/node-trixie` | `cd app && npm ci && npm run build` → Vue 2 webpack bundle under `public/app` |
| 2 | `backend` | `builder/node-trixie` | `npm ci --omit=dev` at repo root → production node_modules |
| 3 | `sbom` | `builder/node-trixie` | `syft dir:/sbom-input -o cyclonedx-json > /sbom.json` |
| 4 | `hc` | `ghcr.io/bboortz/hc:0.1.0` | static healthcheck binary (FG-031 pattern) |
| 5 | `runtime` | `base/node-slim-trixie` | `USER 0` for mkdir /data + chown; COPY runtime artifacts from stages 0/1/2/3/4; `USER 65532`; VOLUME /data; EXPOSE 3000; HEALTHCHECK on /; CMD ["app.js"] (ENTRYPOINT=node inherited from base) |

ARG defaults: `PSITRANSFER_REF=latest` (daily cron re-resolves per FG-013 build.ref-latest-release pattern). Operators who want reproducibility pass `--build-arg PSITRANSFER_REF=<sha>`.

The runtime image declares `depends_on: base/node-slim-trixie`. Rule 12 post-FG-075 + the FG-077 ordering fix ensure publish-base finishes before publish-derivatives starts.

L0.1 upstream source registered: `github.com/psi-4ward/psitransfer` → `psitransfer-slim-trixie` (single consumer, Node-source build stage).

## Alternatives rejected

- **Option A — FG-012 externally-sourced** (clone upstream + build via upstream's own Dockerfile): would FROM `node:26-alpine` instead of forge's Debian-glibc chain. Breaks the "all forge L4 Node images are on `base/node-slim-trixie`" symmetry. Also skips `apt-upgrade` → forge's weekly CVE patching doesn't reach it. Rejected.
- **Build frontend into the runtime stage itself** (single-stage): would ship webpack + all dev deps into the runtime. ~200 MB extra. Rejected.
- **Skip the SBOM stage** (no `/sbom.json`): breaks FG-020 pattern + makes grype scanning miss Node.js dependency tree. Rejected.

## Breaking changes

**None**. New image; homelab's existing `docker/psitransfer/` recipe + compose file-mount paths are preserved on the forge side (same `/data` volume, same `:3000` port, same `USER 65532`-compatible permissions).

## Merge plan

Full `memory/workflow.md § Blocking gates`. Smoke tests (`smoke_serves_http.sh` especially) will exercise the running container end-to-end.

## Rollout plan

1. PR → dev (auto-merge on green CI)
2. `release.yml` → main
3. `build.yml` → publishes `ghcr.io/bboortz/psitransfer-slim-trixie:latest` (with FG-077 ordering fix, no manual rerun needed)
4. Verify tag via `docker manifest inspect`
5. Paired homelab PR: delete `docker/psitransfer/`, flip compose to `image: ghcr.io/bboortz/psitransfer-slim-trixie:latest`

## Shipping evidence

Filled at pre-ship audit. All rows ✅ before merge.

| Item | Pointer | Status |
|------|---------|--------|
| Scenario: image dir exists | `tests/acceptance/test_FG_078_psitransfer-slim-trixie.sh:§1` | ✅ |
| Scenario: image builds + smokes pass | `tests/acceptance/test_FG_078_psitransfer-slim-trixie.sh:§2` | ✅ |
| Scenario: service serves HTTP 200 | `images/psitransfer-slim-trixie/tests/smoke_serves_http.sh` | ✅ |
| Scenario: published tag resolves | post-merge `docker manifest inspect` | ⚠️ (post-rollout) |
| CAP `image.psitransfer-slim` | test + `docs/CAPABILITIES.md#image.psitransfer-slim` | ✅ |
