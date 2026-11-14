---
id: FG-050
slug: freshen-upstream-pins
status: shipped
owner: bboortz
created: 2026-11-13
---

# FG-050 — Freshen upstream pins: ipmi-exporter + cadvisor to :latest, node-exporter bump

Three Forge images lagging on upstream. This story combines two kinds of fix:

**Switch to `:latest` floating pattern** (same mechanism as uptime-kuma-slim-trixie / FG-013):

- `cadvisor-slim-trixie` — stable upstream project, no breaking-change history in v0.60.x, operators don't mount config files. Good candidate.
- `ipmi-exporter-scratch-trixie` + `ipmi-exporter-slim-trixie` — pair of images sharing `IPMI_EXPORTER_VERSION`, slow release cadence (~1-2/yr), metrics-only, no config contract. Good candidates.

**Explicit version bumps** (pins stay, changelog-reviewed for breaking changes):

- `node-exporter-scratch-trixie` — v1.9.0 → **v1.12.1**. 3 minor versions, no metric renames or label changes affecting dashboards. mdadm metric source moved from `/proc/mdstat` to sysfs (behavior improvement); `erofs` added to default filesystem excludes.

**Deferred (blocked on FG-048's node-UI-builder infrastructure):**

- `alertmanager-scratch-trixie` — v0.28.1 → v0.35.0 was originally scoped here. **Blocked**: upstream v0.32.0+ no longer ships compiled UI assets in-tree (`ui/web.go` uses `//go:embed app/dist/*`, which requires `ui/app/dist/` to exist at compile time; upstream removed those pre-built assets per [v0.32 changelog](https://github.com/prometheus/alertmanager/releases/tag/v0.32.0): *"`go get github.com/prometheus/alertmanager/ui` will now fail as compiled UI assets are no longer checked into the repository. Downstream builds that rely on these assets being present in the source tree must now build the UI from source."*). Alertmanager v0.32+ needs a Node.js UI build pipeline — same shape FG-048 is adding for prometheus. Rather than duplicate FG-048's work inline here, defer alertmanager's bump until forge-builder-node-trixie ships (tracked in IDEAS.md under "alertmanager v0.32+ bump"). Alertmanager stays at v0.28.1 for this cycle.

Why combined into one story instead of three `chore/`s: the IPMI pair shares an ARG and must flip together; the `:latest` switch is the same pattern applied twice. A single PR exercising the same scan-regression + size-budget audit gate across all three remaining images is cheaper to review than three micro-PRs.

## 9 canonical answers

1. **Who** — Forge maintainer (me) applying routine upstream-freshen discipline. Secondary: operator running these images (gets newer binary + newer CVE profile next cron cycle).

2. **When** — fires on this story's merge-to-dev. Daily cron picks up the new recipes; next cold rebuild produces the new binary versions. For the `:latest` images, every subsequent cron re-resolves the current upstream latest release (same mechanism uptime-kuma already uses).

3. **What success looks like**:
   - `images/cadvisor-slim-trixie/Dockerfile` has `ARG CADVISOR_VERSION=` (empty); the Dockerfile's builder stage resolves upstream GitHub `latest` release via curl+jq; `image.yaml` `tag: "latest"`.
   - `images/ipmi-exporter-scratch-trixie/Dockerfile` + `images/ipmi-exporter-slim-trixie/Dockerfile` both have `ARG IPMI_EXPORTER_VERSION=` (empty); each Dockerfile's builder stage resolves upstream via curl+jq; both `image.yaml` files carry `tag: "latest"`.
   - `images/node-exporter-scratch-trixie/Dockerfile` has `ARG NODE_EXPORTER_VERSION=v1.12.1`; `image.yaml` tag `"1.12"`; PROMISES.yaml version banner updated to `1.12.1`.
   - `images/alertmanager-scratch-trixie/Dockerfile` stays pinned to `v0.28.1` with a deferral comment pointing at the FG-048 / forge-builder-node-trixie blocker.
   - Every affected image's acceptance test + smoke suite passes against the new build. Scan-baselines regenerated for node-exporter (the one bumped-pin image).
   - No consumer-facing API change. Existing cap entries still apply; one new CAP registered (see Q9).

4. **Urgency** — quality-of-life. No CVE pressure forces this cycle. node-exporter + ipmi-exporter are freshness, not security. cadvisor currently matches upstream — the switch to `:latest` is stability-of-process (no future bumps needed for it). The alertmanager v0.35 bump that originally scoped this story is deferred (upstream UI-pipeline blocker; see "Deferred" paragraph above).

5. **Happy path**:
   1. Branch `feat/FG-050-freshen-upstream-pins` from `dev`.
   2. Flip `CADVISOR_VERSION` + `IPMI_EXPORTER_VERSION` in both Dockerfiles to empty; add a Dockerfile RUN step before the git clone that resolves the version via `curl https://api.github.com/repos/<upstream>/releases/latest | jq -r .tag_name` and writes it to `/tmp/resolved-version` for the subsequent build step to consume. Update the three `image.yaml` files to `tag: "latest"`.
   3. Bump `NODE_EXPORTER_VERSION=v1.12.1` + update PROMISES version banner + `image.yaml` `tag: "1.12"`.
   4. `scripts/scan-baseline-update.py` for node-exporter (the one image whose binary version changed).
   5. `make check-smart-strict` green locally.
   6. PR to `dev` → CI full-check on 3 affected images → merge on green.
   7. Daily cron picks up the new recipes; next build cycle publishes the new binaries.

6. **Edge cases / failure modes**:
   - **`:latest` resolution hits GitHub API rate-limit during cron** — GitHub's unauthenticated API caps at 60 req/hr/IP; we use < 5 per cron (one per `:latest`-tracking image). Comfortable margin. Mitigation if it ever bites: authenticate via `GITHUB_TOKEN` already available in GHA.
   - **Upstream yanks a release post-publish** — resolved sha is baked into `org.opencontainers.image.revision` + SBOM; publish-time digest is immutable. Daily cron would re-resolve the next release.
   - **alertmanager v0.34 `reason` label split silently breaks an operator's PagerDuty-failure dashboard** — operator responsibility per Forge's shared-image contract, but worth calling out in the release notes + README. Documented in plan.
   - **node-exporter v1.10 mdadm sysfs-vs-/proc behavior change** — metrics have same names, slightly different exact values under RAID degraded states. Documented, not broken.
   - **ipmi-exporter v1.10.x ships a patch release we miss** — this is precisely what `:latest` fixes. Current discipline misses them.
   - **cadvisor v0.61 lands with a breaking collector change** — `:latest` would auto-pick it up. Mitigation: FG-050 (and the broader `:latest` practice) implies we accept this risk for images with historically-stable release discipline. If upstream ships a surprise major-breaking change, the next Forge rebuild's smoke tests catch it (cadvisor's smoke exercises `/healthz` + `/metrics` on :8080; a broken release fails those), the daily cron fails to publish, and `:latest` stays on the previous good build. Not silent.
   - **Scan-regression CRITICAL/HIGH diff on the three bumped images** — likely zero or one new; expected with 3-7 versions of changes. Re-baseline in-PR.

7. **Out of scope**:
   - **alertmanager bump to v0.35.0** — deferred. Discovered mid-implementation that upstream v0.32+ needs an npm UI build pipeline (FG-048 territory). Rather than ship node-builder infrastructure twice (once inline here, once properly as FG-048), park the alertmanager bump until FG-048 extracts `forge-builder-node-trixie`. Then alertmanager v0.35 + prometheus 3.x migrate together.
   - **Switching node-exporter or alertmanager to `:latest`** — both have historically-breaking changes between minors (alertmanager especially). Keep pinned.
   - **Switching postgres / python / nginx / mosquitto / redis to `:latest`** — these are Debian-packaged, version follows apt; not ARG-pinned.
   - **Switching prometheus to anything** — FG-048's job, deferred.
   - **cadvisor-slim-trixie internal Go pin** — the Go base is `forge-builder-go-trixie:latest` (already-floating forge image). Nothing to change.
   - **Introducing a shared helper for the GitHub-API-resolve step** — right now uptime-kuma's `build.sh` has its own 6-line resolve. We'll copy the pattern. If a 4th or 5th `:latest` consumer lands, extract into `scripts/resolve-latest-release.sh`.
   - **Stability-contract text in PROMISES.yaml** — PROMISES already describes behavior; no new promise needed for "version floats." The `image.yaml tag: "latest"` IS the stability contract.

8. **How we know it's done** — see Gherkin below.

9. **Capabilities delivered or extended**:
   - NEW `build.ref-latest-release` — Dockerfiles carry an empty `<APP>_VERSION=` ARG; a sibling `build.sh` resolves the version at build time via `GET https://api.github.com/repos/<upstream>/releases/latest` + `jq -r .tag_name`, then passes it to `docker build --build-arg`. The resolved tag is baked into `org.opencontainers.image.revision` + the SBOM. Daily cron re-resolves, so the fleet stays current without manual bumps. Precedent: FG-045 uptime-kuma-slim-trixie implemented this shape as `build.from-node-source`'s sub-step; FG-050 formalizes the pattern as its own CAP + extends it to cadvisor + ipmi-exporter (scratch + slim).
   - EXT `image.cadvisor-serves-metrics` — now tracks upstream `latest` release instead of pinned version.
   - EXT `image.ipmi-exporter-serves-metrics` — now tracks upstream `latest` release instead of pinned version. Applies to both scratch + slim variants.
   - EXT `image.node-exporter-serves-metrics` — now v1.12.1 (was v1.9.0); no API contract change.
   - (NOT EXTENDED) `image.alertmanager-routes-alerts` — v0.35 bump deferred; alertmanager image unchanged this cycle.

## Gherkin acceptance

```
Scenario: cadvisor-slim-trixie tracks upstream latest
  Given the forge repo at FG-050 head
  When images/cadvisor-slim-trixie/Dockerfile is read
  Then it contains `ARG CADVISOR_VERSION=` with an empty default
   And images/cadvisor-slim-trixie/image.yaml carries `tag: "latest"`
   And images/cadvisor-slim-trixie/build.sh resolves the version via GitHub API

Scenario: ipmi-exporter (scratch + slim) tracks upstream latest
  Given the forge repo at FG-050 head
  When each of images/ipmi-exporter-scratch-trixie/Dockerfile and
       images/ipmi-exporter-slim-trixie/Dockerfile is read
  Then each contains `ARG IPMI_EXPORTER_VERSION=` with an empty default
   And each image.yaml carries `tag: "latest"`
   And each build.sh resolves the version via GitHub API
   And the two Dockerfiles resolve to the SAME version on a given build cycle

Scenario: node-exporter-scratch-trixie pins v1.12.1
  Given the forge repo at FG-050 head
  When images/node-exporter-scratch-trixie/Dockerfile is read
  Then it contains `ARG NODE_EXPORTER_VERSION=v1.12.1`
   And images/node-exporter-scratch-trixie/image.yaml carries `tag: "1.12"`
   And the PROMISES.yaml version banner string has been updated to `1.12.1`

Scenario: alertmanager bump deferred, deferral documented
  Given the forge repo at FG-050 head
  When images/alertmanager-scratch-trixie/Dockerfile is read
  Then it still contains `ARG ALERTMANAGER_VERSION=v0.28.1`
   And it carries a comment naming the FG-048 / forge-builder-node-trixie blocker

Scenario: build + smoke suite green for every affected image
  Given the three changed images (cadvisor + ipmi-exporter pair + node-exporter)
  When bash scripts/build-image.sh <image> runs for each
   And each image's existing smoke suite runs
  Then every smoke exits 0 against the new build

Scenario: scan-baseline regenerated for the one bumped-pin image
  Given node-exporter rebuilt at v1.12.1
  When scripts/scan-baseline-update.py node-exporter-scratch-trixie is run
  Then the updated scan-baseline.json commits cleanly
   And make scan-regression passes against the new baseline
```

## References

- Plan: `docs/plan/FG-050-freshen-upstream-pins-plan.md`
- Red test: `tests/acceptance/test_FG_050_freshen-upstream-pins.sh`
- Precedent: FG-045 uptime-kuma-slim-trixie — first consumer of `build.ref-latest-release` shape (not yet formalized as its own CAP; FG-050 formalizes).
- Precedent: FG-013 — `source.ref: latest` for externally-sourced images (different mechanism — same intent).
- Upstream changelog: [prometheus/node_exporter v1.9 → v1.12](https://github.com/prometheus/node_exporter/releases) (3 minor versions, no container-contract breakers).
- Deferred bump: [prometheus/alertmanager v0.32.0 release notes](https://github.com/prometheus/alertmanager/releases/tag/v0.32.0) — "compiled UI assets are no longer checked into the repository." Blocks any v0.32+ bump until FG-048 node-builder lands.
