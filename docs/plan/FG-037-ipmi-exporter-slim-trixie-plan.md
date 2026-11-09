# FG-037 — Plan: ipmi-exporter-slim-trixie

**Story**: [`docs/stories/FG-037-ipmi-exporter-slim-trixie.md`](../stories/FG-037-ipmi-exporter-slim-trixie.md)
**Status**: shipped
**Branch**: `feat/FG-037-ipmi-exporter-slim-trixie`

## Design delta

### `images/ipmi-exporter-slim-trixie/` (new)

- `image.yaml`: tag `"1.10"`, platforms `[linux/amd64]`. **No `depends_on`** — this image is single-stage Debian-slim-trixie, not a scratch derivative.
- `Dockerfile`: single-stage.
  - `FROM debian:trixie-slim` (NOT forge-builder-trixie — that has python + syft we don't need in the runtime).
  - Install: `prometheus-ipmi-exporter`, `freeipmi-tools`, `ca-certificates` (the exporter can be configured for HTTPS pushgateway).
  - `apt-get -y --no-install-recommends upgrade` first (freshly-patched runtime).
  - `rm -rf /var/lib/apt/lists/*` after install.
  - Pre-create `/etc/prometheus/ipmi-exporter.yml` with a minimal default-module config so `docker run` succeeds.
  - `ENTRYPOINT ["/usr/bin/prometheus-ipmi-exporter"]`, `CMD ["--config.file=/etc/prometheus/ipmi-exporter.yml", "--web.listen-address=:9290"]`, `EXPOSE 9290`.
  - `USER` default: this is the tricky bit. ipmi-exporter typically needs root to open `/dev/ipmi0` (Debian default device perms). Two options: (a) stay as root (upstream default), (b) ship a `freeipmi` group + chgrp `/dev/ipmi0` dance (host-side; can't do in-image). Ship as root; document that privileged + `--device /dev/ipmi0` is the standard homelab pattern.
- `PROMISES.yaml` (new): `runtime.ipmi-exporter-binary`, `runtime.metrics-endpoint-serves`, `runtime.freeipmi-tools-bundled`, `runtime.config-file-valid`, `presence.shell` (slim-contract — explicit positive promise), `shape.size-budget` (≤ 200 MB). `version: "0.1"`.
- **No `EXPECTATIONS.yaml`** — doesn't derive from scratch-base-trixie.
- `scan-baseline.json`: generated post-build; expected to list several accepted CRITICALs (Debian slim base + freeipmi closure).

### Smoke tests

- `smoke_binary_runs.sh` — `prometheus-ipmi-exporter --version` prints `ipmi_exporter, version 1.10.0`.
- `smoke_metrics_endpoint.sh` — boot without device mount, scrape `/metrics`, assert `ipmi_scrape_duration_seconds` appears.
- `smoke_freeipmi_tools.sh` — `docker exec <CID> ls /usr/sbin/` lists `ipmimonitoring` + `ipmi-sel` + `ipmi-dcmi`.
- `smoke_config_valid.sh` — `docker exec <CID> /usr/bin/prometheus-ipmi-exporter --config.file=/etc/prometheus/ipmi-exporter.yml --help` exits 0.
- `smoke_has_shell.sh` — positive assertion: `/bin/sh -c 'echo ok'` works (slim contract).
- `smoke_size.sh` — ≤ 200 MB.
- `smoke_scan_against_baseline.sh` — standard scan-regression check against committed baseline.

### Default `ipmi-exporter.yml`

Minimal baked at `/etc/prometheus/ipmi-exporter.yml`:
```yaml
modules:
  default:
    collectors:
      - bmc
      - ipmi
      - chassis
```
Operators mount their own in prod. The baked default lets smoke tests boot the exporter without an operator config.

### Acceptance test

`tests/acceptance/test_FG_037_ipmi-exporter-slim-trixie.sh` — 4 sections.

## Alternatives rejected

- **Scratch runtime** — freeipmi-tools' dynamic closure (libfreeipmi, libgcrypt, libgpg-error, libgsasl, ...) would require replicating most of the Debian base in a `/out` overlay. For an operator-privileged container that already needs `--device` or `--privileged`, the attack-surface-reduction win from scratch is marginal. Keep slim.
- **Base on `forge-builder-trixie`** — carries python + syft we don't need. `debian:trixie-slim` is leaner.
- **Pull binary from upstream `prometheuscommunity/ipmi-exporter`** — upstream community image uses an older freeipmi version and lacks Debian's security backport pipeline.
- **Ship non-root user** — upstream and real-world homelab deployments run as root to access `/dev/ipmi0` or load kernel helpers. Non-root is incompatible with the local-BMC use case without host-side device-group changes.

## Breaking changes

None user-facing — new image, no existing Forge consumers.

## Merge plan

- All blocking gates pass.
- Acceptance test green.
- `scan-baseline.json` committed (expected nonzero CRITICAL list; documented as acceptable per the slim contract).
- Image size recorded.

## Rollout plan

1. Land on `dev` via PR.
2. Promote to `main` via `release.yml`.
3. Daily cron publishes.
4. Homelab PR swaps `image:` reference on each IPMI-capable host's compose.

## Shipping evidence

| Item | Pointer | Status |
|------|---------|--------|
| Scenario: publishes with triple | `tests/acceptance/test_FG_037_...sh` § 1 | ⏳ |
| Scenario: /metrics without /dev/ipmi0 | § 3 + smoke_metrics_endpoint.sh | ⏳ |
| Scenario: freeipmi-tools binaries present | § 3 + smoke_freeipmi_tools.sh | ⏳ |
| Scenario: config check | § 3 + smoke_config_valid.sh | ⏳ |
| Scenario: shell KEPT (slim contract) | § 3 + smoke_has_shell.sh | ⏳ |
| Scenario: size ≤ 200 MB | § 3 + smoke_size.sh | ⏳ |
| Scenario: homelab compose swap | documented + consumer-side PR | ⏳ |
| NEW CAP `image.ipmi-exporter-serves-metrics` | `docs/CAPABILITIES.md` + acceptance + smokes | ⏳ |
