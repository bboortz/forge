# FG-034 — Plan: node-exporter-scratch-trixie

**Story**: [`docs/stories/FG-034-node-exporter-scratch-trixie.md`](../stories/FG-034-node-exporter-scratch-trixie.md)
**Status**: draft
**Branch**: `feat/FG-034-node-exporter-scratch-trixie`

## Design delta

### `images/node-exporter-scratch-trixie/` (new)

- `image.yaml`: tag `"1.9"`, platforms `[linux/amd64]`, `depends_on: [scratch-base-trixie]`.
- `Dockerfile`: two-stage.
  - Builder: `FROM forge-builder-trixie` → `apt-get install prometheus-node-exporter` → syft SBOM → stage overlay (binary + glibc-only lib closure from `ldd /usr/bin/prometheus-node-exporter`).
  - Runtime: `FROM scratch` overlay `scratch-base-trixie` then `/out`. `ENTRYPOINT ["/usr/bin/prometheus-node-exporter"]`, `USER 65532:65532`, `EXPOSE 9100`.
- `PROMISES.yaml`: promises for `runtime.binary-runs`, `runtime.metrics-endpoint-serves`, `runtime.user-nonroot`, `absence.shell`, `absence.os-cves`, `shape.size-budget` (≤ 30 MB). `version: "0.1"`.
- `EXPECTATIONS.yaml`: FG-010 contract on `scratch-base-trixie >= 0.2` for ld-linux + glibc.
- No sid pins (use trixie stock version).

### Smoke tests

- `smoke_binary_runs.sh` — `--entrypoint=/usr/bin/prometheus-node-exporter` with `--version`; expect `node_exporter, version 1.9.0`.
- `smoke_metrics_endpoint.sh` — boot via `scripts/smoke-server.sh` on port 9100, scrape with curl; assert `# TYPE node_` present AND at least one `node_.*_seconds_total` line present (minimal Prometheus-format check that works even without /proc host mount).
- `smoke_no_shell.sh` — standard pattern.
- `smoke_user_nonroot.sh` — `docker inspect` user == `65532:65532`.
- `smoke_size.sh` — hard ≤ 30 MB ceiling.
- `smoke_zero_os_cves.sh` — grype dpkg-source matches == 0.

### Acceptance test

`tests/acceptance/test_FG_034_node-exporter-scratch-trixie.sh`:
1. Required files present.
2. Build via `scripts/build-image.sh`.
3. Per-image smoke suite.
4. `image.yaml`: tag + `depends_on: [scratch-base-trixie]`.

### Homelab adoption notes

Current homelab usage (expected pattern):
```yaml
node-exporter:
  image: prom/node-exporter:latest
  pid: host
  network_mode: host
  volumes:
    - /proc:/host/proc:ro
    - /sys:/host/sys:ro
    - /:/rootfs:ro
  command:
    - '--path.procfs=/host/proc'
    - '--path.sysfs=/host/sys'
    - '--path.rootfs=/rootfs'
    - '--collector.filesystem.mount-points-exclude=^/(sys|proc|dev|host|etc)($$|/)'
```

Post-adoption: single-line `image:` swap. The Debian binary name is `/usr/bin/prometheus-node-exporter` (not `/bin/node_exporter`); the Forge image's `ENTRYPOINT` already resolves it, so no `command:` change is needed unless the consumer overrode the entrypoint.

### No workflow changes

`build.yml` discover job auto-detects the new image dir.

## Alternatives rejected

- **Pull binary from upstream `prom/node-exporter` Docker Hub image** — bypasses Debian's security tracking + patch cadence. The Debian package picks up CVE fixes via Debian Security Tracker; the upstream Docker Hub image follows prometheus upstream's cadence. We want Debian's.
- **Base on `-slim` (Debian runtime)** — bigger surface area; node_exporter doesn't need a shell or any apt-managed binary at runtime.
- **Add textfile collector scripts** — consumer concern; those scripts are shell + awk and don't fit in a scratch image.
- **Bake typical homelab command-line flags** (`--path.procfs=...`) — operator concern; different hosts have different mount setups.

## Breaking changes

None user-facing. New image, no existing consumers.

## Merge plan

- All blocking gates pass.
- FG-034 acceptance green.
- Image size baseline recorded.
- `scan-baseline.json` committed (expected: 0 CRITICAL for the scratch runtime).

## Rollout plan

1. Land on `dev` via PR.
2. Promote to `main` via `release.yml`.
3. Daily cron publishes `:1.9` + `:latest`.
4. Homelab PR: swap `image:` references across host compose files.

## Shipping evidence

| Item | Pointer | Status |
|------|---------|--------|
| Scenario: publishes with triple | `tests/acceptance/test_FG_034_...sh` § 1 | ⏳ |
| Scenario: /metrics responds with Prometheus text | § 3 + smoke_metrics_endpoint.sh | ⏳ |
| Scenario: no shell | § 3 + smoke_no_shell.sh | ⏳ |
| Scenario: nonroot uid 65532 | § 3 + smoke_user_nonroot.sh | ⏳ |
| Scenario: size ≤ 30 MB | § 3 + smoke_size.sh | ⏳ |
| Scenario: homelab compose swap | documented in plan + consumer-side PR | ⏳ |
| NEW CAP `image.node-exporter-serves-metrics` | `docs/CAPABILITIES.md` + acceptance + smokes | ⏳ |
