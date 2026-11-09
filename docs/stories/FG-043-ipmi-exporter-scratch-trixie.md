---
id: FG-043
slug: ipmi-exporter-scratch-trixie
status: draft
owner: bboortz
created: 2026-11-09
---

# FG-043 — ipmi-exporter-scratch-trixie (alongside slim variant)

FG-037 shipped `ipmi-exporter-slim-trixie:1.10` on debian:trixie-slim and framed scratch as impractical ("freeipmi-tools' dynamic closure is too intertwined"). Deep verification 2026-11-09 proved that framing wrong:

- The exporter execs **only ELF binaries** at runtime (`bmc-info`, `ipmi-sensors`, `ipmi-chassis`, `ipmi-dcmi`, `ipmi-sel`). The shell-script wrapper `ipmimonitoring` exists in Debian's package but the exporter doesn't call it.
- Dynamic-lib closure is **4 libs not in baseline** (`libfreeipmi.so.17`, `libgcrypt.so.20`, `libgpg-error.so.0`, `libipmidetect.so.0`) totaling ~5 MB. Same shape as postgres-scratch-trixie's overlay (libicu/libkrb5/libldap stack).
- Overlay total: ~20 MB. Projected final image size: **~33 MB (vs slim's 107 MB — 3.3× smaller)**.

FG-043 ships `ipmi-exporter-scratch-trixie:1.10` alongside the existing slim variant. Operators pick: scratch for zero-OS-CVE alignment with the rest of the exporter fleet (node-exporter, prometheus, alertmanager all scratch), slim for `docker exec -it sh` ergonomics.

Target deployment: homelab hosts `hetzner-staging` + `server2` (both already carry `/dev/ipmi0` per `~/git/homelab/systemd/ipmi/` systemd services).

## 9 canonical answers

1. **Who** — homelab operator (me) first, deploying on `hetzner-staging` + `server2`. Secondary: any Forge consumer wanting a minimal IPMI exporter aligned with the rest of the scratch exporter fleet.

2. **When** — fires at every `docker compose up` on an IPMI-capable host + every prometheus scrape cycle. Pipeline: next 03:00 UTC cron after this lands on `main`.

3. **What success looks like**:
   - `ghcr.io/bboortz/ipmi-exporter-scratch-trixie:1.10` publishes daily with cosign + SBOM + scan attestations.
   - `docker run --rm -d --device /dev/ipmi0 --privileged -p 9290:9290 <image>` on hetzner-staging or server2 boots → `curl /metrics` returns Prometheus text with `ipmi_*` metrics populated (temperatures, fan speeds, voltages, power).
   - `docker run --rm -d -p 9290:9290 <image>` without the device still responds to `/metrics` (self-metrics only; `ipmi_scrape_duration_seconds` always present).
   - Image size ≤ 50 MB (projected ~33 MB; budget allows headroom).
   - grype scan: **zero OS CVEs** (vs slim's 7 accepted CRITICAL).
   - Homelab compose line swap: `image: ghcr.io/bboortz/ipmi-exporter-slim-trixie:1.10` → `image: ghcr.io/bboortz/ipmi-exporter-scratch-trixie:1.10`. Same compose volumes, devices, ports. No other changes.
   - FG-037's slim variant stays published — operators who need debug shell keep it.

4. **Urgency** — quality-of-life + supply chain. Current slim ships with 7 accepted CRITICAL CVEs (freeipmi + debian-slim closure). Scratch eliminates those. Not emergency; ship when touching the image.

5. **Happy path**:
   1. Forge daily cron publishes `:1.10` + `:latest`.
   2. Homelab compose on hetzner-staging + server2 updates `image:` reference.
   3. `docker compose up -d` — container boots as root (needed for `/dev/ipmi0`), scrapes BMC via freeipmi tools, exposes `:9290/metrics`.
   4. Existing prometheus server picks up the new target metrics without config change.

6. **Edge cases / failure modes**:
   - **Operator customizes `ipmi-exporter.yml` with `command: ipmimonitoring`** — the shell-script wrapper. Scratch has no shell, so this fails. Document: the default collector set + any `command:` field pointing at a real ELF binary (`ipmi-sensors`, `bmc-info`, `ipmi-chassis`, `ipmi-dcmi`, `ipmi-sel`, `ipmi-raw`) works; `ipmimonitoring` + `ipmi-chassis-config` + `ipmi-pef-config` + `ipmi-sensors-config` (all shell scripts in Debian's freeipmi-tools) do not. Operators needing those keep slim.
   - **`/var/lib/freeipmi/` IPC key** — `ipmi-sensors` writes an IPC key here. Scratch runtime needs this dir writable + owned root. Dockerfile `install -d` with mode 0755 pre-creates it; works because we run as root (required for `/dev/ipmi0`).
   - **Writable /tmp** — baseline (scratch-base-trixie) provides `/tmp` at 1777. freeipmi subprocesses use it for ephemeral files.
   - **No `curl`/`wget` for `docker exec` healthcheck** — handled by `/hc` (FG-031 pattern); baked HEALTHCHECK polls `/metrics`.
   - **BMC accessibility varies per host** — hetzner-staging is a dedicated Hetzner server (direct BMC access); server2 is similar. Both expose `/dev/ipmi0` to the OS. Smoke tests the IMAGE contract; runtime verification on the hosts is the operator's step (documented).

7. **Out of scope**:
   - **Deprecating `ipmi-exporter-slim-trixie`**. Kept published; operators who need debug shell OR who rely on shell-script freeipmi tools (`ipmimonitoring`, `*-config` wrappers) stay on slim.
   - Shipping `ipmi-raw` or `bmc-watchdog`. Default collector set (`bmc + ipmi + chassis + dcmi + sel`) covers homelab's use case. Can be added if an operator config requires them.
   - Remote-BMC mode (via `--config.file` with user/pass). Operator-side configuration; image is mode-agnostic.
   - Multi-arch. amd64-only matches every other Forge image.
   - Testing against actual IPMI hardware from CI. Not feasible without host access; smokes validate IMAGE contract, operator validates per-host.

8. **How we know it's done** — see Gherkin below.

9. **Capabilities delivered or extended**:
   - EXT `image.ipmi-exporter-serves-metrics` — scratch variant extends the CAP (same contract; smaller image, no shell).
   - NEW `image.ipmi-exporter-scratch-nonroot-exempt` — explicit documentation that this specific scratch image runs as **root** (not the baseline uid 65532 default). `/dev/ipmi0` requires root; non-root is impossible without host-side device-group changes. Flagged so future scratch audits don't mis-flag this as a regression.

## Gherkin acceptance

```
Scenario: ipmi-exporter-scratch-trixie:1.10 publishes with the standard triple
  Given a successful build.yml publish cycle
  When the image resolves on GHCR
  Then cosign verify succeeds with the standard --certificate-identity
   And the SBOM lists prometheus-ipmi-exporter 1.10.0 + freeipmi-tools 1.6.15
   And the grype scan is attached with ZERO Debian-source matches (scratch, no dpkg DB)

Scenario: All 5 freeipmi ELF binaries are shipped
  Given the built image
  When the image contents are inspected via `docker save | tar tf`
  Then /usr/sbin/bmc-info, ipmi-sensors, ipmi-chassis, ipmi-dcmi, ipmi-sel are all present

Scenario: /metrics responds without /dev/ipmi0 (self-metrics only)
  Given a running forge-local/ipmi-exporter-scratch-trixie:1.10 (no device mount)
  When `curl http://localhost:9290/metrics` runs
  Then the response is HTTP 200
   And the body contains `ipmi_scrape_duration_seconds` (self-metric from exporter)
   And the body contains `# TYPE ipmi_` (Prometheus format marker)

Scenario: Image has NO shell
  Given the built image
  When common shell paths are probed via docker run --entrypoint
  Then /bin/sh, /bin/bash, /bin/dash, /usr/bin/sh all fail to exec

Scenario: /hc baked HEALTHCHECK polls /metrics
  Given the built image
  When `docker inspect --format {{.Config.Healthcheck.Test}}` is read
  Then it contains "/hc" and "/metrics" and "127.0.0.1:9290"
   And a running container becomes `healthy` within 15s

Scenario: Runs as root (documented exception; /dev/ipmi0 requires it)
  Given the built image
  When `docker inspect --format {{.Config.User}}` is read
  Then it is "" (default root) — NOT 65532 like other scratch images

Scenario: Zero OS CVEs (scratch contract)
  Given the built image
  When grype -o json scans it
  Then there are zero Debian-source matches

Scenario: Image size within budget
  Given the built image
  Then image size ≤ 50 MB

Scenario: hetzner-staging / server2 adoption (operator-side, documented)
  Given hetzner-staging or server2 with /dev/ipmi0 readable
  When operator runs `docker run --rm -d --device /dev/ipmi0 --privileged ghcr.io/bboortz/ipmi-exporter-scratch-trixie:latest`
   And `curl http://localhost:9290/metrics` is called
  Then the response contains real `ipmi_*` metrics populated from the BMC (temperatures, fan speeds, voltages)
   And the operator reports back by filing a GitHub issue if the metrics are missing or wrong

Scenario: FG-037 slim variant still works (no regression)
  Given the FG-037 acceptance test
  When re-run against the current slim image
  Then every assertion still passes (both variants coexist on GHCR)
```

## References

- Plan: `docs/plan/FG-043-ipmi-exporter-scratch-trixie-plan.md`
- Red test: `tests/acceptance/test_FG_043_ipmi-exporter-scratch-trixie.sh`
- Predecessor: FG-037 (slim variant; initial assessment that scratch was impractical — corrected by this story)
- Homelab deployment targets: `hetzner-staging` + `server2` (both carry /dev/ipmi0 per `~/git/homelab/systemd/ipmi/`)
- Upstream: Debian trixie `prometheus-ipmi-exporter 1.10.0-2+b4` + `freeipmi-tools 1.6.15-1`
