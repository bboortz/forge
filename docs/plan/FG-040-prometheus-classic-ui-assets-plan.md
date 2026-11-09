# FG-040 — Plan: fix prometheus classic UI static asset 404s

**Story**: [`docs/stories/FG-040-prometheus-classic-ui-assets.md`](../stories/FG-040-prometheus-classic-ui-assets.md)
**Status**: draft
**Branch**: `feat/FG-040-prometheus-classic-ui-assets`

## Design delta

### `images/prometheus-scratch-trixie/Dockerfile` — one char change

```diff
- cp -r /usr/share/prometheus/web /out/usr/share/prometheus/web; \
+ cp -rL /usr/share/prometheus/web /out/usr/share/prometheus/web; \
```

`-L` dereferences symlinks. `/usr/share/prometheus/web/static/` contains 10 symlinks (`bootstrap4`, `d3`, `eonasdan-bootstrap-datetimepicker`, `jquery`, `jquery-hotkeys`, `moment`, `moment-timezone`, `mustache`, `popper.js`, `rickshaw`) pointing at `../../../javascript/<lib>/`. With `-L`, `cp` reads through the symlinks and writes real directories into `/out`. Debian's packaged lib content lands in the overlay without us needing to also copy `/usr/share/javascript/`.

Size impact: +~10 MB. Current image 191 MB → ~201 MB. Budget 300 MB.

### Extend smoke test — `images/prometheus-scratch-trixie/tests/smoke_web_ui.sh`

Add one section to the existing file (after the `_base.html` presence check + React UI probe + classic-UI render probe):

**Section 4: every classic-UI asset returns 200.** Fetch `/classic/graph`, extract every `href="..."` and `src="..."` with `/classic/static/` prefix via grep + awk, loop + curl each, assert HTTP 200. Any single 404 fails the smoke.

This is the exact probe that would have caught FG-039's gap on day zero.

### Red acceptance test — `tests/acceptance/test_FG_040_prometheus-classic-ui-assets.sh`

1. Static invariants — Dockerfile grep for `cp -rL /usr/share/prometheus/web`; the extended `smoke_web_ui.sh` carries the asset-matrix probe.
2. Build.
3. Run the extended `smoke_web_ui.sh` (which now includes section 4).
4. Re-run `test_FG_035_prometheus-scratch-trixie.sh` + `test_FG_039_prometheus-web-ui.sh` (regression guard — both must stay green).

### PROMISES bump

- `version: "0.2"` → `"0.3"`
- Extend the `runtime.web-ui-serves` promise description: add "+ every classic-UI `href`/`src` asset returns HTTP 200".

### No workflow + no CAPABILITIES changes

`image.prometheus-serves-metrics` already registered; the "Extended by" line for FG-040 can be added but isn't critical for traceability.

### Scan-baseline

No dpkg closure change — all the `libjs-*` packages were already in Debian's `prometheus` apt dep chain and already appeared in the syft SBOM. The runtime overlay now ships the files those packages installed; the SBOM listing stays. Regen anyway for hygiene.

## Alternatives rejected

- **`cp -r /usr/share/javascript /out/usr/share/javascript`** (keep symlinks, ship targets) — also works; preserves the Debian-style symlink architecture. Downside: two directories to think about; symlinks are relative-path-aware and could break if the overlay is remounted. `-rL` is a cleaner self-contained overlay.
- **Hardcode-ship only the libs actually referenced by `/classic/graph`** — trims ~1-2 MB; next Debian update rearranges deps and we break. Not worth the brittleness.
- **Drop the classic UI entirely** — Debian still bundles it; cosmetic consistency with upstream has value; shipping is cheap. Decision made in FG-039 planning.

## Breaking changes

None. Image only grows (+10 MB); nothing removed; API surface unchanged.

## Merge plan

- Red test passes post-fix (section 4's HTTP 200 matrix is the single highest-value assertion).
- FG-035 + FG-039 regression tests pass.
- `make test-fast` + pre-push `check-smart-strict` green.
- `scan-baseline.json` regenerated.

## Rollout plan

1. Land FG-040 on `dev` via PR.
2. Promote to `main` via `release.yml`.
3. Next 03:00 UTC cron publishes `:2.53` + `:latest` with the classic UI fully styled.
4. Operator refreshes browser → full UI.

## Shipping evidence

| Item | Pointer | Status |
|------|---------|--------|
| Scenario: every classic-UI asset returns 200 | `tests/acceptance/test_FG_040_...sh` § 3 + smoke_web_ui.sh § 4 | ⏳ |
| Scenario: Bootstrap CSS specifically | § 3 + smoke_web_ui.sh § 4 | ⏳ |
| Scenario: jQuery specifically | § 3 + smoke_web_ui.sh § 4 | ⏳ |
| Scenario: FG-035 + FG-039 regression | § 4 (re-runs both acceptance tests) | ⏳ |
| Scenario: size within budget | smoke_size.sh | ⏳ |
| EXT `image.prometheus-serves-metrics` | `docs/CAPABILITIES.md` (optional note) | ⏳ |
