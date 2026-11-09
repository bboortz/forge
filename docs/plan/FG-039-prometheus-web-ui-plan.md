# FG-039 — Plan: fix prometheus-scratch-trixie web UI

**Story**: [`docs/stories/FG-039-prometheus-web-ui.md`](../stories/FG-039-prometheus-web-ui.md)
**Status**: draft
**Branch**: `feat/FG-039-prometheus-web-ui`

## Design delta

### `images/prometheus-scratch-trixie/Dockerfile`

Add one line to the overlay-assembly `RUN`:

```dockerfile
cp -r /usr/share/prometheus/web /out/usr/share/prometheus/web; \
```

Debian's Prometheus package ships templates (`_base.html` + 9 page templates) under `/usr/share/prometheus/web/templates/` and bootstrap/vendor static assets under `/usr/share/prometheus/web/static/`. Total 332 KB. These paths are **compile-time hardcoded in Debian's build** — no CMD flag override is possible.

No CMD change needed; `--web.console.templates` + `--web.console.libraries` already correctly point at `/etc/prometheus/{consoles,console_libraries}/` (the classic-console template dirs — different thing from `/usr/share/prometheus/web/`, which is for the UI chrome).

No PROMISES version bump — the contract text for `runtime.healthy-endpoint` is unchanged; this fix is a bugfix behind an already-public promise. Add new promise `runtime.web-ui-serves` instead.

### `images/prometheus-scratch-trixie/PROMISES.yaml`

- Bump `version: "0.1"` → `"0.2"`.
- Add new promise:
  ```yaml
  - id: runtime.web-ui-serves
    description: "GET / returns the React UI (HTTP 200, HTML body); GET /classic/graph returns the classic UI (HTTP 200, HTML body); no 'error reading base template' in container logs. Requires /usr/share/prometheus/web/ shipped in the runtime overlay."
    caps: [image.prometheus-serves-metrics]
    tests:
      - images/prometheus-scratch-trixie/tests/smoke_web_ui.sh
  ```

### New smoke test: `images/prometheus-scratch-trixie/tests/smoke_web_ui.sh`

Three-part:
1. **Content check** via `docker save | tar tf` — `usr/share/prometheus/web/templates/_base.html` is present.
2. **React UI** — `curl -sf http://host:9090/` → HTTP 200 OR a 2xx redirect that lands on HTML. Body contains `<html` or `<!doctype`.
3. **Classic UI** — `curl -sf http://host:9090/classic/graph` → HTTP 200, body contains `<html`, AND the container logs do NOT contain `error reading base template`.

### Red acceptance test: `tests/acceptance/test_FG_039_prometheus-web-ui.sh`

1. Static invariants — Dockerfile grep for `cp -r /usr/share/prometheus/web`; PROMISES.yaml grep for `runtime.web-ui-serves`.
2. Build the image.
3. Run the new `smoke_web_ui.sh`.
4. Re-run all other FG-035 smokes + `test_FG_035_prometheus-scratch-trixie.sh` (regression guard).

### Scan-baseline

No dpkg closure change (no new apt packages), but the SBOM includes `/usr/share/prometheus/web/` content paths. Regen anyway to keep the baseline honest.

### No workflow changes

`build.yml` + `ci.yml` already pick up the image via the discover matrix.

## Alternatives rejected

- **Patch Debian's prometheus binary to look elsewhere** — insane; compile-time path.
- **Switch to upstream Prometheus tarball** — bypasses Debian's security-tracker cadence; loses the CVE pipeline. Not worth it for 332 KB.
- **Ship node-exporter example consoles** (`prometheus-example-consoles` Debian package or equivalent) — not what the bug is about. `/etc/prometheus/consoles/` placeholder dirs stay; operators who want the fancy node-exporter dashboards bake a derived image.
- **Bump image.yaml tag to 2.53.1** — no semantic change; same binary version.
- **Change `/etc/prometheus/consoles/` → `/usr/share/prometheus/consoles/`** (as the bug report suggested) — Debian layout keeps them at `/etc/prometheus/`; the baked CMD flags match. Moving them is a separate concern not driven by this fix.

## Breaking changes

None. Image only grows (+332 KB) and adds functionality; nothing removed, no API change.

## Merge plan

- Red acceptance test passes post-implementation.
- FG-035 acceptance test re-run against the new image passes (regression guard).
- `make test-fast` + pre-push `check-smart-strict` green.
- `scan-baseline.json` regenerated.

## Rollout plan

1. Land FG-039 on `dev` via PR.
2. Promote to `main` via `release.yml` dispatch.
3. Next 03:00 UTC cron publishes `:2.53` + `:latest` with the web UI fixed.
4. Homelab operator pulls new digest → UI works.

## Shipping evidence

| Item | Pointer | Status |
|------|---------|--------|
| Scenario: React UI loads at / | `tests/acceptance/test_FG_039_...sh` § 3 + smoke_web_ui.sh | ⏳ |
| Scenario: Classic UI renders without template errors | § 3 + smoke_web_ui.sh | ⏳ |
| Scenario: /usr/share/prometheus/web/ shipped | § 3 (file-presence in smoke) | ⏳ |
| Scenario: no regression vs FG-035 | § 4 (re-runs test_FG_035) | ⏳ |
| Scenario: image size within budget | smoke_size.sh | ⏳ |
| EXT `image.prometheus-serves-metrics` | `docs/CAPABILITIES.md` extension | ⏳ |
