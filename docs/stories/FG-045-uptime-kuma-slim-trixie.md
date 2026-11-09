---
id: FG-045
slug: uptime-kuma-slim-trixie
status: shipped
owner: bboortz
created: 2026-11-09
---

# FG-045 — uptime-kuma-slim-trixie (built from Node source; no Chromium)

Homelab monitoring already covers host + container metrics (node-exporter, cadvisor, prometheus, alertmanager). The missing piece is **endpoint uptime** — synthetic HTTP/TCP/push monitoring with status pages. Uptime Kuma is the canonical open-source choice; upstream only ships a 1664 MB Alpine/musl image with Chromium bundled. This story ships `uptime-kuma-slim-trixie:latest` built from Node source on `node:22-trixie-slim`, deliberately dropping Chromium (and Playwright browsers) to produce a 589 MB slim variant for the HTTP/TCP/DNS/Push/Ping monitor fleet.

Tracks upstream's latest GitHub release via build-time resolution (FG-013 pattern) — no version pin in the image tag; operators who need reproducibility pin a digest.

## 9 canonical answers

1. **Who** — homelab operator (me) first, running the uptime dashboard for every exposed service in `~/git/homelab/`. Secondary: any Forge consumer wanting an Uptime Kuma that aligns with their Debian supply chain (not Alpine) and doesn't carry the ~200 MB Chromium baggage they won't use.

2. **When** — fires at every `docker compose up` on the homelab uptime host; monitors poll targets on their own configured cadence. Pipeline: next 03:00 UTC cron after this lands on `main`.

3. **What success looks like**:
   - `ghcr.io/bboortz/uptime-kuma-slim-trixie:latest` publishes daily with cosign + SBOM + scan attestations. Daily cron re-resolves upstream's latest GitHub release.
   - `docker run -d --name uptime-kuma -v uk-data:/app/data -p 3001:3001 ghcr.io/bboortz/uptime-kuma-slim-trixie:latest` boots.
   - `curl -sLf http://localhost:3001/` returns the SPA; `curl -sf http://localhost:3001/api/entry-page` returns JSON 200.
   - Browser points at `:3001` → setup wizard → operator configures DB/admin → dashboard loads.
   - Image size ≤ 700 MB (measured: 589 MB — vs upstream 1664 MB, 2.8× smaller).
   - Runs as nonroot uid 1000 (upstream `node` user).
   - Static-binary pattern not applicable (Node.js runtime); dynamic deps covered by `node:22-trixie-slim`.

4. **Urgency** — quality-of-life. No incident; filling the "endpoint uptime" gap in homelab monitoring.

5. **Happy path**:
   1. Forge daily cron re-resolves upstream latest (currently v2.5.9) and publishes `:latest` + `:latest-amd64`.
   2. Homelab compose adds `uptime-kuma` service pointing at `:latest` with a named volume on `/app/data`.
   3. `docker compose up -d` — container boots, listens on :3001, serves the setup wizard.
   4. Operator completes setup via browser; configures HTTP/TCP/Push monitors for each homelab service.
   5. Status page URL is reverse-proxied through the homelab's nginx-scratch-trixie ingress.

6. **Edge cases / failure modes**:
   - **Operator configures a browser-based (Playwright) monitor** — fails with uptime-kuma's own "Playwright not available" error. Documented (out-of-scope); operators who need this run upstream's 1664 MB image.
   - **First boot without volume** — SQLite DB stored in container's ephemeral `/app/data`; config lost on `docker rm`. Compose files MUST mount a named volume. Documented in adoption notes.
   - **302 redirect on GET /** — pre-setup, `/` redirects to `/setup-database`; post-setup, serves the SPA. HEALTHCHECK polls `/api/entry-page` which is always 200 either way.
   - **@louislam/sqlite3 native module** — ships amd64 prebuilt; CI rebuild never hits the compile path. Builder stage retains `make g++ python3` as safety-net for future dep updates.
   - **npm registry outage during daily cron** — publish fails for the day; `:latest` stays on yesterday's image. Operator doesn't notice; next successful cron resumes.

7. **Out of scope**:
   - **Chromium / Playwright browsers** (~200 MB savings). Explicitly documented in PROMISES.yaml's `absence.chromium` + CAP `image.uptime-kuma-no-chromium`. Operators who need browser monitors use upstream image OR a future `uptime-kuma-browser-slim-trixie` variant (track in IDEAS if an operator asks).
   - **Scratch runtime**. Node.js on scratch is possible but labor-intensive (ldd closure for Node + stdlib modules + libstdc++). Low payoff — slim is already 2.8× smaller than upstream.
   - **Multi-arch**. amd64-only matches every other Forge image.
   - **Upstream's v3.0 beta line** (Node >= 26.2.0 — too bleeding edge). Track v2.x stable until upstream declares v3 stable.
   - **Reproducible builds from a pinned release**. The `:latest` tag tracks upstream's moving target. Operators who need a specific build pin a digest.

8. **How we know it's done** — see Gherkin below.

9. **Capabilities delivered or extended**:
   - NEW `image.uptime-kuma-serves-monitoring` — serves the Uptime Kuma SPA + `/api/entry-page` on :3001 with first-run setup wizard, SQLite persistence under `/app/data`, and the full HTTP/TCP/DNS/Push/Ping monitor set.
   - NEW `image.uptime-kuma-no-chromium` — explicit documentation that this specific slim image does NOT bundle Chromium or Playwright browsers; browser-based synthetic monitors are unsupported. Prevents operator confusion + future audits from flagging the absence as a regression.
   - NEW `image.uptime-kuma-nonroot` — runs as uid 1000 (upstream's `node` user).
   - NEW `build.from-node-source` — multi-stage pattern for Node.js images not in Debian: `node:X-trixie-slim` builder → `npm ci` + `npm run build` + `npm prune --omit=dev` → `node:X-trixie-slim` runtime overlay. Sibling to FG-044's `build.from-go-source`. First consumer: uptime-kuma. Future consumers (grafana, n8n, Node-RED, ...) can share.
   - EXT `image.has-shell` — now lists cadvisor-slim-trixie + uptime-kuma-slim-trixie.

## Gherkin acceptance

```
Scenario: uptime-kuma-slim-trixie:latest publishes with the standard triple
  Given a successful build.yml publish cycle
  When the image resolves on GHCR
  Then cosign verify succeeds with the standard --certificate-identity
   And the SBOM lists uptime-kuma's resolved tag + the full npm module graph
   And the grype scan is attached (nonzero CRITICAL CVEs allowed via scan-baseline.json — slim contract)

Scenario: Node.js runtime is v22.x
  Given the built image
  When `docker run <image> --entrypoint=node --version` runs
  Then stdout starts with "v22."

Scenario: Uptime Kuma SPA serves on :3001
  Given a running forge-local/uptime-kuma-slim-trixie:latest
  When `curl -sLf http://localhost:3001/` runs
  Then the response contains "Uptime Kuma"

Scenario: /api/entry-page returns 200
  Given a running forge-local/uptime-kuma-slim-trixie:latest
  When `curl -sf http://localhost:3001/api/entry-page` runs
  Then the response is HTTP 200

Scenario: Chromium and Playwright browsers are NOT shipped
  Given the built image
  When common Chromium paths are probed
  Then /usr/bin/chromium, /usr/bin/chromium-browser, /usr/bin/chrome, /opt/google/chrome/chrome all do NOT exist
   And /ms-playwright does NOT exist
   And ~/.cache/ms-playwright does NOT exist

Scenario: /hc baked HEALTHCHECK polls /api/entry-page
  Given the built image
  When `docker inspect --format {{.Config.Healthcheck.Test}}` is read
  Then it contains "/hc" and "/api/entry-page"
   And a running container becomes `healthy` within 30s

Scenario: Runs as nonroot uid 1000 (upstream `node` user)
  Given the built image
  When `docker inspect --format {{.Config.User}}` is read
  Then it is "node"

Scenario: Image has shell (slim contract)
  Given the built image
  When `docker run --entrypoint=/bin/sh <image> -c 'echo ok'` runs
  Then stdout is "ok"

Scenario: Image size within budget
  Given the built image
  Then image size ≤ 700 MB

Scenario: Homelab adoption (operator-side, documented)
  Given a homelab host with Docker + compose
  When the operator adds an `uptime-kuma` service to compose pointing at `ghcr.io/bboortz/uptime-kuma-slim-trixie:latest` with a named volume on `/app/data`
   And `docker compose up -d uptime-kuma` succeeds
  Then browser navigation to `:3001` lands on the setup wizard
   And operator completes setup, configures HTTP/TCP monitors, and the dashboard populates on monitor scrape interval
```

## References

- Plan: `docs/plan/FG-045-uptime-kuma-slim-trixie-plan.md`
- Red test: `tests/acceptance/test_FG_045_uptime-kuma-slim-trixie.sh`
- Upstream: `github.com/louislam/uptime-kuma` (latest release resolved at build time; 2026-11-09 snapshot was v2.5.9)
- Related: FG-044 (cadvisor-slim-trixie — first `build.from-source` consumer; this is the Node analog)
- Future: `uptime-kuma-browser-slim-trixie` (sibling with Chromium + Playwright for browser-based monitors; deferred until an operator asks)
- FG-013 ref:latest pattern: daily cron re-resolves upstream latest
