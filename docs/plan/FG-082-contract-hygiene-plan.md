# FG-082 — Plan: contract hygiene (stale dumb-init refs + orphan smoke promises)

**Story**: [`docs/stories/FG-082-contract-hygiene.md`](../stories/FG-082-contract-hygiene.md)
**Status**: ready → shipped
**Branch**: `feat/FG-082-contract-hygiene`

## Design delta

Zero image behaviour changes. Pure documentation + contract tidy-up.

**Category A (4 files)** — drop the `+ dumb-init` phrase from:
- `images/pre-builder/archlinux/PROMISES.yaml` (lines 3, 36)
- `images/pre-builder/archlinux/tests/smoke_size.sh` (line 2 comment)
- `images/base/archlinux/Dockerfile` (line 14 composition comment)

The authoritative "DELTA ... dumb-init is NOT shipped" header in `pre-builder/archlinux/Dockerfile:16-20` + its LABEL remain untouched — they are the current truth.

**Category B (3 PROMISES files, 4 new promise entries)** — register the 4 orphan smokes as promises pointing at existing CAPs:

| File | Promise id | CAP |
|---|---|---|
| `images/ipmi-exporter-scratch-trixie/PROMISES.yaml` | `absence.shell-wrapper-dependency` | `image.ipmi-exporter-serves-metrics` |
| `images/prometheus-scratch-trixie/PROMISES.yaml` | `files.console-templates` | `image.prometheus-serves-metrics` |
| `images/prometheus-scratch-trixie/PROMISES.yaml` | `runtime.lifecycle-reload` | `image.prometheus-serves-metrics` |
| `images/uptime-kuma-slim-trixie/PROMISES.yaml` | `files.ping-binary` | `image.uptime-kuma-serves-monitoring` |

No new CAPs; no tooling changes; no new scripts.

## Alternatives rejected

- **Add `scripts/verify-no-orphan-smokes.sh` policy enforcement** — would turn B into a durable invariant, but adds net-new behaviour. Appropriate as a future FG after FG-082 proves the baseline. Deferred.
- **Collapse the 4 orphan smokes into one meta-promise** — hides the per-test traceability. DD-TGD wants explicit test-per-promise lines. Rejected.
- **Retitle `pre-builder/archlinux/PROMISES.yaml` version bump** — out of scope; version field is contract-schema version, not release.

## Breaking changes

None. `verify-traceability`, `verify-contracts`, `verify-dockerfile-conformance`, and `verify-no-upstream-drift` are unaffected (every promise still cites a known CAP; every CAP still has ≥1 test pointer).

## Merge plan

Full `memory/workflow.md § Blocking gates`. `make test-fast` + PR CI acceptance suite. No image rebuilds required (no Dockerfile that participates in a FROM chain is touched — only `base/archlinux/Dockerfile:14`, a prose comment).

## Rollout plan

1. PR → dev (auto-merge on green CI)
2. `release.yml` → main
3. `build.yml` — technically no-op for scan/sign (no image bits changed) but the daily cron will re-resolve digests anyway.

## Tooling updates

None.

## Shipping evidence

Filled at pre-ship audit.

| Item | Pointer | Status |
|------|---------|--------|
| Scenario: no "+ dumb-init" in 4 target files | `tests/acceptance/test_FG_082_contract-hygiene.sh:§1` | ✅ |
| Scenario: 4 orphan smokes referenced | test §2 | ✅ |
| Scenario: no new CAPs / no new images | test §3 | ✅ |
| Scenario: traceability + test-fast green | test §4 | ✅ |
| EXT `image.ipmi-exporter-serves-metrics` | PROMISES line | ✅ |
| EXT `image.prometheus-serves-metrics` (×2) | PROMISES line | ✅ |
| EXT `image.uptime-kuma-serves-monitoring` | PROMISES line | ✅ |
