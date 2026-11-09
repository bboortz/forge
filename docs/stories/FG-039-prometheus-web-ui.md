---
id: FG-039
slug: prometheus-web-ui
status: draft
owner: bboortz
created: 2026-11-09
---

# FG-039 — Fix prometheus-scratch-trixie web UI (missing /usr/share/prometheus/web/)

FG-035 shipped `prometheus-scratch-trixie:2.53` with the binary + `/etc/prometheus/{consoles,console_libraries}/` but **not** `/usr/share/prometheus/web/`. Prometheus 2.53 as packaged by Debian trixie requires the HTML base templates at `/usr/share/prometheus/web/templates/` even for the classic-UI redirect path at `/classic/graph`.

Reproducer (currently-shipped image on GHCR + `:latest`):
- `GET /` → 302 redirect to `/classic/graph`
- `GET /classic/graph` → 500 with log line: `error reading base template: open /usr/share/prometheus/web/templates/_base.html: no such file or directory`

FG-035's `/-/healthy` + `/-/ready` smokes passed because those endpoints don't touch the template engine. Operator-facing UI was untested — and broken.

FG-039 COPYs `/usr/share/prometheus/web/` (332 KB — templates + static assets) from the builder into the runtime overlay. Fixes both classic UI (`/classic/graph`) and the default React UI (which is `go:embed`'d into the binary since Prometheus 2.21 but still needs the static vendor CSS/JS on disk for some assets). Adds two new smoke tests so this regression can't recur.

## 9 canonical answers

1. **Who** — every `prometheus-scratch-trixie` operator who opens the Prometheus UI in a browser. Homelab monitoring stack specifically; secondary: any Forge consumer.

2. **When** — fires on every `GET /` or `/classic/graph` request. Pipeline: next 03:00 UTC cron after this lands on `main`.

3. **What success looks like**:
   - `curl http://localhost:9090/` returns HTTP 200 + HTML (React UI, `go:embed`'d).
   - `curl http://localhost:9090/classic/graph` returns HTTP 200 + HTML (classic UI, template-engine rendered).
   - No `error reading base template` lines in the container logs.
   - Image size stays within the 300 MB budget (adds ~332 KB, negligible).
   - `/-/healthy` + `/-/ready` + `promtool` smokes (from FG-035) continue to pass.

4. **Urgency** — correctness. Shipped `:latest` + `:2.53` tags today have an unusable web UI. Operator pulling the current digest and opening the dashboard hits a 500 error. Prometheus is observability infrastructure; a broken UI undermines its primary purpose.

5. **Happy path**:
   1. Forge PR merges FG-039 to `dev`.
   2. Promote to `main` via `release.yml`.
   3. Next 03:00 UTC cron publishes a new `:2.53` + `:latest` digest.
   4. Consumer `docker pull` + restart → UI works at `http://host:9090/`.

6. **Edge cases / failure modes**:
   - **Mixed-release path confusion** — upstream Prometheus tarball layout differs from Debian's (`prometheus-X.Y.Z.linux-amd64/consoles/` vs `/etc/prometheus/consoles/`). Debian's layout is authoritative for Forge; FG-039 keeps it (no CMD flag changes). The `/usr/share/prometheus/web/` path is baked into the binary at compile time via Debian's packaging.
   - **Image size** — 332 KB is 0.1% of the 300 MB budget. No budget bump needed.
   - **Future Debian minor bumps** may rearrange `/usr/share/prometheus/web/` layout. Mitigation: the new smoke tests probe the HTTP endpoints (what consumers see), not specific files — layout changes that preserve the UI contract pass; genuine breakage fails.

7. **Out of scope**:
   - Changing the default CMD flags (`--web.console.*` already correctly point at `/etc/prometheus/{consoles,console_libraries}/` per Debian layout).
   - Alternative console templates from `prometheus-example-consoles` (Debian ships placeholder dirs with only README.consoles; operators who want node-exporter dashboards bake a derived image).
   - Switching to upstream Prometheus tarball — Forge tracks Debian for CVE cadence; keeping the layout.

8. **How we know it's done** — see Gherkin below.

9. **Capabilities delivered or extended**:
   - EXT `image.prometheus-serves-metrics` — now includes functional web UI (classic + React), not just the `/-/healthy` + `/-/ready` + `/api/v1/*` endpoints.

## Gherkin acceptance

```
Scenario: React UI loads at /
  Given a running forge-local/prometheus-scratch-trixie:2.53
  When `curl -sf -o /dev/null -w "%{http_code}" http://localhost:9090/` runs
  Then the response is HTTP 200 (or 302 to the React UI — not to /classic/graph)
   And the final body contains HTML (either <!DOCTYPE or <html)

Scenario: Classic UI renders without template errors
  Given the same running container
  When `curl -sf http://localhost:9090/classic/graph` runs
  Then the response is HTTP 200
   And the body contains "<html"
   And the container logs do NOT contain "error reading base template"

Scenario: /usr/share/prometheus/web/templates/_base.html shipped
  Given the built image
  When the image contents are inspected via `docker save | tar tf`
  Then /usr/share/prometheus/web/templates/_base.html is present

Scenario: No regression against FG-035 smokes
  Given FG-035's existing smoke suite + acceptance test
  When re-run against the FG-039 image
  Then every assertion still passes (/-/healthy, /-/ready, promtool, SSL_CERT_FILE, /hc)

Scenario: Image size stays within budget
  Given the rebuilt image
  Then image size ≤ 300 MB
```

## References

- Plan: `docs/plan/FG-039-prometheus-web-ui-plan.md`
- Red test: `tests/acceptance/test_FG_039_prometheus-web-ui.sh`
- Capabilities: EXT `image.prometheus-serves-metrics`
- Predecessor: FG-035 (prometheus-scratch-trixie initial ship — missed this asset dir)
- Upstream: Debian trixie `prometheus 2.53.3+ds1-2` ships `/usr/share/prometheus/web/` with templates + static assets
