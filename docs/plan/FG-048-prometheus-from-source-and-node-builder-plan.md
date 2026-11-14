# FG-048 — Plan: prometheus-from-source + forge-builder-node-trixie (Path B)

**Story**: [`docs/stories/FG-048-prometheus-from-source-and-node-builder.md`](../stories/FG-048-prometheus-from-source-and-node-builder.md)
**Status**: ready → in-progress → shipped
**Branch**: `feat/FG-048-prometheus-from-source-and-node-builder`

## Design delta

### `images/forge-builder-node-trixie/` (new)

- `image.yaml`: `tag: "0.1"`, `platforms: [linux/amd64]`, no `depends_on` (externally-maintained-runtime exemption: FROMs `node:24-trixie-slim` upstream). Same shape as `forge-builder-go-trixie`.
- `Dockerfile`:
  - Stage 0: `FROM ${SYFT_SRC} AS syft-src` (Docker Hub, same as forge-builder-go-trixie).
  - Stage 1: `FROM node:24-trixie-slim` — apt-upgrade + CA + `git curl jq make g++ python3 dumb-init`. `COPY --from=syft-src /syft /usr/local/bin/syft`. `corepack enable` (makes pnpm + yarn available without npm install; corepack ships with Node 16+).
  - Smoke the toolchain: `node --version`, `syft version`, `pnpm --version`, `yarn --version` all at build time via a final RUN so broken images fail fast.
- `PROMISES.yaml`: `files.node-toolchain` (Node ≥ 24), `files.syft-binary`, `files.ca-certificates`, `files.release-resolve-tools` (git + curl + jq), `files.native-dep-toolchain` (make + g++ + python3), `files.corepack-enabled` (pnpm + yarn available), `apt.freshly-upgraded`, `apt.no-cache`.
- `tests/`: `smoke_node_version.sh`, `smoke_corepack_wraps.sh` (pnpm + npm + yarn all report versions), `smoke_syft_available.sh`, `smoke_size.sh`.

### `images/prometheus-scratch-trixie/Dockerfile` (rewrite)

Three-stage dual-builder, mirroring ipmi-exporter-scratch's Go + C pattern:

- Stage 0: `FROM ${SCRATCH_BASE_REF} AS scratch_base` (unchanged).
- Stage 0b: `FROM ${HC_REF} AS hc` (FG-031).
- Stage 1 (UI builder): `FROM ${FORGE_BUILDER_NODE_REF} AS ui-builder` — clone upstream `prometheus/prometheus` at `PROMETHEUS_VERSION=v2.53.5`, run `scripts/build_ui.sh`. The script does: build 2 npm workspaces (`lezer-promql`, `codemirror-promql`) in order, then `cd react-app && npm install && npm run build`. Output: `web/ui/static/react/` populated with compiled SPA assets. emit syft SBOM against `/src`.
- Stage 2 (Go builder): `FROM ${FORGE_BUILDER_GO_REF} AS builder` — `COPY --from=ui-builder /src /src`, then `go build -tags builtinassets` with upstream's LDFLAGS (version/revision/branch/buildUser/buildDate/goVersion into `github.com/prometheus/common/version`). Output: `/out/usr/bin/prometheus` + `/out/usr/bin/promtool`.
- Stage 3 (runtime scratch): baseline + overlay. Overlay: binaries (`/usr/bin/prometheus` + `promtool`) + console_libraries + consoles + /etc/prometheus/prometheus.yml (minimal self-scrape). **FG-039/FG-040 overlays**: investigate in-PR; delete if the binary serves `/graph` + `/classic/graph` cleanly without them.

ARGs:
```
ARG SCRATCH_BASE_REF=ghcr.io/bboortz/scratch-base-trixie:latest
ARG FORGE_BUILDER_REF=ghcr.io/bboortz/forge-builder-trixie:latest  # legacy ref, may be removable
ARG FORGE_BUILDER_NODE_REF=ghcr.io/bboortz/forge-builder-node-trixie:latest
ARG FORGE_BUILDER_GO_REF=ghcr.io/bboortz/forge-builder-go-trixie:latest
ARG HC_REF=ghcr.io/bboortz/hc:0.1.0
ARG PROMETHEUS_VERSION=v2.53.5
```

### `images/prometheus-scratch-trixie/image.yaml` (unchanged)

`tag: "2.53"` stays. Daily cron picks up patch bumps via `PROMETHEUS_VERSION` ARG edits.

### `images/prometheus-scratch-trixie/PROMISES.yaml` (minor update)

- `runtime.prometheus-binary` description: update version banner from `2.53.3` (current) → `2.53.5` (new pinned). Classic `--allow-modify` case.
- `absence.os-cves.waivers`: keep `GO-2026-6604` (Windows-only, may still be flagged against go1.27 — verify in scan). Clear nothing else because the existing waiver list is minimal and other Go-stdlib CVEs weren't in waivers anyway.

### `images/uptime-kuma-slim-trixie/Dockerfile` (migration)

Two edits:
1. `ARG NODE_BASE=node:22-trixie-slim` → `ARG NODE_BASE=node:24-trixie-slim`. The runtime stage FROMs `${NODE_BASE}` (per existing shape).
2. Builder stage changes from `FROM ${NODE_BASE} AS builder` → `FROM ${FORGE_BUILDER_NODE_REF} AS builder`. Add `ARG FORGE_BUILDER_NODE_REF=ghcr.io/bboortz/forge-builder-node-trixie:latest`.

Builder-stage apt-install line (`git curl jq ca-certificates make g++ python3 dumb-init`) becomes partially redundant — forge-builder-node-trixie already ships all of those. Can simplify to: no apt-install needed for the builder; still install `ca-certificates dumb-init` in the runtime stage since those are runtime deps, not build-time. **Verify in-PR** which packages uptime-kuma's builder actually consumes beyond what the base provides.

### `scripts/build-image.sh` (new auto-build recursion)

Mirror the forge-builder-go-trixie block (line 63-72):
```bash
_FORGE_BUILDER_NODE_DIR="${ROOT}/images/forge-builder-node-trixie"
if [[ -d "${_FORGE_BUILDER_NODE_DIR}" && -f "${SRC}/Dockerfile" ]] \
   && grep -q "FORGE_BUILDER_NODE_REF" "${SRC}/Dockerfile"; then
  echo "→ builder-stage dependency: forge-builder-node-trixie"
  REGISTRY="${REGISTRY}" "${BASH_SOURCE[0]}" forge-builder-node-trixie
fi
```

And the ref-resolution block (mirror line 142-152 for FORGE_BUILDER_GO_REF) to prefer the local forge-local tag when present.

### `.github/workflows/build.yml` (forge-builder-node-trixie in builders tier)

`scripts/discover-images.sh --builders` must include `forge-builder-node-trixie`. Add it to the `_FORGE_BUILDERS` array (if the array exists; verify script shape). CI matrix cell for the builders tier ensures forge-builder-node-trixie builds before its consumers.

### `docs/CAPABILITIES.md` (new + ext)

- NEW `build.shared-node-builder` — sibling of `build.shared-go-builder`. Pattern identical. Consumers: prometheus-scratch-trixie (dual with Go), uptime-kuma-slim-trixie.
- EXT `build.from-go-source` — add prometheus-scratch-trixie as the 7th consumer.
- EXT `build.from-node-source` — now extracted into a shared base; FG-048 formalizes.
- EXT `image.prometheus-scratch-serves-metrics` (if the CAP exists; verify name) — now from-source build.

### `docs/stories/INDEX.md` + `docs/plan/IDEAS.md`

- INDEX: add FG-048 row (ready → shipped post-merge).
- IDEAS: strike the `prometheus-scratch-trixie from-Go-source migration` entry (shipped via FG-048). Strike the `forge-builder-node-trixie` entry (shipped via FG-048). The `alertmanager v0.32+ bump` entry stays (unblocked; actionable follow-up).

## Alternatives rejected

- **Prometheus v3.16.0** — current stable. User chose v2.53.5 LTS. v3 bump is a bigger story (Mantine UI, pnpm, TSDB storage changes, operator-side breaking changes).
- **node:22-trixie-slim** (per IDEAS entry) — user chose node:24-trixie-slim (current LTS, forward-looking, satisfies prometheus v3 whenever that's promoted).
- **npm only** — user chose corepack. Zero extra apt; auto-selects based on `packageManager` field in package.json.
- **Single fat builder with Go + Node** — rejected. Breaks one-tool-per-builder principle. forge-builder-node-trixie stays lean.
- **Pre-built UI assets from upstream GitHub release** — defeats the from-source scan-surface story. Rejected.
- **Skip uptime-kuma migration this PR** — user chose to migrate (builder + runtime both to Node 24). Keeps the 2-consumer promotion criterion satisfied from day one.
- **Keep FG-039/040 filesystem overlay as belt-and-suspenders** — user chose investigate in-PR. If the embedded assets suffice, delete; if not, keep.

## Breaking changes

**For Forge image consumers**: One operator-facing HTTP surface change (not an API-contract breakage); otherwise additive.

- `prometheus-scratch-trixie:2.53` continues to serve the same **API** surface (`/-/healthy`, `/-/ready`, `/metrics`, `/api/v1/*`). Operators pinning `:2.53` get patch bumps (v2.53.3 → v2.53.5) on the next cron, same as today. Binary is now from-source with go1.27+ stdlib instead of Debian-packaged with go1.24.x — observable via `prometheus --version` output.
- **`/classic/*` HTML routes removed**: our pre-FG-048 image inherited a Debian-specific patch that kept `/classic/graph`, `/classic/alerts`, etc. alive. Upstream v2.53.x removed those routes (confirmed: upstream `prom/prometheus:v2.53.5` also returns 404). FG-048 matches upstream. **Operator action**: migrate `/classic/*` bookmarks + scripts to React routes at `/`, `/graph`, `/alerts`, `/rules`, `/service-discovery`.
- **Homelab compat note**: `scripts/monitoring/grafana-verify.py` in `~/git/homelab` probes `GET /classic/graph` today — needs a one-line edit to probe `/graph` instead. Scan + metrics endpoints (what Prometheus itself + Beaconry use) are unaffected. All 4 prometheus-forge test assertions in `tests/test_monitoring_forge.py` remain green.
- `uptime-kuma-slim-trixie:latest` continues to serve the same HTTP surface. Runtime bumps from Node 22 → Node 24; operators may observe subtle Node-version behavior differences (deprecations, V8 flags). FG-045's smoke suite is the oracle for regressions.
- **Homelab uptime-kuma migration readiness**: homelab's `docker/uptime-kuma/Dockerfile` today FROMs `louislam/uptime-kuma:2` directly, but a prospective migration onto `ghcr.io/bboortz/uptime-kuma-slim-trixie:latest` is planned. Two operator-side deltas between upstream and our image when that migration happens:
  1. **No `extra/healthcheck` binary** — upstream ships a Go-compiled healthcheck binary at `/app/extra/healthcheck`; we don't run upstream's `build-healthcheck.js` step. Homelab's compose currently has `healthcheck.test: ["CMD-SHELL", "extra/healthcheck"]` — that line will error on our image (file not found). Fix: either delete the compose-level healthcheck (our baked HEALTHCHECK takes over: `/hc -t 3 http://127.0.0.1:3001/api/entry-page`), or match it explicitly: `["CMD", "/hc", "-t", "3", "http://127.0.0.1:3001/api/entry-page"]`.
  2. **No Chromium / Playwright** — FG-045 deliberately drops both. If homelab plans browser-based synthetic monitors, our image won't work — it needs upstream or a future `uptime-kuma-browser-slim-trixie` (IDEAS entry). Homelab's current monitor set (HTTP/TCP/DNS/Push/Ping per `docker/uptime-kuma/README.md`) is compatible — none of those use browser automation.

**For scanners / auditors**: positive change. Prometheus binary now ships go1.27+ stdlib → Debian-go1.24.x CVE class (GO-2025-3563, GO-2026-4337, GO-2026-6612) stops appearing on scan reports. Only GO-2026-6604 (Windows-only, documented waiver) may remain.

## Merge plan

All blocking gates per `memory/workflow.md`:

- hadolint + shellcheck + yamllint + actionlint clean.
- `make verify-sid-pins` — N/A (no sid pins introduced).
- `make verify-traceability` — new CAP registered + bidirectional test links.
- `make verify-contracts` — PROMISES changes validate; `--allow-modify` in commit msg for the prometheus version-banner description change.
- `make verify-no-upstream-drift` — should still report 2 (debian:trixie-slim + python:3.14-slim-trixie via pre-builders). node:24-trixie-slim is not under the single-consumer rule because `forge-builder-node-trixie` is a dedicated-toolchain builder (same exemption as `forge-builder-go-trixie` per docker-standard.md).
- `make test-acceptance` — all 3 new FG-048 red tests go green.
- `make build` + `make scan` + `make verify` per affected image.
- Scan-regression gate: regenerate `scan-baseline.json` for prometheus-scratch + uptime-kuma.
- Image sizes within budgets (prometheus ≤ 300 MB; uptime-kuma ≤ 700 MB).

## Rollout plan

1. Land FG-048 on `feat/FG-048-...` branch.
2. Autonomous merge on green CI per workflow.md step 8.
3. User triggers `release.yml` → promotes dev → main.
4. Daily cron publishes:
   - `forge-builder-node-trixie:0.1` + `:latest` + `-amd64` variants (builders tier).
   - `prometheus-scratch-trixie:2.53` rebuilt from source (daily cron also re-resolves PROMETHEUS_VERSION if we switch that to latest-release later; for v2.53.x stays pinned).
   - `uptime-kuma-slim-trixie:latest` rebuilt with forge-signed builder.
5. Beaconry / grype scans of prometheus-scratch now return go1.27+ stdlib; Debian-go1.24.x CVEs stop appearing. FG-050's alertmanager v0.32+ bump IDEAS entry becomes actionable; can ship as a chore after FG-048.

## Shipping evidence

| Item | Pointer | Status |
|------|---------|--------|
| Story drafted | `docs/stories/FG-048-prometheus-from-source-and-node-builder.md` | ✅ |
| Plan drafted | `docs/plan/FG-048-prometheus-from-source-and-node-builder-plan.md` | ✅ |
| Red test 048a (forge-builder-node) | `tests/acceptance/test_FG_048a_forge-builder-node-trixie.sh` | ⚠️ (create next) |
| Red test 048b (prometheus from-source) | `tests/acceptance/test_FG_048b_prometheus-from-source.sh` | ⚠️ |
| Red test 048c (uptime-kuma Node 24 migration) | `tests/acceptance/test_FG_048c_uptime-kuma-node24-migration.sh` | ⚠️ |
| INDEX.md + IDEAS.md updated | `docs/stories/INDEX.md` + `docs/plan/IDEAS.md` | ⚠️ |
| New forge-builder-node-trixie image | `images/forge-builder-node-trixie/` | ⚠️ |
| Prometheus Dockerfile rewrite | `images/prometheus-scratch-trixie/Dockerfile` | ⚠️ |
| uptime-kuma Dockerfile migration | `images/uptime-kuma-slim-trixie/Dockerfile` | ⚠️ |
| scripts/build-image.sh recursion | `scripts/build-image.sh` | ⚠️ |
| build.yml publish-builders tier | `.github/workflows/build.yml` | ⚠️ |
| CAPs registered | `docs/CAPABILITIES.md` | ⚠️ |
| Scan-baselines regenerated | prometheus-scratch + uptime-kuma | ⚠️ |
| All 3 FG-048 cells + full test suite green | CI on PR | ⚠️ |
