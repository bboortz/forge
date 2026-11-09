---
id: FG-040
slug: prometheus-classic-ui-assets
status: draft
owner: bboortz
created: 2026-11-09
---

# FG-040 — Fix prometheus-scratch-trixie classic UI static asset 404s

FG-039 fixed the `/usr/share/prometheus/web/templates/_base.html` miss and got the classic UI rendering HTML — but **25 of its 34 assets still 404**. Evidence from a captured HAR of `GET /classic/graph` against the shipped `prometheus-scratch-trixie:2.53`:

| HTTP | Count | Pattern |
|---|---|---|
| 200 | 9 | real files: `css/*.css`, `img/favicon.ico`, `js/graph/index.js`, `vendor/{bootstrap3-typeahead,bootstrap4-glyphicons,fuzzy,js}/*` |
| 404 | 25 | symlink targets: `jquery/`, `popper.js/`, `bootstrap4/{js,css}`, `rickshaw/`, `d3/`, `moment/`, `moment-timezone/`, `mustache/`, `eonasdan-bootstrap-datetimepicker/{js,css}` |

Debian packages Prometheus with its third-party JS/CSS libs factored out as `libjs-*` apt packages living under `/usr/share/javascript/`, with relative symlinks from `/usr/share/prometheus/web/static/<lib> → ../../../javascript/<lib>`. FG-039's `cp -r` preserved the symlinks but never copied the targets — the overlay ships dangling symlinks, HTTP serves 404.

FG-040 switches that one `cp` to `cp -rL` (dereference symlinks). Inlines the Debian JS libs into the overlay as real files. Adds ~10 MB; stays well under the 300 MB ceiling. Classic UI goes from "HTML renders but no CSS/JS" to fully styled & functional.

## 9 canonical answers

1. **Who** — every operator who clicks "Classic UI" in the Prometheus dashboard. Homelab primarily; secondary: any Forge consumer who prefers the legacy graph interface or inspects alerting rules there.

2. **When** — fires on every classic-UI page load. Pipeline: next 03:00 UTC cron after this lands on `main`.

3. **What success looks like**:
   - **All 20** distinct `href`/`src` references on `/classic/graph` return HTTP 200.
   - Page renders with Bootstrap chrome: dropdowns work, graphs render via Rickshaw/d3, time-range picker works.
   - React UI at `/` still works (FG-039 regression guard).
   - All FG-035 + FG-039 smokes stay green.
   - Image size ≤ 300 MB (current 191 MB → ~200 MB expected).
   - grype scan stays clean (no dpkg closure change; adding files that already came with the `prometheus` apt dep).

4. **Urgency** — correctness + operator experience. The classic UI is un-usable (buttons unstyled, graphs blank). Anyone who switches to it from the React UI thinks the image is broken. Separately: two bug reports in two days for the same `prometheus-scratch-trixie:2.53` image.

5. **Happy path**:
   1. Forge PR merges FG-040 to `dev`.
   2. Promote to `main` via `release.yml`.
   3. Next 03:00 UTC cron publishes `:2.53` + `:latest` with the inlined static assets.
   4. Operator refreshes `/classic/graph` → full UI.

6. **Edge cases / failure modes**:
   - **Future Debian minor bumps** add/remove `libjs-*` deps. Mitigation: `cp -rL` dereferences whatever's there at build time; no hardcoded list. If a lib is added, it ships; if removed, it doesn't. Smoke asserts every HTML `href`/`src` returns 200 — catches both drift directions.
   - **Image size creep** — currently +10 MB. If Debian bundles grow a lot in a future release, `smoke_size.sh`'s 300 MB cap catches it.
   - **License surface** — the inlined `libjs-*` content is under the licensing the Debian package already carries; SBOM already lists them via syft's dpkg cataloger. No new license concern.
   - **Vendor-dir confusion** — Forge already ships some lib content under `web/static/vendor/` (fuzzy, bootstrap3-typeahead, etc). Those are hard-shipped by the `prometheus` package itself, not symlinked. `cp -rL` doesn't change their behavior.

7. **Out of scope**:
   - Replacing the classic UI with the React UI entirely. Debian still ships it; some operators still use it; shipping both is cheap.
   - Trimming the `web/static/` dir to only what's referenced. Overfitting; next Debian update could break.
   - Changing the React UI behavior. Already works via `go:embed`.
   - A separate `prometheus-scratch-trixie-no-classic` variant. Overengineering.

8. **How we know it's done** — see Gherkin below.

9. **Capabilities delivered or extended**:
   - EXT `image.prometheus-serves-metrics` — classic UI now renders with full styling + working JS; previously HTML-only.

## Gherkin acceptance

```
Scenario: Every classic-UI asset referenced from /classic/graph returns 200
  Given a running forge-local/prometheus-scratch-trixie:2.53
  When /classic/graph's HTML is fetched
   And every <link href="..."> and <script src="..."> is probed
  Then every response is HTTP 200
   And no response is 404

Scenario: Known-previously-404 bootstrap CSS now serves
  Given the same running container
  When `curl http://localhost:9090/classic/static/bootstrap4/css/bootstrap.min.css` runs
  Then the response is HTTP 200
   And the body starts with `/*! Bootstrap` or similar CSS preamble

Scenario: jQuery served (previously 404)
  Given the same running container
  When `curl http://localhost:9090/classic/static/jquery/jquery.min.js` runs
  Then the response is HTTP 200
   And the body is non-empty JavaScript

Scenario: FG-039 + FG-035 regression guard
  Given the FG-039 + FG-035 acceptance tests
  When re-run against the FG-040 image
  Then every scenario still passes

Scenario: Image size stays within budget
  Given the rebuilt image
  Then image size ≤ 300 MB
```

## References

- Plan: `docs/plan/FG-040-prometheus-classic-ui-assets-plan.md`
- Red test: `tests/acceptance/test_FG_040_prometheus-classic-ui-assets.sh`
- Evidence: captured HAR `~/Downloads/lala.har` — 25 of 34 entries were 404, all matching the 10 symlinked libs under `/usr/share/javascript/`
- Predecessors: FG-035 (initial scratch build — missed static assets entirely); FG-039 (fixed templates but missed symlink targets)
- Upstream: Debian trixie `prometheus 2.53.3+ds1-2` with `libjs-bootstrap4`, `libjs-jquery`, `libjs-d3`, etc. deps at `/usr/share/javascript/`
