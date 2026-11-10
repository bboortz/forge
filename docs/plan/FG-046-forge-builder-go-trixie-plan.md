# FG-046 — Plan: forge-builder-go-trixie + migrate all-but-one Go image

**Story**: [`docs/stories/FG-046-forge-builder-go-trixie.md`](../stories/FG-046-forge-builder-go-trixie.md)
**Status**: shipped
**Branch**: `feat/FG-046-forge-builder-go-trixie-migrations`

## Design delta

### `images/forge-builder-go-trixie/` (new)

Sibling of FG-025's `forge-builder-trixie`. `tag: 0.1`, platforms `[linux/amd64]`.

- Dockerfile: `FROM golang:1.27-trixie` → apt-upgrade + ca-certificates + git + curl + jq + syft (via Docker Hub, like FG-025). `go version` reports 1.27.3; `syft version` works. 943 MB (Go toolchain is heavy — comparable to golang:X-trixie).
- PROMISES.yaml: 6 promises — `files.go-toolchain`, `files.syft-binary`, `files.ca-certificates`, `files.release-resolve-tools` (git/curl/jq), `apt.freshly-upgraded`, `apt.no-cache` (inverse). Capability: `build.shared-go-builder`.
- 5 smokes: smoke_has_go.sh (version ≥ 1.27), smoke_has_syft.sh, smoke_ca_bundle.sh, smoke_release_tools.sh, smoke_no_apt_cache.sh.

### `scripts/build-image.sh` plumbing

Mirror of FG-025 pattern:

- `_FORGE_BUILDER_GO_DIR` check — if the image's Dockerfile contains `FORGE_BUILDER_GO_REF`, auto-build forge-builder-go-trixie first.
- `FORGE_BUILDER_GO_REF` resolution — prefer `forge-local/forge-builder-go-trixie:${tag}` if present, else `ghcr.io/bboortz/forge-builder-go-trixie:${tag}`.
- `_HAS_LOCAL_DEP` check extended so buildx cache is disabled when the forge-local Go builder is the FROM reference (daemon-only tag, buildx docker-container driver can't resolve it).
- `PULL_FLAG` dropped when FORGE_BUILDER_GO_REF is forge-local/… (same reason as FORGE_BUILDER_REF).
- `--build-arg FORGE_BUILDER_GO_REF=…` added to the final `docker build` invocation.
- `forge-builder-go-trixie` added to the "doesn't itself need forge-builder" skip-list (prevents circular dep).

### Migrated images — Dockerfile shape

| Image | Builder change | Binary source | Overlay additions |
|---|---|---|---|
| cadvisor-slim-trixie | `golang:1.27-trixie` → `forge-builder-go-trixie` | github.com/google/cadvisor v0.60.6 (unchanged) | none |
| node-exporter-scratch-trixie | `forge-builder-trixie` + apt-install → `forge-builder-go-trixie` + go build | github.com/prometheus/node_exporter v1.9.0 | none (pure Go, static binary) |
| alertmanager-scratch-trixie | `forge-builder-trixie` + apt-install → `forge-builder-go-trixie` + go build (2 binaries) | github.com/prometheus/alertmanager v0.28.1 | amtool binary + template/default.tmpl + template/email.tmpl (all from upstream source tree) |
| ipmi-exporter-scratch-trixie | Single builder → **dual builder**: forge-builder-go-trixie for the Go exporter, forge-builder-trixie for apt-install freeipmi-tools (C binaries + libs + /etc/freeipmi/*.conf) | github.com/prometheus-community/ipmi_exporter v1.10.0 | 5 C binaries (bmc-info, ipmi-sensors, ipmi-chassis, ipmi-dcmi, ipmi-sel), 4 libs, 4 conf files — all from Debian's freeipmi-tools pkg |
| ipmi-exporter-slim-trixie | Single-stage runtime → **two-stage**: forge-builder-go-trixie for exporter + debian:trixie-slim runtime with apt install freeipmi-tools + ca-certificates (keeps shell + apt for operator debugging) | github.com/prometheus-community/ipmi_exporter v1.10.0 | freeipmi-tools pkg installed via apt (unchanged) |

Each migrated image preserves:
- Exact upstream version string via upstream-matching `-X github.com/prometheus/common/version.Version=…` ldflags (so `--version` output is unchanged)
- Existing smoke suite + scan baseline + PROMISES.yaml contract
- Runtime shape (ENV, USER, WORKDIR, HEALTHCHECK, ENTRYPOINT, CMD)
- FG-031 /hc healthcheck pattern
- FG-009 SSL_CERT_FILE env for outbound-TLS images (alertmanager)
- FG-043's `collector_cmd: ipmi-sensors` + `custom_args` config override (ipmi-exporter)

### Prometheus deferral (NOT migrated)

Upstream Prometheus 2.53 embeds a React SPA via `go:embed` from `web/ui/static/react/` — and that directory is populated by `web/ui/build_ui.sh` which runs `npm install` + `npm run build` in each of multiple nested `web/ui/module/*` packages. Adding Node.js to the builder stage would:

- Bloat forge-builder-go-trixie from ~943 MB to ~1.5 GB
- Add 5+ minutes to prometheus's build time
- Introduce an npm dep-audit surface

Verified 2026-11-10: a from-source `go build ./cmd/prometheus` (without npm) produces a 97 MB binary that boots + serves /-/healthy but errors on `GET /` with `Error opening React index.html: open static/react/index.html: no such file or directory`.

**Decision**: defer. prometheus-scratch-trixie retains its current Debian-packaged binary + the existing FG-fix waiver for GO-2026-6604. A future story can introduce a Node-aware builder (perhaps `forge-builder-node-go-trixie` — hybrid) or use a different build path (Debian source package with UI pre-built).

### `docs/CAPABILITIES.md`

- NEW `build.shared-go-builder` entry (sibling of `build.shared-builder`).
- EXT `build.from-go-source` (FG-044) — now references the shared base + lists all 5 consumers.
- EXT `image.node-exporter-serves-metrics`, `image.alertmanager-routes-alerts`, `image.ipmi-exporter-serves-metrics`, `image.cadvisor-serves-metrics` — mention the source-rebuild under this story.

### Memory updates

- `memory/supply-chain.md`: update the "Go stdlib CVE triage" section to note that for Forge-native images we now control the toolchain (forge-builder-go-trixie), so Go CVEs land within 24h of the toolchain bump instead of months behind Debian.
- `memory/scratch-closures.md` already covers the "Debian shell-script wrapper in ELF clothing" trap (FG-043's `ipmimonitoring` lesson) — no change needed.

### IDEAS.md

- Mark `forge-builder-go-trixie` entry as SHIPPED (links to this story).
- Add new entry: `prometheus-scratch-trixie from-Go-source migration` — documents the React UI build-pipeline blocker. Promotion trigger: either (a) upstream Prometheus simplifies the UI build, or (b) we invest in a Node-aware builder.

## Alternatives rejected

- **Migrate prometheus too** — requires npm build pipeline; too much scope for this PR. Deferred to follow-up.
- **Add Node.js to forge-builder-go-trixie** — bloats to ~1.5 GB for one consumer. Premature; keep it minimal.
- **Build prometheus's React UI separately in a Node builder stage** — doable but adds a 3rd builder stage + npm dep management; defer until needed.
- **Keep each from-Go image pointing at `golang:X-trixie` directly** — misses the "one place to bump Go version" benefit of FG-025's shared-builder pattern.
- **Auto-resolve upstream latest release tag at build time** (FG-013 pattern) — operator-controlled version bumps via ARG are safer for images that can affect production (prometheus metrics wire contract, alertmanager notification receivers). Keep ARG pins for now.

## Breaking changes

None observable at the image-contract level:
- Every migrated image's `--version` output format + metrics wire protocol unchanged.
- Every HEALTHCHECK, ENTRYPOINT, CMD, EXPOSE, USER, WORKDIR unchanged.
- Existing scan-baseline.json files remain valid (any removed CVEs don't cause scan-regression failures).

Internal change (Dockerfile shape): each migrated image gets a new ARG `FORGE_BUILDER_GO_REF` + a Go-builder stage. Consumer-visible only to Forge maintainers.

## Merge plan

- All blocking gates pass.
- FG-046 acceptance test green (verifies every migrated image's Go stdlib version + the 5 scenarios).
- Each image's existing smoke suite + acceptance test still passes.
- scan-baseline.json regenerated for each migrated image (most will shrink — previous Go stdlib CRITICAL CVEs no longer present).
- `make test-fast` green.
- Pre-push `check-smart-strict` green.

## Rollout plan

1. Land on `dev` via PR → autonomous merge on green CI.
2. Promote to `main` via `release.yml` (user triggers).
3. Daily cron publishes:
   - forge-builder-go-trixie:0.1 + :latest (the base)
   - cadvisor-slim-trixie, node-exporter-scratch-trixie, alertmanager-scratch-trixie, ipmi-exporter-scratch-trixie, ipmi-exporter-slim-trixie (all re-built from source)
   - prometheus-scratch-trixie unchanged
4. Beaconry re-scans and sees zero Go stdlib CRITICALs on the 5 migrated images.
5. Operators see no change in image behavior.

## Shipping evidence

| Item | Pointer | Status |
|------|---------|--------|
| Scenario: forge-builder-go-trixie works | `tests/acceptance/test_FG_046_...sh` § 1 | ⏳ |
| Scenario: node-exporter stdlib go1.27 + wire contract unchanged | § 2 | ⏳ |
| Scenario: alertmanager stdlib go1.27 + amtool preserved | § 3 | ⏳ |
| Scenario: ipmi-exporter-scratch dual-builder + collector-override preserved | § 4 | ⏳ |
| Scenario: ipmi-exporter-slim rebuilt + freeipmi apt-install preserved | § 5 | ⏳ |
| Scenario: cadvisor uses shared Go base | § 6 | ⏳ |
| Scenario: zero Go-stdlib CRITICALs in all 5 migrated images | § 7 | ⏳ |
| Scenario: prometheus migration deferred (documented) | IDEAS.md entry + prometheus Dockerfile unchanged | ⏳ |
| NEW `build.shared-go-builder` | `docs/CAPABILITIES.md` entry | ⏳ |
| EXT `build.from-go-source` consumers | `docs/CAPABILITIES.md` update | ⏳ |
