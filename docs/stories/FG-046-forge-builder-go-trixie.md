---
id: FG-046
slug: forge-builder-go-trixie
status: shipped
owner: bboortz
created: 2026-11-10
---

# FG-046 — forge-builder-go-trixie + migrate all-but-one Go image

Beaconry's 2026-11-10 scan flagged `GO-2026-6604` (CVE-2026-56857) on three Forge scratch images — the latest in a growing pile of Go stdlib CVEs inherited from Debian trixie's lagging Go toolchain (go1.24.x). Full picture after a fresh grype DB refresh:

| CVE | Scope | Debian go1.24 affected? | Go 1.27 affected? |
|---|---|---|---|
| GO-2025-3563 | net/http chunked request smuggling | ✓ | ✗ |
| GO-2026-4337 | crypto/tls session resumption | ✓ | ✗ |
| GO-2026-6604 | os.Root.Mkdir Windows junction (windows-only) | ✓ | ✗ |
| GO-2026-6612 | net/http HTTP/2 flow control | ✓ | ✗ |

Since the Debian-packaged binaries (`prometheus-ipmi-exporter`, `prometheus-alertmanager`, `prometheus`, `prometheus-node-exporter`) embed the Debian-shipped stdlib at build time, every one of them carries all four CVEs. Fix lands when Debian bumps their Go toolchain and rebuilds — can take months. The alternative is: build from upstream source with a newer Go toolchain ourselves.

This story introduces `forge-builder-go-trixie` as the shared Go builder base (sibling to FG-025's `forge-builder-trixie`) and migrates every Forge-native from-Go image to use it:

| Image | Previous | After this story | Go stdlib before → after | Stdlib CRITICAL CVEs |
|---|---|---|---|---|
| `cadvisor-slim-trixie` | `FROM golang:1.27-trixie` direct | `FROM forge-builder-go-trixie` | go1.27.x → go1.27.3 (toolchain unification) | 0 → 0 |
| `node-exporter-scratch-trixie` | Debian `prometheus-node-exporter` binary | Built from upstream v1.9.0 Go source | go1.24.4 → go1.27.3 | 2 → 0 |
| `alertmanager-scratch-trixie` | Debian `prometheus-alertmanager` binary | Built from upstream v0.28.1 Go source | go1.24.1 → go1.27.3 | 3 → 0 |
| `ipmi-exporter-scratch-trixie` | Debian `prometheus-ipmi-exporter` binary | Built from upstream v1.10.0 Go source + Debian freeipmi overlay | go1.24.4 → go1.27.3 | 2 → 0 |
| `ipmi-exporter-slim-trixie` | Debian `prometheus-ipmi-exporter` binary | Built from upstream v1.10.0 Go source + Debian freeipmi apt-install | go1.24.4 → go1.27.3 | 2 → 0 |
| **`prometheus-scratch-trixie`** | Debian `prometheus` binary | **DEFERRED — deferred migration** (upstream build requires npm build pipeline for React UI; low-benefit-high-cost for this PR; existing Go-stdlib CVE waiver remains) | go1.24.4 (unchanged) | 2 → 2 |

## 9 canonical answers

1. **Who** — Forge maintainer (me) eliminating the Debian-Go-toolchain-lag CVE class in one pass. Secondary: every consumer of these images (homelab, CI, downstream Forge consumers) gets their Go-stdlib CVE count dropped to zero for the 5 migrated exporters without any compose-file change.

2. **When** — fires at every daily cron build. New: forge-builder-go-trixie builds first (before scratch-base-trixie), then every from-Go image builds against it instead of against Debian-packaged binaries.

3. **What success looks like**:
   - `ghcr.io/bboortz/forge-builder-go-trixie:0.1` publishes alongside `forge-builder-trixie:0.1`; identical signing/SBOM/scan treatment.
   - `scripts/build-image.sh` auto-resolves `FORGE_BUILDER_GO_REF` to the local tag when `images/forge-builder-go-trixie/` exists, same pattern as FG-025's forge-builder-trixie handling.
   - Each migrated image's `--version` still reports the same upstream version string it did before (Debian version pinned at source clone; no behavior change observable from the metrics wire contract).
   - Every migrated image's grype scan shows **zero Go stdlib CVEs** (verified 2026-11-10 against the four Go stdlib CVEs in current circulation).
   - Every migrated image's acceptance test + smoke suite still passes.
   - Existing `GO-2026-6604` waivers added by `fix/go-stdlib-windows-cve-waiver` remain in PROMISES.yaml as a belt-and-suspenders guard (expires 2027-05-10); once-migrated images no longer match the CVE in grype but the waiver documentation stays for historical audit.

4. **Urgency** — quality-of-life + supply-chain. Beaconry noise from stdlib CVEs on bb-82jq every daily scan cycle. Not emergency (CVEs mostly unreachable code paths on linux/amd64) but accumulating cost.

5. **Happy path**:
   1. Daily cron builds forge-builder-go-trixie first.
   2. Each from-Go image's builder stage pulls forge-builder-go-trixie:latest and `git clone --depth 1 --branch <pinned>` the upstream source.
   3. `go build` with upstream-matching ldflags produces a static Go binary against go1.27.x stdlib.
   4. Runtime stage overlays the binary (and any C deps like freeipmi for ipmi-exporter).
   5. Operator sees no change in image behavior; Beaconry sees stdlib CVE count drop.

6. **Edge cases / failure modes**:
   - **Prometheus React UI build** — upstream prometheus 2.53 uses `go:embed` for a React SPA that must be built via `npm run build` before `go build`. Requires Node.js + npm + 5+ minutes of build. Deferred to a follow-up story to keep this PR's scope manageable.
   - **ipmi-exporter freeipmi hybrid build** — the Go exporter is simple to build from source, but it exec's C binaries (`ipmi-sensors`, `bmc-info`, etc.) that come from Debian's freeipmi-tools package. Both scratch and slim variants now use a **dual-builder** pattern: forge-builder-go-trixie for the Go exporter + forge-builder-trixie for the freeipmi apt-install.
   - **ipmi collector config override** — FG-043's `collector_cmd: ipmi-sensors` + `custom_args` fix is preserved in the migration (shipped in `ipmi-exporter.yml`, verified by `smoke_ipmi_collector_uses_elf.sh`).
   - **Version bump responsibility shifts to Forge** — we previously inherited Debian's chosen version; now we pin a specific upstream tag per image. Daily cron doesn't auto-bump upstream versions — operator does that by editing `ARG <IMG>_VERSION=` in each Dockerfile. Could flip to FG-013-style latest-resolve in a follow-up.

7. **Out of scope**:
   - **prometheus-scratch-trixie migration** — deferred (see Edge cases above).
   - **Latest-release auto-resolve** — all pinned by ARG. Operator-controlled bumps.
   - **Multi-arch** — amd64-only matches every other Forge image.
   - **Removing the GO-2026-6604 waivers** — stays as a documented "if a future grype DB flags this again, don't surprise the reviewer" guard. Can be cleaned up when the waiver expires 2027-05-10.
   - **arm64 builds for Prometheus-Community and Prometheus upstream** — same amd64-only policy.

8. **How we know it's done** — see Gherkin below.

9. **Capabilities delivered or extended**:
   - NEW `build.shared-go-builder` — `ghcr.io/bboortz/forge-builder-go-trixie:0.1` is a published builder-base image with go1.27+ toolchain + apt-upgrade + CA certs + syft + git/curl/jq. Sibling to `build.shared-builder` (FG-025).
   - EXT `build.from-go-source` (FG-044) — pattern now has a shared base; first-consumer cadvisor refactored to use it. Node-exporter, alertmanager, ipmi-exporter (scratch + slim) join as additional consumers.
   - EXT `image.node-exporter-serves-metrics` — now from Go source, same wire contract.
   - EXT `image.alertmanager-routes-alerts` — now from Go source, same wire contract (amtool preserved).
   - EXT `image.ipmi-exporter-serves-metrics` — now from Go source + Debian freeipmi overlay.
   - EXT `image.cadvisor-serves-metrics` — now from shared Go base (was golang:1.27-trixie direct).

## Gherkin acceptance

```
Scenario: forge-builder-go-trixie:0.1 is a working Go builder-base
  Given a successful build of forge-builder-go-trixie
  When any from-Go image's builder stage FROMs it
  Then `go version` reports >= 1.27
   And /usr/local/bin/syft is runnable
   And git + curl + jq are available for upstream-source cloning

Scenario: node-exporter-scratch-trixie is built from Go source with newer stdlib
  Given the rebuilt image
  When `strings /usr/bin/prometheus-node-exporter | grep ^go1` runs
  Then the output is `go1.27.3` (or later)
   And `--version` still prints `node_exporter, version 1.9.0`
   And /metrics still returns node_* series

Scenario: alertmanager-scratch-trixie is built from Go source with newer stdlib
  Given the rebuilt image
  When `strings /usr/bin/prometheus-alertmanager | grep ^go1` runs
  Then the output is `go1.27.3` (or later)
   And `--version` still prints `alertmanager, version 0.28.1`
   And /-/healthy still returns 200
   And /-/ready still returns 200
   And amtool is still present at /usr/bin/amtool

Scenario: ipmi-exporter-scratch-trixie is built from Go source with newer stdlib (dual-builder)
  Given the rebuilt image
  When `strings /usr/bin/prometheus-ipmi-exporter | grep ^go1` runs
  Then the output is `go1.27.3` (or later)
   And `--version` still prints `ipmi_exporter, version 1.10.0`
   And the 5 freeipmi ELF binaries are still shipped (bmc-info, ipmi-sensors, ipmi-chassis, ipmi-dcmi, ipmi-sel)
   And /etc/freeipmi/freeipmi_interpret_sensor.conf is still present
   And the `smoke_ipmi_collector_uses_elf.sh` regression guard still passes

Scenario: ipmi-exporter-slim-trixie is built from Go source (same freeipmi apt-install)
  Given the rebuilt image
  When `strings /usr/bin/prometheus-ipmi-exporter | grep ^go1` runs
  Then the output is `go1.27.3` (or later)
   And the freeipmi-tools binaries are still apt-installed (ipmimonitoring + ipmi-sensors + …)
   And /bin/sh is still present (slim contract)

Scenario: cadvisor-slim-trixie uses the shared Go base
  Given the rebuilt image
  When the Dockerfile is inspected
  Then it FROMs ghcr.io/bboortz/forge-builder-go-trixie (not golang:X-trixie directly)
   And `strings /usr/bin/cadvisor | grep ^go1` is still `go1.27.3`

Scenario: zero Go-stdlib CRITICALs in every migrated image
  Given a grype scan of each migrated image
  When the scan output is filtered to severity=Critical and artifact=stdlib
  Then the list is empty for: cadvisor-slim-trixie, node-exporter-scratch-trixie,
       alertmanager-scratch-trixie, ipmi-exporter-scratch-trixie,
       ipmi-exporter-slim-trixie

Scenario: prometheus-scratch-trixie migration deferred (documented)
  Given this story explicitly defers prometheus-scratch-trixie
  Then prometheus-scratch-trixie's Dockerfile is unchanged (still FROMs forge-builder-trixie + apt install prometheus)
   And prometheus-scratch-trixie's PROMISES.yaml still carries the GO-2026-6604 waiver (from fix/go-stdlib-windows-cve-waiver)
   And docs/plan/IDEAS.md contains an entry documenting what blocks the migration (React UI npm build pipeline)
```

## References

- Plan: `docs/plan/FG-046-forge-builder-go-trixie-plan.md`
- Red tests (split 2026-11-10 to fit the FG-038 per-cell timeout range [4..10] min — one cell per migration): `tests/acceptance/test_FG_046a_forge-builder-go-trixie.sh` + `test_FG_046b_cadvisor-go-source.sh` + `test_FG_046c_node-exporter-go-source.sh` + `test_FG_046d_alertmanager-go-source.sh` + `test_FG_046e_ipmi-exporter-scratch-go-source.sh` + `test_FG_046f_ipmi-exporter-slim-go-source.sh`
- Precedents: FG-025 (forge-builder-trixie — Debian + syft), FG-044 (cadvisor from-Go-source, first consumer)
- Beaconry finding: GO-2026-6604 on bb-82jq, 2026-11-10 (plus GO-2026-4337 + GO-2026-6612 surfaced by grype DB refresh)
- Upstream versions pinned:
  - node_exporter: v1.9.0 (github.com/prometheus/node_exporter)
  - alertmanager: v0.28.1 (github.com/prometheus/alertmanager)
  - ipmi_exporter: v1.10.0 (github.com/prometheus-community/ipmi_exporter)
  - cadvisor: v0.60.6 (github.com/google/cadvisor; unchanged from FG-044)
