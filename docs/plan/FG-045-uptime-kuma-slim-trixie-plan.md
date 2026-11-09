# FG-045 — Plan: uptime-kuma-slim-trixie

**Story**: [`docs/stories/FG-045-uptime-kuma-slim-trixie.md`](../stories/FG-045-uptime-kuma-slim-trixie.md)
**Status**: draft
**Branch**: `feat/FG-045-uptime-kuma-slim-trixie`

## Design delta

### `images/uptime-kuma-slim-trixie/` (new)

- `image.yaml`: `tag: "latest"` (no version pin; daily cron re-resolves upstream GitHub latest release — FG-013 pattern), platforms `[linux/amd64]`, no `depends_on` (slim, standalone).
- `Dockerfile`: multi-stage.
  - Stage 0: `FROM ghcr.io/bboortz/hc:0.1.0 AS hc` (for the FG-031 /hc binary).
  - Stage 1: `FROM docker.io/anchore/syft:latest AS syft-src` (syft binary — FG-025 convention).
  - Stage 2 (builder): `FROM node:22-trixie-slim AS builder` — apt-upgrade + git + curl + jq + make/g++/python3 (safety net for native-dep rebuild), resolve upstream latest release tag via GitHub API, shallow-clone, `npm ci` + `npm run build` (vite SPA compile) + `npm prune --omit=dev` (drops dev deps post-build), emit SBOM against source tree.
  - Stage 3 (runtime): `FROM node:22-trixie-slim` — apt-upgrade + `ca-certificates` + `dumb-init` (upstream convention for PID 1 signal forwarding), `COPY --from=builder /out/app /app` + `/sbom.json` + `/hc`, `USER node`, `HEALTHCHECK /hc http://127.0.0.1:3001/api/entry-page`, entrypoint `/usr/bin/dumb-init --`, cmd `node server/server.js`.
- `PROMISES.yaml`: 8 promises (`runtime.uptime-kuma-app`, `runtime.node-runtime`, `runtime.hc-binary`, `presence.shell`, `absence.chromium`, `runtime.nonroot-node`, `shape.size-budget`, `scan.nonzero-accepted`). `version: "0.1"`.
- **No `EXPECTATIONS.yaml`**: slim variant with no `scratch-base-trixie` dependency.
- `scan-baseline.json`: nonzero CRITICAL list (GHSA-23hp-3jrh-7fpw for tar, GHSA-xq3m-2v4x-88gg for protobufjs — both npm-tree) — regenerated per-build.

### Why build from source

Uptime Kuma is **not in Debian trixie**. Upstream only ships `louislam/uptime-kuma:*`, a 1664 MB Debian 12 bookworm image with Chromium bundled. Options evaluated (full investigation in session transcript):

| Option | Shape | Decision |
|---|---|---|
| A. Build from Node source, no Chromium | `node:22-trixie-slim` → 589 MB | **Chosen** — Debian ecosystem + 2.8× smaller + homelab doesn't need browser monitors |
| B. Mirror upstream Alpine/Chromium | `FROM louislam/uptime-kuma` + re-sign | Rejected — Alpine under `-trixie` name is misleading + no own supply-chain |
| C. Build with Chromium | A + apt install chromium | Deferred — 200 MB bloat for an optional feature; sibling variant later if asked |

### Why :latest (no version pin)

Uptime Kuma releases on a stable cadence (v2.5.9 was Oct 31, 2026). Unlike cadvisor (FG-044's `:0.60.6`), there's no compelling reason for consumers to pin a specific upstream version — the app is self-contained with its own SQLite state, no public API contract is tied to a version. `tag: "latest"` + daily re-resolve lets the fleet stay current. Operators who need reproducibility pin a digest.

### Why NOT introduce `forge-builder-node-trixie` yet

Same argument as FG-044's forge-builder-go-trixie: single consumer today. If a 2nd Node-source image lands (grafana, n8n, Node-RED), extract the shared builder. Tracked in IDEAS.md.

### Why drop Chromium

- **~200 MB savings** on a 589 MB image (26% reduction)
- **Homelab use case**: HTTP/TCP/Push/DNS/Ping monitors. Browser-based synthetic monitoring is nice-to-have not must-have.
- **Explicit opt-in** via future `uptime-kuma-browser-slim-trixie` sibling image (deferred until an operator asks)
- **Smoke test guards** the absence (`smoke_no_chromium.sh`) so a future apt install chromium slip can't accidentally re-introduce it

### Why :latest resolve at build time (not clone master)

- **master is beta**: v3.0.0-beta.0 requires Node >= 26.2.0 (bleeding edge).
- **Latest release tag**: proven stable, covered by upstream release notes.
- Pattern: `curl -fsSL https://api.github.com/repos/louislam/uptime-kuma/releases/latest | jq -r .tag_name`
- `--build-arg UPTIME_KUMA_VERSION=2.5.9` overrides for reproducible local builds.

### Runtime shape

- **User**: `node` (uid 1000) — upstream convention; no root needed (uptime-kuma is a pure userspace Node app).
- **Port**: 3001 (upstream default).
- **Healthcheck target**: `/api/entry-page` (always-200 Express handler) — NOT `/` which 302-redirects to `/setup-database` pre-config.
- **Entrypoint**: `/usr/bin/dumb-init -- node server/server.js` (upstream convention; proper PID 1 signal forwarding).
- **VOLUME**: `/app/data` — consumers mount a named volume for SQLite + config persistence.
- **No config file**: default flags; app configures via first-run setup wizard.

### Smoke tests

7 scripts under `images/uptime-kuma-slim-trixie/tests/`:

- `smoke_serves_200.sh` — `scripts/smoke-server.sh` boots container on :3001; `curl -sLf /` returns HTML containing "Uptime Kuma"; ready-probe uses `/api/entry-page`.
- `smoke_node_version.sh` — `docker run --entrypoint=node --version` returns v22.x.
- `smoke_no_chromium.sh` — standard Chromium paths + `/ms-playwright` absent (regression guard).
- `smoke_user_node.sh` — `docker inspect Config.User` is `node` / `1000`.
- `smoke_hc_healthcheck.sh` — HEALTHCHECK baked + healthy within 30s + closed-port guard-rail.
- `smoke_has_shell.sh` — `/bin/sh` present (slim contract).
- `smoke_size.sh` — ≤ 700 MB absolute ceiling.

### Red acceptance test — `tests/acceptance/test_FG_045_uptime-kuma-slim-trixie.sh`

4 sections:

1. **Required files** — Dockerfile, image.yaml, PROMISES.yaml, scan-baseline.json, 7 smokes all present + executable.
2. **Build** — `bash scripts/build-image.sh uptime-kuma-slim-trixie` succeeds.
3. **Smoke suite** — all 7 smokes green.
4. **image.yaml invariants** — tag=latest, platforms=[linux/amd64], no `depends_on`.

### `docs/CAPABILITIES.md`

- NEW `image.uptime-kuma-serves-monitoring` — SPA on :3001 + /api/entry-page health; HTTP/TCP/DNS/Push/Ping monitors.
- NEW `image.uptime-kuma-no-chromium` — Chromium / Playwright browsers NOT bundled; browser-based synthetic monitors unsupported.
- NEW `image.uptime-kuma-nonroot` — runs as uid 1000 (upstream `node`).
- NEW `build.from-node-source` — multi-stage Node builder → slim runtime pattern; sibling of `build.from-go-source`.
- EXT `image.has-shell` — now lists uptime-kuma-slim-trixie.

### `docs/stories/INDEX.md`

New row for FG-045.

### `docs/plan/IDEAS.md`

Add entry: `forge-builder-node-trixie` — same promotion trigger as forge-builder-go-trixie.

## Alternatives rejected

- **Mirror upstream `louislam/uptime-kuma`** — ships Alpine under `-slim-trixie` name; no supply-chain ownership.
- **Include Chromium** — +200 MB for optional browser monitors homelab doesn't use. Sibling image if asked.
- **Scratch runtime** — Node.js ldd closure is ~20 libs + stdlib `.node` modules; high effort, marginal payoff vs. slim.
- **Pin to v2.5.9** — user explicitly asked for `:latest`.
- **Use upstream's /app/extra/healthcheck binary** — upstream doesn't ship the binary in the released source; it's compiled in their private `louislam/uptime-kuma:builder-go` base. `/hc` + `/api/entry-page` is simpler.
- **Root user** — no technical need; upstream's own convention is `node` user.

## Breaking changes

None.
- New image, no existing consumers.
- No API changes to other images.

## Merge plan

- All blocking gates pass.
- FG-045 acceptance test green (4 sections, 7 smokes).
- `scan-baseline.json` regenerated with current CRITICALs (2 expected: tar + protobufjs from npm tree).
- `make test-fast` green.
- Pre-push `check-smart-strict` green.

## Rollout plan

1. Land FG-045 on `dev` via PR → autonomous merge on green CI.
2. Promote to `main` via `release.yml` (user triggers).
3. Daily cron publishes `:latest` + `:latest-amd64` (re-resolves upstream latest).
4. Operator adds `uptime-kuma` service to homelab compose with named volume on `/app/data`.
5. Browser setup → monitors configured → status page reverse-proxied through homelab nginx-scratch-trixie.

## Shipping evidence

| Item | Pointer | Status |
|------|---------|--------|
| Scenario: publishes with triple | `tests/acceptance/test_FG_045_...sh` § 1 + § 2 | ⏳ |
| Scenario: Node.js runtime v22.x | § 3 + smoke_node_version.sh | ⏳ |
| Scenario: SPA serves on :3001 | § 3 + smoke_serves_200.sh | ⏳ |
| Scenario: /api/entry-page 200 | § 3 + smoke_serves_200.sh (ready probe) | ⏳ |
| Scenario: no Chromium | § 3 + smoke_no_chromium.sh | ⏳ |
| Scenario: /hc HEALTHCHECK | § 3 + smoke_hc_healthcheck.sh | ⏳ |
| Scenario: nonroot `node` user | § 3 + smoke_user_node.sh | ⏳ |
| Scenario: has shell | § 3 + smoke_has_shell.sh | ⏳ |
| Scenario: size ≤ 700 MB | § 3 + smoke_size.sh | ⏳ |
| Scenario: homelab adoption | operator-side; documented in story § 9 happy path | ⏳ |
| NEW `image.uptime-kuma-serves-monitoring` | `docs/CAPABILITIES.md` entry | ⏳ |
| NEW `image.uptime-kuma-no-chromium` | `docs/CAPABILITIES.md` entry | ⏳ |
| NEW `image.uptime-kuma-nonroot` | `docs/CAPABILITIES.md` entry | ⏳ |
| NEW `build.from-node-source` | `docs/CAPABILITIES.md` entry | ⏳ |
| EXT `image.has-shell` → uptime-kuma | `docs/CAPABILITIES.md` extension | ⏳ |
