# FG-043 — Plan: ipmi-exporter-scratch-trixie

**Story**: [`docs/stories/FG-043-ipmi-exporter-scratch-trixie.md`](../stories/FG-043-ipmi-exporter-scratch-trixie.md)
**Status**: draft
**Branch**: `feat/FG-043-ipmi-exporter-scratch`

## Design delta

### `images/ipmi-exporter-scratch-trixie/` (new)

Mirrors FG-037 slim's directory layout but produces a scratch runtime.

- `image.yaml`: tag `"1.10"`, platforms `[linux/amd64]`, `depends_on: [scratch-base-trixie]`.
- `Dockerfile`: two-stage.
  - Builder: `FROM forge-builder-trixie` → `apt install prometheus-ipmi-exporter freeipmi-tools` → syft SBOM → stage overlay (binaries + 4 libs + writable dirs + default config).
  - Runtime: `FROM scratch` → overlay `scratch-base-trixie` then `/out`. Runs as **root** (documented exception; `/dev/ipmi0` requires it).
- `PROMISES.yaml`: `runtime.ipmi-exporter-binary`, `runtime.freeipmi-elf-tools-bundled` (5 named: bmc-info, ipmi-sensors, ipmi-chassis, ipmi-dcmi, ipmi-sel), `runtime.metrics-endpoint`, `runtime.hc-binary`, `runtime.root-documented-exception`, `absence.shell`, `absence.os-cves`, `shape.size-budget` (≤ 50 MB). `version: "0.1"`.
- `EXPECTATIONS.yaml`: scratch-base-trixie ≥ 0.2 (ld-linux, glibc + libm, /etc/passwd root, /tmp 1777).
- `ipmi-exporter.yml`: default config with `collectors: [bmc, ipmi, chassis, dcmi, sel]` (matches FG-037 slim's default; all ELF-binary-backed).

### Binaries shipped

Just the 5 default-collector binaries + the exporter. Operators who need `ipmi-raw` or `bmc-watchdog` configure slim. Shell-script tools (`ipmimonitoring`, `ipmi-chassis-config`, etc) excluded by design.

```
/usr/bin/prometheus-ipmi-exporter   13.2 MB (Go)
/usr/sbin/bmc-info                  171 KB
/usr/sbin/ipmi-sensors              231 KB
/usr/sbin/ipmi-chassis              173 KB
/usr/sbin/ipmi-dcmi                 173 KB
/usr/sbin/ipmi-sel                  195 KB
                                    ─────
                                   ~14 MB
```

### Libs to add to overlay (not in baseline)

```
/lib/x86_64-linux-gnu/libfreeipmi.so.17       (follow symlink → real file ~4 MB)
/lib/x86_64-linux-gnu/libgcrypt.so.20         (~1 MB)
/lib/x86_64-linux-gnu/libgpg-error.so.0       (~100 KB)
/lib/x86_64-linux-gnu/libipmidetect.so.0      (~50 KB)
```

`libc.so.6` + `libm.so.6` already in baseline.

### Writable runtime dirs

- `/var/lib/freeipmi/` (0755 root) — freeipmi IPC key
- `/var/log/freeipmi/` (0755 root) — freeipmi logs
- `/tmp` (1777) — provided by baseline

### Smoke tests

All smokes use the `docker save | tar tf` pattern + `docker run --entrypoint=<binary>` pattern (NOT `docker exec -it sh` — no shell available).

- `smoke_binary_runs.sh` — `prometheus-ipmi-exporter --version` prints `ipmi_exporter, version 1.10.0`.
- `smoke_metrics_endpoint.sh` — `scripts/smoke-server.sh` boot on :9290; `curl /metrics` returns `# TYPE ipmi_` + `ipmi_scrape_duration_seconds`.
- `smoke_freeipmi_tools.sh` — contents check via `docker save | tar tf` asserts every one of the 5 ELF binaries present under `/usr/sbin/`.
- `smoke_hc_healthcheck.sh` — `docker inspect` carries `/hc` + `/metrics` + `:9290` in HEALTHCHECK. Container becomes healthy within 15s.
- `smoke_no_shell.sh` — standard (verifies `/bin/sh` etc. are absent).
- `smoke_user_root.sh` — `docker inspect` `Config.User` is "" (default root). Documents the exception; future audits don't flag it.
- `smoke_size.sh` — ≤ 50 MB absolute ceiling (projected ~33 MB; 50 MB gives headroom for future freeipmi growth).
- `smoke_zero_os_cves.sh` — grype `-o json` reports 0 Debian-source matches (scratch, no dpkg DB).

### Host-adoption test (documented, not CI-executed)

`docs/adoption/FG-043-homelab-adoption.md` carries the hetzner-staging + server2 operator-verification recipe:

```yaml
services:
  ipmi-exporter:
    image: ghcr.io/bboortz/ipmi-exporter-scratch-trixie:latest
    restart: unless-stopped
    devices:
      - /dev/ipmi0:/dev/ipmi0
    privileged: true   # OR drop and add --cap-add=SYS_RAWIO + fine-grained device perms
    ports:
      - "9290:9290"
```

Operator verification steps per host:
1. SSH to `hetzner-staging` (or `server2`).
2. `curl -sf http://localhost:9290/metrics | grep 'ipmi_temperature' | head`.
3. Expect at least one temperature reading (CPU inlet or exhaust) with a plausible value (0 < T < 150 °C).
4. If zero `ipmi_*` metrics appear → `docker logs ipmi-exporter` + check `dmesg | grep -i ipmi` on host for driver presence.
5. File GitHub issue if BMC-accessible metrics are missing.

Can't execute from CI. Documented as part of the shipping evidence.

### Red acceptance test — `tests/acceptance/test_FG_043_ipmi-exporter-scratch-trixie.sh`

5 sections:

1. **Required files** — Dockerfile, image.yaml, PROMISES.yaml, EXPECTATIONS.yaml, ipmi-exporter.yml, scan-baseline.json, 8 smokes all present + executable.
2. **Build** — `bash scripts/build-image.sh ipmi-exporter-scratch-trixie` succeeds.
3. **Smoke suite** — all 8 smokes green.
4. **image.yaml invariants** — tag=1.10, depends_on=[scratch-base-trixie].
5. **FG-037 regression** — `test_FG_037_ipmi-exporter-slim-trixie.sh` still passes (slim coexists).

### `docs/CAPABILITIES.md`

- EXT `image.ipmi-exporter-serves-metrics` — now has both slim and scratch variants.
- NEW `image.ipmi-exporter-scratch-nonroot-exempt` — explicit entry documenting why this specific scratch image runs as root (vs baseline uid 65532). Prevents future "why isn't this nonroot?" audit confusion.

### `docs/stories/INDEX.md`

New row for FG-043.

## Alternatives rejected

- **Replace slim with scratch (deprecate slim)** — slim still has value for operators who need `docker exec -it sh` or shell-script freeipmi tools. Zero cost to ship both; let operators choose.
- **Ship `ipmi-raw` + `bmc-watchdog` too** — not in default collector set; adds ~200 KB. Scope-creep; can add in a follow-up if an operator hits it.
- **Ship `ipmimonitoring` shell script + a tiny shell** — defeats the no-shell contract. Operators who need `ipmimonitoring` use slim.
- **Use `cp -L` for libs** — plain `cp` already dereferences symlinks on GNU coreutils (default). `-L` is redundant but harmless. Use plain `cp` to match other scratch Dockerfiles' convention.
- **Non-root via host-side device group** — requires every host to `chgrp ipmi /dev/ipmi0` + add user. Complicates deployment for marginal security win (container already needs `--privileged` or `--cap-add=SYS_RAWIO` anyway). Keep root; document the exception explicitly.
- **Test on actual hetzner-staging/server2 from CI** — no SSH credentials in CI. Operator-side verification is the right split.

## Breaking changes

None.
- New image, no existing consumers.
- FG-037 slim stays published.
- No API changes to other images.

## Merge plan

- All blocking gates pass.
- FG-043 acceptance test green (5 sections, 8 smokes, FG-037 regression).
- `scan-baseline.json` committed (expected 0 CRITICAL CVEs — scratch has no dpkg DB).
- `make test-fast` green.
- Pre-push `check-smart-strict` green.

## Rollout plan

1. Land FG-043 on `dev` via PR.
2. Promote to `main` via `release.yml`.
3. Daily cron publishes `:1.10` + `:latest`.
4. Operator deploys on hetzner-staging via compose swap.
5. Operator verifies real `ipmi_*` metrics populate from BMC.
6. If successful, operator deploys on server2 via same pattern.
7. FG-037 slim variant remains published indefinitely (coexistence).

## Shipping evidence

| Item | Pointer | Status |
|------|---------|--------|
| Scenario: publishes with triple | `tests/acceptance/test_FG_043_...sh` § 1 + § 2 | ⏳ |
| Scenario: 5 freeipmi ELF binaries shipped | § 3 + smoke_freeipmi_tools.sh | ⏳ |
| Scenario: /metrics without /dev/ipmi0 | § 3 + smoke_metrics_endpoint.sh | ⏳ |
| Scenario: no shell | § 3 + smoke_no_shell.sh | ⏳ |
| Scenario: /hc HEALTHCHECK | § 3 + smoke_hc_healthcheck.sh | ⏳ |
| Scenario: runs as root (documented) | § 3 + smoke_user_root.sh | ⏳ |
| Scenario: zero OS CVEs | § 3 + smoke_zero_os_cves.sh | ⏳ |
| Scenario: size ≤ 50 MB | § 3 + smoke_size.sh | ⏳ |
| Scenario: hetzner-staging / server2 adoption | operator-side; documented in story § 9 happy path | ⏳ |
| Scenario: FG-037 regression | § 5 (re-runs test_FG_037) | ⏳ |
| EXT `image.ipmi-exporter-serves-metrics` | `docs/CAPABILITIES.md` extension | ⏳ |
| NEW `image.ipmi-exporter-scratch-nonroot-exempt` | `docs/CAPABILITIES.md` entry | ⏳ |
