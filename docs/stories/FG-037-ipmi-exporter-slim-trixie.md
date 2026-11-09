---
id: FG-037
slug: ipmi-exporter-slim-trixie
status: shipped
owner: bboortz
created: 2026-11-08
---

# FG-037 — ipmi-exporter-slim-trixie

New Forge image: `ghcr.io/bboortz/ipmi-exporter-slim-trixie:1.10` — Prometheus IPMI Exporter 1.10.0 (from Debian trixie's `prometheus-ipmi-exporter` apt package) + `freeipmi-tools` 1.6.15 (ipmitool / ipmi-chassis / ipmi-sensors binaries), on a Debian-slim-trixie **runtime** (not scratch). Enables homelab's per-host IPMI metrics collection (fan speeds, voltages, temperatures, power draw) with a signed/scanned/attested Forge base replacing `prometheuscommunity/ipmi-exporter:latest`.

**Why slim, not scratch**: `prometheus-ipmi-exporter` shells out to `freeipmi-tools` binaries (`/usr/sbin/ipmimonitoring`, `/usr/sbin/ipmi-sel`, `/usr/sbin/ipmi-dcmi`, etc.) which link against libc + libfreeipmi + libgcrypt + libgpg-error + ... The dynamic closure is large and intertwined; replicating it in a scratch overlay would add every dpkg-tracked lib and much of their config without reducing surface area meaningfully. Debian-slim-trixie is the right shape — matches `postgres-slim-trixie` / `python-slim-trixie` precedent.

## 9 canonical answers

1. **Who** — homelab operator (me) running one ipmi-exporter container per IPMI-capable host (servers with BMCs). Secondary: any Forge consumer running IPMI metrics collection.

2. **When** — fires at every ipmi-exporter boot; at every prometheus scrape of `/metrics`; at every IPMI probe to `/dev/ipmi0` (or remote BMC via `--config.file`). Pipeline: next 03:00 UTC cron after this lands on `main`.

3. **What success looks like**:
   - `ghcr.io/bboortz/ipmi-exporter-slim-trixie:1.10` publishes daily with cosign + SBOM + scan attestations.
   - `docker run --rm -p 9290:9290 --device /dev/ipmi0 --privileged <image>` boots the exporter.
   - `curl http://localhost:9290/metrics` returns Prometheus text format with at least `ipmi_scrape_duration_seconds` present (self-metric, independent of real IPMI device).
   - `curl http://localhost:9290/ipmi?target=hostname` initiates an IPMI probe (requires `/dev/ipmi0` or a `config.yml` with BMC credentials).
   - Image size ≤ 200 MB (Debian base ~80 MB + freeipmi-tools ~30 MB + exporter binary ~15 MB + overhead).
   - grype's dpkg scan runs against the slim base; **nonzero expected** (shell + apt still in the image) — but `scan-baseline.json` captures the accepted CVE set.
   - Homelab compose line swap: `image: prometheuscommunity/ipmi-exporter:latest` → `image: ghcr.io/bboortz/ipmi-exporter-slim-trixie:1.10`. Device mount + port unchanged.

4. **Urgency** — quality-of-life + supply-chain. IPMI exporters on homelab hosts have been running the upstream community image; switching to the Forge build ties patch cadence to Debian's security tracker + adds the signed triple.

5. **Happy path**:
   1. Forge daily cron publishes `:1.10` + `:latest`.
   2. Homelab compose updates `image:` reference.
   3. Container boots with `--device /dev/ipmi0` (local BMC) or `-v $(pwd)/ipmi-config.yml:/etc/prometheus/ipmi-exporter.yml:ro` (remote BMC credentials).
   4. Prometheus continues scraping `:9290` (and/or targeted `:9290/ipmi?target=<bmc>`) without config change.

6. **Edge cases / failure modes**:
   - **Shell is present** — unlike scratch images, slim-trixie keeps `/bin/sh`, `apt`, `coreutils`. Smoke test `smoke_no_shell.sh` does NOT apply; `smoke_has_shell.sh` (positive assertion) does.
   - **`/dev/ipmi0` device mount** — consumer concern; smoke runs without the device and asserts the exporter still responds on `/metrics` (self-metrics only, no actual IPMI probe). No device → scrape returns an error metric, which is fine for smoke validation.
   - **Privileged vs. --device** — `--device /dev/ipmi0` is cleaner than `--privileged`; both work. Document the `--device` pattern in README.
   - **Config file format** — ipmi-exporter uses its own YAML config at `/etc/prometheus/ipmi-exporter.yml`. Ship a minimal default that specifies `modules.default: { collectors: [...] }` so `/metrics` works without a user-provided config.
   - **CVE surface** — slim images inherit the full dpkg closure; zero-CVE is NOT a design goal. scan-baseline captures reality; scan-regression gate fires only on NEW CRITICALs vs baseline.
   - **ipmitool vs freeipmi-tools** — prometheus-ipmi-exporter uses the freeipmi-tools family (`ipmimonitoring`, `ipmi-sel`, etc.), not the `ipmitool` binary. Install the correct package.

7. **Out of scope**:
   - A scratch variant (`ipmi-exporter-scratch-trixie`). The dynamic closure of freeipmi-tools makes scratch impractical without replicating most of the Debian base. Revisit if the exporter ever gets a static Go rewrite.
   - Baking IPMI credentials. Consumer secret material via mounted config file.
   - Remote BMC-only mode without local `/dev/ipmi0` — supported by the exporter itself, consumer-configured.
   - Kernel modules (`ipmi_msghandler`, `ipmi_devintf`) — host-side concern, consumer loads them on the host.

8. **How we know it's done** — see Gherkin below.

9. **Capabilities delivered or extended**:
   - NEW `image.ipmi-exporter-serves-metrics` — image runs ipmi-exporter with freeipmi-tools deps; responds to `/metrics` even without an IPMI device; initiates IPMI probes when `/dev/ipmi0` or remote BMC config is provided.
   - EXT `image.has-shell` — another slim-trixie derivative keeping apt + shell at runtime (matches postgres-slim + python-slim).
   - EXT `scan.regression-gate` — scan-baseline with a nonzero-but-accepted CVE set (precedent: forge-builder-trixie's upstream syft CVE recorded as baseline).

## Gherkin acceptance

```
Scenario: ipmi-exporter-slim-trixie:1.10 publishes with the standard triple
  Given a successful build.yml publish cycle
  When the image resolves on GHCR
  Then cosign verify succeeds with the standard --certificate-identity
   And the SBOM attestation lists prometheus-ipmi-exporter 1.10.0 + freeipmi-tools 1.6.15
   And the grype attestation is attached (nonzero CVEs expected, all captured in scan-baseline)

Scenario: /metrics responds even without /dev/ipmi0
  Given a running forge-local/ipmi-exporter-slim-trixie:1.10 with no device mount
  When `curl http://localhost:9290/metrics` runs
  Then the response is HTTP 200
   And the body contains `ipmi_scrape_duration_seconds` (self-metric)

Scenario: freeipmi-tools binaries are present
  Given a running container
  When `docker exec <container> ls /usr/sbin/` runs
  Then the output contains `ipmimonitoring`, `ipmi-sel`, `ipmi-dcmi`

Scenario: ipmi-exporter config check works
  Given a running container
  When `docker exec <container> /usr/bin/prometheus-ipmi-exporter --config.file=/etc/prometheus/ipmi-exporter.yml --help` runs
  Then the exit code is 0
   And stdout mentions `--web.listen-address`

Scenario: Image KEEPS a shell (slim contract)
  Given the built image
  When `docker run --entrypoint=/bin/sh <image> -c 'echo ok'` runs
  Then the exit code is 0
   And stdout is "ok"

Scenario: Image size within budget
  Given the built image
  Then image size ≤ 200 MB

Scenario: Homelab compose swap works
  Given a homelab compose referencing prometheuscommunity/ipmi-exporter:latest
  When the `image:` line is swapped to ghcr.io/bboortz/ipmi-exporter-slim-trixie:1.10
  Then `docker compose up -d` boots the container successfully
   And prometheus continues to scrape :9290/metrics without config change
```

## References

- Plan: `docs/plan/FG-037-ipmi-exporter-slim-trixie-plan.md`
- Red test: `tests/acceptance/test_FG_037_ipmi-exporter-slim-trixie.sh`
- Capabilities: `docs/CAPABILITIES.md` (NEW `image.ipmi-exporter-serves-metrics`)
- Upstream: Debian trixie `prometheus-ipmi-exporter` 1.10.0-2+b4 + `freeipmi-tools` 1.6.15-1
- Reference pattern: FG-026 (postgres-slim-trixie — slim variant for shell-requiring workflows), FG-031 (retained slim images for operator ergonomics)
