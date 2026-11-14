# FG-050 — Plan: Freshen upstream pins

**Story**: [`docs/stories/FG-050-freshen-upstream-pins.md`](../stories/FG-050-freshen-upstream-pins.md)
**Status**: ready → (pending implementation; story + plan + red test land first, implementation paused for user review)
**Branch**: `feat/FG-050-freshen-upstream-pins`

## Design delta

### `cadvisor-slim-trixie` — switch to `:latest`

- `Dockerfile`: `ARG CADVISOR_VERSION=v0.60.6` → `ARG CADVISOR_VERSION=` (empty default).
- `build.sh`: resolve via GitHub API if `CADVISOR_VERSION` empty (mirror `images/uptime-kuma-slim-trixie/build.sh` shape — ~6 lines of curl + jq, pass result as `--build-arg CADVISOR_VERSION=$RESOLVED`).
- `image.yaml`: `tag: "0.60.6"` → `tag: "latest"`. Comment updated to reflect 2-tag family (`:latest`, `:latest-amd64`) instead of 4-tag.
- `PROMISES.yaml`: no change — current description already describes behavior, not a version number. Version banner in the `--version` smoke uses regex matching, not literal match.
- `scan-baseline.json`: regenerate post-resolve of current `latest` (should still be v0.60.6 since upstream hasn't bumped since we pinned).

### `ipmi-exporter-scratch-trixie` + `ipmi-exporter-slim-trixie` — switch to `:latest`

Both images share the same `IPMI_EXPORTER_VERSION` ARG and must flip together (otherwise the pair diverges).

- Both `Dockerfile`s: `ARG IPMI_EXPORTER_VERSION=v1.10.0` → `ARG IPMI_EXPORTER_VERSION=` (empty default).
- Each `build.sh`: resolve via GitHub API against `prometheus-community/ipmi_exporter`.
- Both `image.yaml`s: `tag: "1.10"` → `tag: "latest"`.
- `PROMISES.yaml` (both): no change needed — descriptions don't carry version numbers.
- `scan-baseline.json` (both): regenerate (expected: tiny diff, v1.10.0 → v1.10.1).

### `node-exporter-scratch-trixie` — explicit bump v1.9.0 → v1.12.1

- `Dockerfile`: `ARG NODE_EXPORTER_VERSION=v1.9.0` → `ARG NODE_EXPORTER_VERSION=v1.12.1`.
- `image.yaml`: `tag: "1.9"` → `tag: "1.12"`. Tag-family comment updated.
- `PROMISES.yaml`: line 12 `"node_exporter, version 1.9.0"` → `"node_exporter, version 1.12.1"`.
- `scan-baseline.json`: regenerate. Expected: minor CVE diff from 3 minor versions of Go stdlib churn + dep bumps.

### `alertmanager-scratch-trixie` — bump v0.28.1 → v0.35.0 **DEFERRED**

Discovered mid-implementation (2026-11-13): upstream Alertmanager v0.32.0 ([changelog](https://github.com/prometheus/alertmanager/releases/tag/v0.32.0)) stopped shipping compiled UI assets in-tree. `ui/web.go` carries `//go:embed app/dist/*`, which errors out at compile time unless the UI's React/Mantine sources have been built into `ui/app/dist/` first. From the upstream changelog:

> `go get github.com/prometheus/alertmanager/ui` will now fail as compiled UI assets are no longer checked into the repository. Downstream builds that rely on these assets being present in the source tree must now build the UI from source.

To bump alertmanager to v0.32 or later, we'd need a Node.js UI build stage in the Dockerfile — effectively a duplicate of the npm-build infrastructure FG-048 is extracting as `forge-builder-node-trixie` for prometheus. Rather than ship that infra inline here (and then refactor when FG-048 lands), defer the alertmanager bump.

**Changes NOT applied** (alertmanager remains unchanged from pre-FG-050 state):

- `Dockerfile`: `ARG ALERTMANAGER_VERSION=v0.28.1` stays. A FG-050 comment names the blocker.
- `image.yaml`: `tag: "0.28"` stays.
- `PROMISES.yaml`: `"alertmanager, version 0.28.1"` stays.
- `scan-baseline.json`: unchanged.

**IDEAS entry** added for "alertmanager v0.32+ bump" — blocked on FG-048. When forge-builder-node-trixie ships, revisit this as a `fix/` or combined into FG-048's PR.

### Changelog audit — recorded for future reference

Even though we're not shipping the bump, the audit remains useful when FG-048 unblocks it. Only **container-contract-affecting** entries are listed below.

| Version | Breaking | Impact on our image |
|---|---|---|
| v0.29.0 | None | — |
| v0.30.0 | Internal API only | none |
| v0.31.0 | None | — |
| v0.32.0 | **UI assets removed from source tree** | **blocks `go build` without a Node.js UI build stage** — this is why FG-050 defers |
| v0.33.0 | `--enable-feature=auto-gomaxprocs` removed; `marker` package extracted; `alertmanager_marked_alerts` metric removed | we don't use the flag; we don't expose the metric |
| v0.34.0 | **`reason` label split on `alertmanager_notifications_failed_total`** — HTTP 401/403 now `authError`, HTTP 429 now `rateLimited` (previously all `clientError`) | **operator-facing**. Dashboards matching `reason="clientError"` for notification auth or rate-limit failures will miss the new counter when we eventually ship v0.34+ |
| v0.35.0 | `--enable-feature=auto-gomemlimit` renamed; eventrecorder schema changes; `types` package removed | none (we don't use any) |

**Verdict**: safe at the metrics + container API level. Only the v0.32 UI-pipeline requirement blocks the actual build. Ship when node-builder infra lands.

### Node-exporter breaking-change audit (compressed)

| Version | Breaking | Impact |
|---|---|---|
| v1.9.1 | None | — |
| v1.10.0 | mdadm uses sysfs instead of `/proc/mdstat` (same metric names); default filesystem excludes add `erofs` | behavior improvement; no API change |
| v1.10.1 / v1.10.2 | Patch | none |
| v1.11.0 | Distroless container image added (upstream artifact — no impact on our build) | none |
| v1.12.0 / v1.12.1 | None | — |

**Verdict**: safe to bump. Zero metric renames, zero label removals.

### `docs/CAPABILITIES.md` entries

- **NEW** `build.ref-latest-release` — pattern of empty `*_VERSION` ARG + in-Dockerfile GitHub Releases API resolve via curl + jq. Delivered by FG-050; FG-045 uptime-kuma-slim-trixie is a prior precedent.
- **EXT** `image.cadvisor-serves-metrics` — now tracks upstream `latest`.
- **EXT** `image.ipmi-exporter-serves-metrics` — now tracks upstream `latest` (both variants).
- **EXT** `image.node-exporter-serves-metrics` — now v1.12.1.
- `image.alertmanager-routes-alerts` — **NOT extended this cycle** (v0.35 bump deferred).

### `docs/stories/INDEX.md`

New FG-050 row.

### `docs/plan/IDEAS.md`

**New entry** (added this cycle): "alertmanager v0.32+ bump — blocked on FG-048 forge-builder-node-trixie." When FG-048 extracts the Node builder base, this is a mechanical ARG bump + add builder stage. Likely 1-2 hours of work piggy-backed on FG-048's PR or shipped immediately after.

Other deferred items unchanged:
- "cosign v3 migration" still deferred (separate pin, separate review cycle).
- "Switch other pinned images to `:latest`" NOT added to IDEAS — we've explicitly decided alertmanager + node-exporter + prometheus stay pinned due to breaking-change history. Python / postgres / nginx / mosquitto / redis are Debian-packaged; not candidates.

### Red acceptance test — `tests/acceptance/test_FG_050_freshen-upstream-pins.sh`

4 sections (post-deferral):

1. **Files-and-pins correctness** — read all 4 Dockerfiles + 4 image.yaml files; assert the exact expected ARG value and tag value per image. Strict string match except where `:latest` is expected (where empty ARG is asserted). Also asserts both ipmi-exporter Dockerfiles carry the same ARG shape (symmetry check). **Alertmanager** gets its own sub-assertion: still `v0.28.1` + Dockerfile carries a FG-048 blocker comment.
2. **PROMISES version banner updated for node-exporter** — `grep 'version 1.12.1' images/node-exporter-scratch-trixie/PROMISES.yaml` returns a line.
3. **Build + smoke** — `scripts/build-image.sh` for each of the 3 bumped images (cadvisor + ipmi-exporter pair + node-exporter); run each image's smoke suite. Must pass. Alertmanager deliberately NOT built here (unchanged this cycle).
4. **Alertmanager deferral documented** — grep plan doc for the FG-048 / forge-builder-node-trixie reference naming the UI-pipeline blocker.

## Alternatives rejected

- **Ship as 4 separate `chore/` commits** — each one is small, but the breaking-change review for alertmanager is more valuable when the reviewer can see the full picture: 7 minor versions of changes, which affect the image vs which don't. A single PR concentrates that review. The IPMI pair also must flip together.
- **Bump alertmanager to a specific pre-v0.34 version to avoid the reason-label split** — defers the real decision. Operators' dashboards eventually need the update either way; delaying doesn't help them.
- **Switch alertmanager + node-exporter to `:latest` too** — rejected by the question-9 analysis. Alertmanager's history of config + metric-label breaking changes makes silent auto-updates risky. Node-exporter has fewer such changes but still enough (collector renames in older versions) that the discipline of a manual bump gate is worth keeping.
- **Introduce `scripts/resolve-latest-release.sh` now instead of copying uptime-kuma's inline logic 3× (cadvisor + 2× ipmi-exporter)** — borderline. We go with the "3 similar lines beats a premature abstraction" rule for this PR. If a 4th/5th consumer appears, extract. IDEAS entry if someone wants.
- **Bump cadvisor to a hypothetical v0.61** — upstream's latest is v0.60.6 as of 2026-11-13. We're already there. The point of `:latest` for cadvisor is automation, not catch-up.

## Breaking changes

**For Forge image consumers:** None at the API / tag-contract level, with one tag-vocabulary change:

1. Consumers pinning `node-exporter-scratch-trixie:1.9` stay on v1.9.0. New publishes go to `:1.12`.
2. Consumers pulling `ipmi-exporter-scratch-trixie:1.10` or `cadvisor-slim-trixie:0.60.6` will continue to pull those legacy tags from GHCR (frozen from before this story). Going forward, only `:latest` is published for these two images. **This is a tag-vocabulary change** — operators who want "the current stable" should start pulling `:latest` (or more precisely `:latest-amd64` for architecture explicitness).
3. `alertmanager-scratch-trixie:0.28` unchanged this cycle (bump deferred — see above).

**For operators of the alertmanager image:** No change. The v0.34.0 `reason` label split is NOT shipped in this cycle (alertmanager bump deferred). When FG-048 unblocks it, operators will need to update dashboards matching `alertmanager_notifications_failed_total{reason="clientError"}` for HTTP 401/403/429 failures to additionally match `reason="authError"` and `reason="rateLimited"`.

## Merge plan

All blocking gates per `memory/workflow.md`:

- hadolint + shellcheck + yamllint + actionlint clean on edited files.
- `make verify-sid-pins` — N/A (no sid pins touched).
- `make verify-traceability` — new CAP registered + bidirectional links.
- `make verify-contracts` — PROMISES.yaml edits validate against schema.
- `make verify-no-upstream-drift` — unchanged; this story doesn't change any `FROM` lines.
- `make test-acceptance` — new FG-050 test green.
- `make build` + `make scan` + `make verify` + `make test-images` per affected image.
- Scan-regression gate: regenerated baselines in-PR for the three bumped-pin images; cadvisor baseline unchanged (version unchanged).
- Image sizes within budget for each image (ceiling unchanged).

## Rollout plan

1. Land story + plan + red test on `feat/FG-050-freshen-upstream-pins`. **Pause here per user instruction** (ship story + plan + red test, stop before implementation).
2. (On user go-ahead) Implement 5 Dockerfile edits + 5 image.yaml edits + 2 PROMISES edits + 3 regenerated scan-baselines + build.sh updates.
3. Autonomous merge on green CI per workflow.md step 8.
4. Promote to main via `release.yml` (user triggers).
5. Daily cron publishes:
   - `:latest` tag family (4 images) for cadvisor + ipmi-exporter pair.
   - `:1.12` tag family for node-exporter.
   - `:0.35` tag family for alertmanager.
6. Operators pulling `:latest` on any of these images get the new binary on the next pull after cron.
7. README `§ Images` table updated post-merge with the new tags (if it lists specific versions).

## Shipping evidence

| Item | Pointer | Status |
|------|---------|--------|
| Story drafted | `docs/stories/FG-050-freshen-upstream-pins.md` | ✅ |
| Plan drafted | `docs/plan/FG-050-freshen-upstream-pins-plan.md` | ✅ |
| Red acceptance test | `tests/acceptance/test_FG_050_freshen-upstream-pins.sh` | ✅ |
| INDEX.md updated | `docs/stories/INDEX.md` | ✅ |
| CAPs registered | `docs/CAPABILITIES.md` — `build.ref-latest-release` NEW + 3 EXT | ✅ |
| IDEAS entry for alertmanager v0.32+ bump | `docs/plan/IDEAS.md` | ✅ |
| Scenario: cadvisor floats | `tests/acceptance/test_FG_050_...sh` §1 | ✅ (built + smoked locally) |
| Scenario: ipmi-exporter pair floats | §1 (symmetry check) | ✅ (built + smoked locally — both resolved v1.10.1) |
| Scenario: node-exporter pins v1.12.1 | §1 + §2 | ✅ (built + smoked locally) |
| Scenario: alertmanager deferred, documented | §1 + §4 | ✅ |
| Scenario: build + smokes green | §3 | ✅ (local; CI runs on PR) |
| Scenario: scan-baseline regenerated for node-exporter | §3 | ⚠️ (at commit time) |
