# FG-044 — Plan: cadvisor-slim-trixie

**Story**: [`docs/stories/FG-044-cadvisor-slim-trixie.md`](../stories/FG-044-cadvisor-slim-trixie.md)
**Status**: shipped
**Branch**: `feat/FG-044-cadvisor-slim-trixie`

## Design delta

### `images/cadvisor-slim-trixie/` (new)

- `image.yaml`: tag `"0.60.6"`, platforms `[linux/amd64]`, no `depends_on` (slim variant; standalone).
- `Dockerfile`: multi-stage.
  - Stage 0: `FROM ghcr.io/bboortz/hc:0.1.0 AS hc` (for the FG-031 /hc binary).
  - Stage 1: `FROM docker.io/anchore/syft:latest AS syft-src` (syft binary — FG-025 convention).
  - Stage 2 (builder): `FROM golang:1.27-trixie AS builder` — apt-upgrade + git, shallow-clone `google/cadvisor@v0.60.6`, build with `CGO_ENABLED=0 -tags netgo` + upstream-mirrored ldflags for the `lib/version` package. Emits `/out/usr/bin/cadvisor` + `/sbom.json` (syft against source tree).
  - Stage 3 (runtime): `FROM debian:trixie-slim` — apt-upgrade + `ca-certificates`, `COPY --from=builder /out/usr/bin/cadvisor /usr/bin/cadvisor` + `/sbom.json` + `/hc`. `HEALTHCHECK` polls `/hc http://127.0.0.1:8080/healthz`. Entrypoint: `/usr/bin/cadvisor -logtostderr=true -port=8080`.
- `PROMISES.yaml`: 8 promises (`runtime.cadvisor-binary`, `runtime.static-binary`, `runtime.healthz-endpoint`, `runtime.metrics-endpoint`, `runtime.hc-binary`, `presence.shell`, `shape.size-budget`, `scan.nonzero-accepted`). `version: "0.1"`.
- **No `EXPECTATIONS.yaml`**: slim variant with no `scratch-base-trixie` dependency.
- `scan-baseline.json`: empty `critical_cves: []` initially; re-generated after first local build if the scan surfaces unavoidable debian-slim closure CVEs (precedent: forge-builder-trixie accepts a nonzero list).

### Why build from source

cadvisor is **not in Debian trixie**. Upstream ships only `gcr.io/cadvisor/cadvisor:latest` (Alpine/musl). Three options considered (full investigation in session transcript):

| Option | Shape | Decision |
|---|---|---|
| A. Build from Go source | `golang:1.27-trixie` → `debian:trixie-slim` static binary | **Chosen** — keeps Debian ecosystem story + Forge supply-chain ownership |
| B. Mirror upstream Alpine | `FROM gcr.io/cadvisor/cadvisor` + re-sign | Rejected — ships Alpine under a `-trixie` name (misleading) + no own supply-chain |
| C. Frankenstein overlay | `debian:trixie-slim` + Alpine's binary + musl libs | Rejected — ugly, defeats Debian story |

### Why static Go binary (CGO off)

cadvisor's `cmd/cadvisor` compiles without CGO when the optional `-tags libpfm` is absent. libpfm enables perf-event collection (hardware counters) — not needed for homelab container-metrics. Dropping it yields:

- **27 MB static binary** (vs. ~35 MB CGO binary with libpfm linked).
- **No dyn lib deps** → runtime libc ABI compatibility concerns disappear.
- **Simpler Dockerfile** → no libpfm4-dev install, no sha-pinned libpfm source tarball.
- **Smaller SBOM surface** → no C library attestation.

If a future consumer explicitly needs perf_event metrics, they can build a `cadvisor-libpfm-slim-trixie` variant alongside.

### Why NOT introduce `forge-builder-go-trixie` yet

Only **one** Go-source image exists after this ships (cadvisor). FG-025's forge-builder-trixie was justified because 4 scratch images already duplicated apt-upgrade. Premature abstraction (CLAUDE.md § design). Tracked in IDEAS.md with promotion trigger: 2nd Go-source image lands.

### Runtime shape

- **User**: root. cadvisor needs `/sys/fs/cgroup` read + `/var/lib/docker:ro` + `/:/rootfs:ro`. Upstream's runbook explicitly requires root or elaborate seccomp + device-group config. Homelab turnkey story keeps root.
- **Port**: 8080 (upstream default).
- **Healthcheck**: `/hc http://127.0.0.1:8080/healthz` (FG-031 pattern).
- **No config file**: default flags work; operators pass `-enable_metrics` etc. via compose `command:`.

### Smoke tests

7 scripts under `images/cadvisor-slim-trixie/tests/`:

- `smoke_binary_runs.sh` — `cadvisor -version` prints `cAdvisor version v0.60.6` (proves ldflags injection).
- `smoke_static_binary.sh` — `ldd /usr/bin/cadvisor` reports "not a dynamic executable" (CGO-off contract).
- `smoke_healthz.sh` — `scripts/smoke-server.sh` boot on :8080 with `/sys:/sys:ro`; `curl /healthz` returns `ok`.
- `smoke_metrics_endpoint.sh` — `/metrics` returns Prometheus text with `cadvisor_version_info` + `# TYPE cadvisor_` markers.
- `smoke_hc_healthcheck.sh` — HEALTHCHECK baked + healthy within 15s + closed-port guard-rail.
- `smoke_has_shell.sh` — `/bin/sh` present (slim contract).
- `smoke_size.sh` — ≤ 150 MB absolute ceiling (defers to `python-slim-trixie/tests/smoke_size.sh` — the shared size-check helper).

### Red acceptance test — `tests/acceptance/test_FG_044_cadvisor-slim-trixie.sh`

4 sections:

1. **Required files** — Dockerfile, image.yaml, PROMISES.yaml, scan-baseline.json, 7 smokes all present + executable.
2. **Build** — `bash scripts/build-image.sh cadvisor-slim-trixie` succeeds.
3. **Smoke suite** — all 7 smokes green.
4. **image.yaml invariants** — tag=0.60.6, platforms=[linux/amd64], no `depends_on`.

### `docs/CAPABILITIES.md`

- NEW `image.cadvisor-serves-metrics` — container-metrics endpoint on :8080 with cadvisor_version_info + container_* series when /sys mounted.
- NEW `build.from-go-source` — pattern for Go-source images: `golang:X-trixie` builder stage → `debian:trixie-slim` runtime → static Go binary + syft SBOM against source tree.

### `docs/stories/INDEX.md`

New row for FG-044.

### `docs/plan/IDEAS.md`

Add entry: `forge-builder-go-trixie` — Promote to a real FG-NNN when the 2nd Go-source image lands (Jaeger, Consul, Nomad, Grafana-agent, etc). Trigger: `grep -l 'FROM golang:' images/*/Dockerfile | wc -l >= 2`.

## Alternatives rejected

- **Mirror `gcr.io/cadvisor/cadvisor` and re-sign** — ships Alpine under the `-slim-trixie` name. Misleading. Forge gives up supply-chain ownership (binary built by Google's pipeline, not ours).
- **Frankenstein: Alpine binary + musl libs on Debian runtime** — ugly, defeats Debian ecosystem story, no cleaner than Option A.
- **CGO on + libpfm support** — adds a dyn dep (libpfm4), bigger binary, bigger SBOM, no homelab use case. Future consumer can opt-in via a parallel `-libpfm` variant.
- **Forge-builder-go-trixie now** — 1 consumer today; FG-025 precedent was 4+ consumers. Premature abstraction. IDEAS entry tracks the promotion trigger.
- **Scratch runtime** — ~30 MB savings over 100 MB slim; defer to FG-NNN follow-up (FG-037 → FG-043 pattern).
- **Non-root user** — upstream explicitly requires root or elaborate seccomp + device-group workaround. Homelab turnkey keeps root.

## Breaking changes

None.
- New image, no existing consumers.
- No API changes to other images.

## Merge plan

- All blocking gates pass.
- FG-044 acceptance test green (4 sections, 7 smokes).
- `scan-baseline.json` regenerated post-build if non-empty CRITICALs surface.
- `make test-fast` green.
- Pre-push `check-smart-strict` green.

## Rollout plan

1. Land FG-044 on `dev` via PR → autonomous merge on green CI.
2. Promote to `main` via `release.yml` (user triggers).
3. Daily cron publishes `:0.60.6` + `:latest`.
4. Operator adds `cadvisor` service to homelab compose stacks per host.
5. Prometheus config updated with scrape target(s); dashboards populate.

## Shipping evidence

| Item | Pointer | Status |
|------|---------|--------|
| Scenario: publishes with triple | `tests/acceptance/test_FG_044_...sh` § 1 + § 2 | ⏳ |
| Scenario: cadvisor -version reports v0.60.6 | § 3 + smoke_binary_runs.sh | ⏳ |
| Scenario: static Go binary | § 3 + smoke_static_binary.sh | ⏳ |
| Scenario: /healthz → "ok" | § 3 + smoke_healthz.sh | ⏳ |
| Scenario: /metrics + cadvisor_version_info | § 3 + smoke_metrics_endpoint.sh | ⏳ |
| Scenario: has shell | § 3 + smoke_has_shell.sh | ⏳ |
| Scenario: /hc HEALTHCHECK | § 3 + smoke_hc_healthcheck.sh | ⏳ |
| Scenario: size ≤ 150 MB | § 3 + smoke_size.sh | ⏳ |
| Scenario: homelab adoption | operator-side; documented in story § 9 happy path | ⏳ |
| NEW `image.cadvisor-serves-metrics` | `docs/CAPABILITIES.md` entry | ⏳ |
| NEW `build.from-go-source` | `docs/CAPABILITIES.md` entry | ⏳ |
