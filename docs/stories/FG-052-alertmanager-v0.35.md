---
id: FG-052
slug: alertmanager-v0.35
status: shipped
owner: bboortz
created: 2026-11-15
shipped: 2026-11-15
---

# FG-052 — alertmanager-scratch-trixie v0.28.1 → v0.35.0 (dual-builder migration)

Alertmanager at Forge is currently pinned to upstream v0.28.1 — the last release that shipped compiled UI assets in-tree. FG-050 attempted a bump to v0.35 but had to defer because upstream v0.32+ switched to `//go:embed app/dist` and the `app/dist/` directory is produced only by the Node + Elm UI build step, which `forge-builder-go-trixie` doesn't provide.

FG-048 shipped `forge-builder-node-trixie` (for prometheus-scratch's React UI). That unblocks this FG: alertmanager gets the same dual-builder treatment — Node stage builds both the Elm classic UI (`ui/app/`) + the new Mantine UI (`ui/mantine-ui/`), Go stage builds the binary with `-tags builtinassets` embedding everything under `ui/app/dist/`.

Target floating `:latest` tag per FG-050's `build.ref-latest-release` pattern so the daily cron auto-tracks upstream.

## 9 canonical answers

1. **Who** — ops/maintainer first (homelab operator): keeps alertmanager current without a per-release Forge PR. Secondary: any Forge consumer that scraped alertmanager from `ghcr.io/bboortz/alertmanager-scratch-trixie:latest` and wants fresh CVE triage.

2. **When** — fires every daily cron: `build.ref-latest-release` re-resolves `actions/alertmanager@latest` → current upstream tag (v0.35.0 at ship time); image rebuilds + republishes under the same `:latest` tag. Fires on this PR too (first publish of the v0.35-shape image).

3. **What success looks like**:
   - `/-/healthy` + `/-/ready` + `/api/v2/status` all respond 200 against `forge-local/alertmanager-scratch-trixie:latest`.
   - `/api/v2/status` JSON reports `versionInfo.version` matching the resolved upstream tag (e.g. `"0.35.0"`).
   - UI is reachable: Elm classic UI at `/` returns a 200 with embedded HTML; Mantine UI at `/ui/` returns a 200 with embedded HTML. Both routes serve from the baked-in assets (verified by probing with no filesystem UI mount).
   - `amtool --version` responds with the resolved version.
   - `webhook_configs` → outbound HTTPS works (SSL_CERT_FILE still re-declared in the runtime stage per FG-009).
   - cosign + syft + grype attestations present on the published digest.
   - Homelab's existing `docker-compose.yml` continues to work: `image: ghcr.io/bboortz/alertmanager-scratch-trixie:latest` auto-pulls the new build on next `docker compose pull`. No config changes required (homelab only uses `webhook_configs` + `route` + `inhibit_rules`, all of which are unchanged in v0.35).

4. **Urgency** — correctness + security hygiene. Not blocking homelab today (v0.28.1 still works), but accumulates CVE lag the longer we wait. Current gap: v0.28.1 was released 2024-10-16; v0.35.0 2026-11-04. 13 months of fixes + features missed.

5. **Happy path**:
   1. Branch `feat/FG-052-alertmanager-v0.35` from `dev`.
   2. Rewrite `images/alertmanager-scratch-trixie/Dockerfile` as 3 build stages:
      - Stage 1 (`ui-builder` FROM `forge-builder-node-trixie`): `git clone --branch <resolved-tag>` → `cd ui/app && npm ci && npm run build` → `cd ui/mantine-ui && npm ci && npm run build`. Produces `/src/ui/app/dist/` containing both UIs.
      - Stage 2 (`builder` FROM `forge-builder-go-trixie`): COPY `/src` from Stage 1 → `GOFLAGS=-mod=mod CGO_ENABLED=0 go build -tags netgo,builtinassets -ldflags "..."` for both `alertmanager` + `amtool`. Copy templates.
      - Stage 3 (`runtime` FROM `scratch`): COPY from scratch-base + builder + hc. Unchanged ENV + USER + HEALTHCHECK + ENTRYPOINT.
   3. Switch `ALERTMANAGER_VERSION` default from `v0.28.1` → empty (FG-050 `build.ref-latest-release` pattern); add the `curl + jq` resolve step in Stage 2 before `git clone`.
   4. Update `image.yaml` tag `"0.28"` → `"latest"` (per `build.ref-latest-release` convention).
   5. Red acceptance test asserts: image builds with `-tags netgo,builtinassets`; `/api/v2/status` version matches resolved tag; `/` serves 200 with HTML containing a classic-UI marker; `/ui/` serves 200 with HTML containing a Mantine marker; `amtool --version` responds; size ≤ upstream base × 1.1.
   6. `make check-smart-strict` green locally.
   7. PR to `dev` → CI full-check → auto-merge on green.
   8. Promote dev → main via release.yml; daily cron picks up both images (alertmanager + binary refresh).
   9. Homelab compose auto-pulls new image on next `docker compose pull`.

6. **Edge cases / failure modes**:
   - **Upstream v0.36 releases mid-build and breaks the API shape** — mitigated by `build.ref-latest-release`'s `curl + jq` + local test. If a new upstream release lands that breaks the Go API, builds fail CI; we pin to the previous tag via `--build-arg ALERTMANAGER_VERSION=v0.35.0`.
   - **Elm compiler install fails** — Elm is an npm devDependency (`"elm": "0.19.1-6"` in `ui/app/package.json`); `npm ci` installs it automatically. No separate elm install step needed.
   - **Mantine build pulls huge node_modules** — one-shot build image; `node_modules` doesn't ship to runtime. Image size budget still enforced by `smoke_size.sh`.
   - **`webhook_configs` schema regression** — v0.32+ changelog reviewed: no breaking changes to the `webhook_configs` schema that homelab uses. The only breaking changes are `auto-gomemlimit` flag promotion (homelab doesn't use), `types` package removal (Go API, not config), `eventrecorder` config requiring `name` (homelab doesn't use eventrecorder).
   - **`alertmanager_notifications_failed_total` label values changed** (v0.34: HTTP 401/403 → `authError`, HTTP 429 → `rateLimited`, split from `clientError`) — verified via grep: homelab has NO prometheus rules or dashboards referencing this metric. No action required. Documented for future consumers in the plan doc.
   - **UI 404 at `/` after upgrade** — classic Elm UI is still present in v0.35 (changelog "ui: Serve the new Mantine UI at `/ui/` alongside the existing UI"). If a future upstream drops the Elm UI, our smoke will catch it and we'll either downgrade pin or follow upstream.

7. **Out of scope**:
   - Bumping to a pinned specific version. The point of this FG is to adopt `:latest` floating tag + daily cron auto-refresh, matching the pattern FG-050 already uses for cadvisor + ipmi-exporter + uptime-kuma.
   - Adopting Alertmanager v1.0 when it ships (future story — v1.0 may remove the Elm UI; separate migration).
   - Multi-arch (arm64). amd64-only, same as every other Forge image.
   - Clustering / HA (`--cluster.listen-address`). Homelab is single-instance; no change here.

8. **How we know it's done** — see Gherkin below.

9. **Capabilities delivered or extended**:
   - EXT `build.from-node-and-go-source` — alertmanager-scratch-trixie joins prometheus-scratch-trixie as a consumer of this dual-builder pattern.
   - EXT `build.ref-latest-release` — alertmanager (`actions/prometheus/alertmanager`) added as a consumer. Floats on upstream `:latest`.
   - EXT `image.alertmanager-routes-alerts` — existing CAP, no shape change; coverage re-verified against v0.35.
   - EXT `scan.nonzero-accepted` / `absence.os-cves` — baseline regenerated against the fresh source; waiver set reviewed.

## Gherkin acceptance

```
Scenario: alertmanager-scratch-trixie builds from source at upstream :latest
  Given a clean build cache
  When `scripts/build-image.sh alertmanager-scratch-trixie` runs with empty ALERTMANAGER_VERSION
  Then the ui-builder stage resolves the latest upstream release tag via GitHub API
  And the Mantine + Elm UIs both build without error
  And the Go builder links the binary with -tags netgo,builtinassets
  And the resulting image has both embedded UIs available at / and /ui/

Scenario: alertmanager HTTP API reports the resolved upstream version
  Given a running container built from the fresh image
  When GET /api/v2/status fires
  Then the JSON response contains versionInfo.version matching the resolved upstream tag
  And GET /-/healthy returns HTTP 200
  And GET /-/ready returns HTTP 200
  And GET / returns HTTP 200 with the classic UI HTML
  And GET /ui/ returns HTTP 200 with the Mantine UI HTML

Scenario: amtool responds to --version
  Given a running container
  When `docker exec <ctr> amtool --version` fires
  Then exit code is 0 and output contains the resolved upstream tag

Scenario: homelab compose config still works with the new image
  Given homelab's existing /etc/alertmanager/alertmanager.yml (Telegram webhook, 1 inhibit rule)
  When alertmanager starts with --config.file=/etc/alertmanager/alertmanager.yml
  Then config parses without error (no deprecated fields)
  And a test alert routes to the configured webhook_configs receiver
```
