---
id: FG-048
slug: prometheus-from-source-and-node-builder
status: ready
owner: bboortz
created: 2026-11-14
---

# FG-048 — prometheus-scratch-trixie from source + new forge-builder-node-trixie (Path B)

`prometheus-scratch-trixie:2.53` is currently the **only remaining Debian-packaged Go image** in the Forge fleet after FG-046 migrated 5 others off Debian's go1.24.x toolchain. It's also the only Go-source candidate FG-046 explicitly deferred because its UI build requires a Node.js pipeline — `web/ui/` contains a React SPA that `//go:embed`s into the binary via the `-tags builtinassets` build flag, and upstream's React toolchain needs `npm ci && npm run build` before `go build` succeeds.

FG-048 unblocks this by extracting **`forge-builder-node-trixie`** (Node.js equivalent of `forge-builder-go-trixie`) and migrating prometheus onto the dual-builder pattern that ipmi-exporter-scratch already uses (`forge-builder-go-trixie` + `forge-builder-trixie`). It also moves **uptime-kuma-slim-trixie**'s builder stage onto `forge-builder-node-trixie` so the new pre-builder has 2 consumers from day one — the promotion criterion IDEAS called out when reserving FG-048.

Scope (atomic, single PR):

1. **New `forge-builder-node-trixie:0.1`** — `FROM node:24-trixie-slim` (LTS) + apt-upgrade + CA certs + syft + git/curl/jq + make/g++/python3 (native-dep safety net) + **corepack enable** (auto-selects npm / pnpm / yarn based on each consumer's `packageManager` field). Published in the `publish-builders` CI tier alongside forge-builder-go-trixie.
2. **Rewrite `prometheus-scratch-trixie`** — dual-builder:
   - UI-build stage `FROM ghcr.io/bboortz/forge-builder-node-trixie` — clone upstream at pinned `PROMETHEUS_VERSION=v2.53.5` (LTS; v3 deferred to a later story), run upstream's `build_ui.sh` which handles the module builds + the classic React SPA build, emit `web/ui/static` tree.
   - Go-build stage `FROM ghcr.io/bboortz/forge-builder-go-trixie` — COPY the UI assets from the Node stage, then `go build -tags builtinassets` (upstream's documented tag for embedding UI into the binary).
   - Runtime stays `FROM scratch` composed from `scratch-base-trixie` + the single prometheus binary + console_libraries + consoles (text templates, separate from embedded UI assets).
   - **Simplification investigation in-PR**: once building from source with `-tags builtinassets`, verify whether the FG-039 `/usr/share/prometheus/web/` COPY block + FG-040's `cp -rL` symlink-dereferencing fix + the bootstrap4/jquery/d3/popper.js asset shipping are still necessary. The binary is expected to self-serve its UI; current filesystem overlay may become dead code.
3. **Migrate `uptime-kuma-slim-trixie`** — builder stage flips `FROM node:22-trixie-slim` upstream → `FROM ghcr.io/bboortz/forge-builder-node-trixie`. Runtime stage also bumps to `FROM node:24-trixie-slim` upstream (version alignment with builder). Existing FG-045 smoke suite is the oracle — no PROMISES changes expected.

Prometheus's tag stays `"2.53"` (patch floating within v2.53.x). v3 migration is NOT in scope — new UI stack (Mantine + pnpm), new storage format, operator-side breaking changes. Track v3 bump separately when there's operator demand.

## 9 canonical answers

1. **Who** — Forge maintainer (me) shipping the last Go-image from-source migration. Secondary: operators running `prometheus-scratch-trixie:2.53` gain a go1.27+ stdlib (eliminates the Debian-go1.24-lag CVE class) + a smaller image (embedded UI vs filesystem overlay). Tertiary: operators running uptime-kuma gain forge-signed builder provenance (vs upstream node:22 directly).

2. **When** — fires at FG-048's merge-to-dev. Daily cron picks up: `forge-builder-node-trixie:0.1` (publish-builders tier), new `prometheus-scratch-trixie:2.53` build from source, new `uptime-kuma-slim-trixie:latest` build with forge-signed builder.

3. **What success looks like**:
   - `ghcr.io/bboortz/forge-builder-node-trixie:0.1` publishes with cosign + SBOM + scan attestations. `docker run --rm --entrypoint=node <ref> --version` reports `v24.*`. `corepack enable` works; `pnpm --version` + `npm --version` + `yarn --version` all respond.
   - `ghcr.io/bboortz/prometheus-scratch-trixie:2.53` publishes with a from-source go1.27+ binary. `grype <image>` reports zero Debian-source CRITICALs AND zero stdlib go1.24.x CVEs (GO-2026-4337 TLS, GO-2026-6612 HTTP/2). Only GO-2026-6604 (Windows-only, waived) may remain if grype still flags it on go1.27.
   - `curl -sLf http://localhost:9090/` returns the SPA. `/classic/graph` renders without 500s (FG-040 regression stays green; embedded assets replace filesystem overlay). `/-/healthy` + `/-/ready` + `/metrics` + `/api/v1/query` all respond.
   - `ghcr.io/bboortz/uptime-kuma-slim-trixie:latest` publishes with a forge-builder-node-trixie-built artifact. Existing FG-045 smoke suite stays green. `docker run --entrypoint=node --version` reports `v24.*`.
   - Image sizes: prometheus-scratch ≤ 300 MB (likely smaller with embedded UI); uptime-kuma-slim ≤ 700 MB (same as FG-045 ceiling).
   - FG-050's alertmanager v0.35 bump is **unblocked** (forge-builder-node-trixie becomes the shared base for its own future bump).

4. **Urgency** — security-critical for prometheus (eliminates Debian-go1.24.x stdlib CVE lag). Quality-of-life for uptime-kuma. Not an emergency; no operator is actively blocked.

5. **Happy path**:
   1. Branch `feat/FG-048-prometheus-from-source-and-node-builder` from `dev`.
   2. Create `images/forge-builder-node-trixie/` (Dockerfile + image.yaml + PROMISES.yaml + tests/ + build-image.sh recursion).
   3. Rewrite `images/prometheus-scratch-trixie/Dockerfile` as dual-builder from source. Clone upstream v2.53.5. Run upstream's `scripts/build_ui.sh` in the Node stage (handles module + React build). Copy assets into Go stage. `go build -tags builtinassets`.
   4. Verify in-PR whether to delete the FG-039/FG-040 overlay blocks.
   5. Flip `images/uptime-kuma-slim-trixie/Dockerfile`: builder → forge-builder-node-trixie; runtime → node:24-trixie-slim upstream.
   6. Regenerate scan-baseline.json for prometheus-scratch + uptime-kuma.
   7. `make check` locally green; FG-048a/b/c red tests go green.
   8. PR to `dev` → CI full-check on affected matrix → auto-merge on green.

6. **Edge cases / failure modes**:
   - **Breaking change — prometheus `/classic/*` routes removed**: pre-FG-048 our image was built from Debian's `prometheus` apt package which carries a Debian-specific backwards-compat patch that keeps `/classic/*` routes alive. Upstream v2.53.x does NOT ship those routes (confirmed via `prom/prometheus:v2.53.5` upstream image also returns 404). FG-048 builds from upstream source → `/classic/graph`, `/classic/alerts` etc. all 404. React UI at `/`, `/graph`, `/alerts`, `/rules`, `/service-discovery` is the modern equivalent. **Homelab impact**: `scripts/monitoring/grafana-verify.py` currently probes `GET /classic/graph` — after FG-048 ships this check reports FAIL. One-line homelab-side fix: probe `/graph` instead. **Beaconry / scan APIs unchanged**; only the legacy `/classic/*` HTML surface is gone.
   - **uptime-kuma: `extra/healthcheck` binary absent in our image**: upstream ships a Go-compiled healthcheck at `/app/extra/healthcheck` via its `build-healthcheck.js` script; FG-045 doesn't run that step. Our image bakes `/hc -t 3 http://127.0.0.1:3001/api/entry-page` as the Docker HEALTHCHECK instead. When homelab migrates `docker/uptime-kuma/Dockerfile` from `louislam/uptime-kuma:2` → our image, its compose-level override `healthcheck.test: ["CMD-SHELL", "extra/healthcheck"]` must either be deleted (our baked HC takes over) or rewritten to `["CMD", "/hc", "-t", "3", "http://127.0.0.1:3001/api/entry-page"]`.
   - **corepack stale shim versions** — corepack ships default versions baked into Node; if prometheus's `packageManager` field pins a specific pnpm/npm version, corepack downloads it on first `pnpm`/`npm` invocation. Cached per-build; daily cron re-resolves. Fine.
   - **@louislam/sqlite3 native module on Node 24** — prebuilt binaries ship for amd64 + Node major LTS versions. Node 24 is LTS; prebuilds should exist. If not, falls back to source compile (needs make/g++/python3 which forge-builder-node-trixie provides).
   - **Prometheus v2.53.5 build fails on go1.27** — unlikely (v2.53 was built against go1.22 by upstream; go1.27 is stdlib-backwards-compatible). Verify in-PR via build attempt.
   - **FG-039/040 filesystem overlay still needed** — if `-tags builtinassets` doesn't fully embed what the binary serves at `/classic/graph`, we keep the overlay. Decision in-PR, not pre-commitment.
   - **Node 24 runtime behavior change for uptime-kuma** — Node 24 may have subtle runtime differences vs Node 22 (V8 flags, deprecations). FG-045's smoke suite catches breakage. If anything flakes, the FG-048c test fails in-PR and we revert uptime-kuma's runtime bump to node:22 (keep builder on Node 24 either way).
   - **GitHub API rate-limit on release-tag resolution** — forge-builder-node-trixie doesn't resolve latest-release itself (prometheus is pinned via `PROMETHEUS_VERSION=v2.53.5` ARG; uptime-kuma already has `UPTIME_KUMA_VERSION=` latest-resolve but that's per-image). Same cap-sharing as today.
   - **Docker Hub rate-limit on node:24-trixie-slim** — same per-IP 100/6h cap. Daily cron pulls it once; not a new risk vs node:22-trixie-slim.

7. **Out of scope**:
   - **Prometheus v3 bump** — Mantine UI + pnpm + storage format changes. Separate story when operators are ready.
   - **Alertmanager v0.35 bump** — FG-050 deferred this on the same UI-pipeline blocker. Follow-up chore once FG-048 lands; IDEAS "alertmanager v0.32+ bump" entry is the pointer.
   - **`node-slim-trixie` pre-builder** — lean runtime (not builder) Node base. Separate IDEAS entry; promotion trigger is a 2nd Node-at-runtime consumer. uptime-kuma stays on upstream `node:24-trixie-slim` for runtime until then.
   - **Changing prometheus's `tag`** — stays `"2.53"`. :latest floating is explicitly NOT a goal for prometheus (next upstream `latest` release is v3, which would silently jump majors).
   - **Multi-arch arm64** — amd64-only matches every other Forge image.

8. **How we know it's done** — see Gherkin below.

9. **Capabilities delivered or extended**:
   - NEW `build.shared-node-builder` — `ghcr.io/bboortz/forge-builder-node-trixie:0.1` is a published builder-base mirroring FG-046's `build.shared-go-builder` shape but for Node builds. `FROM node:X-trixie-slim` + apt-upgrade + CA + syft + git/curl/jq + make/g++/python3 + corepack. Daily cron rebuilds first so Node-stdlib + npm/pnpm/yarn security fixes propagate within 24h.
   - NEW `build.from-node-source` is extended (not reinvented) — FG-045 delivered the pattern inline; FG-048 extracts the Node builder into a reusable image. Prometheus-scratch-trixie + uptime-kuma-slim-trixie both become consumers.
   - EXT `build.from-go-source` — add prometheus-scratch-trixie as the 7th consumer (dual-builder pattern like ipmi-exporter-scratch).
   - EXT `image.prometheus-scratch-serves-metrics` (or similar; see CAP file) — now built from source, binary links against go1.27+ stdlib, UI embedded via `-tags builtinassets`.

## Gherkin acceptance

```
Scenario: forge-builder-node-trixie:0.1 publishes with the standard triple
  Given a successful build.yml publish cycle
  When ghcr.io/bboortz/forge-builder-node-trixie:0.1 resolves on GHCR
  Then cosign verify succeeds with the standard --certificate-identity
   And the SBOM lists node + apt packages + resolved versions
   And the grype scan is attached

Scenario: Node 24 LTS + corepack provides npm / pnpm / yarn
  Given the built forge-builder-node-trixie image
  When `docker run --rm --entrypoint=node <image> --version` runs
  Then stdout starts with "v24."
   And `corepack enable` succeeds inside the container
   And `pnpm --version` + `npm --version` + `yarn --version` each exit 0

Scenario: prometheus-scratch-trixie builds from source with embedded UI
  Given the FG-048 prometheus Dockerfile
  When `bash scripts/build-image.sh prometheus-scratch-trixie` runs
  Then the UI-builder stage clones prometheus v2.53.5 + runs build_ui.sh
   And the Go-builder stage compiles with `-tags builtinassets` under go1.27+ stdlib
   And the resulting binary serves /classic/graph without the filesystem overlay
   And `docker inspect <image> --format '{{.Size}}'` is ≤ 300 MB

Scenario: Prometheus Go-stdlib CVEs eliminated
  Given the new prometheus-scratch-trixie build
  When grype scans the embedded SBOM
  Then zero stdlib CRITICALs attributed to go1.24.x are reported
   And only the Windows-only GO-2026-6604 waiver (if still flagged against go1.27) remains in PROMISES

Scenario: Prometheus HTTP surface unchanged
  Given a running prometheus-scratch-trixie:2.53
  When probed with curl
  Then GET / returns the SPA (status 200)
   And GET /-/healthy + GET /-/ready + GET /metrics return 200
   And GET /api/v1/query?query=up returns valid JSON

Scenario: uptime-kuma builder migrates to forge-builder-node-trixie (Node 24)
  Given the FG-048 uptime-kuma Dockerfile
  When the builder stage is read
  Then its FROM line references forge-builder-node-trixie (not node:22-trixie-slim)
   And the runtime stage's NODE_BASE is `node:24-trixie-slim`
   And the existing FG-045 smoke suite still passes against the rebuilt image

Scenario: FG-050's alertmanager deferral is now unblockable
  Given forge-builder-node-trixie published
  When a future PR adds a `FROM forge-builder-node-trixie AS ui-builder` stage to alertmanager-scratch-trixie
  Then the build chain for alertmanager v0.35 can succeed
   And the IDEAS "alertmanager v0.32+ bump" entry becomes actionable
```

## References

- Plan: `docs/plan/FG-048-prometheus-from-source-and-node-builder-plan.md`
- Red tests (split per FG-046 pattern):
  - `tests/acceptance/test_FG_048a_forge-builder-node-trixie.sh`
  - `tests/acceptance/test_FG_048b_prometheus-from-source.sh`
  - `tests/acceptance/test_FG_048c_uptime-kuma-node24-migration.sh`
- Precedents: FG-046 (forge-builder-go-trixie + 5-image migration), FG-045 (first from-node-source consumer, inline), FG-025 (forge-builder-trixie as the shape to mirror).
- Upstream: [prometheus/prometheus@v2.53.5](https://github.com/prometheus/prometheus/releases/tag/v2.53.5), [louislam/uptime-kuma](https://github.com/louislam/uptime-kuma).
- IDEAS entries this ships: `prometheus-scratch-trixie from-Go-source migration` (Path B); the separate `forge-builder-node-trixie` entry is superseded by FG-048.
