---
id: FG-058
slug: libxml2-waiver-and-debian-sid-base
status: ready
owner: bboortz
created: 2026-11-15
---

# FG-058 — libxml2 CVE-2026-6653 waiver + new `debian-slim-sid` pre-builder

Beaconry flagged **CVE-2026-6653** (libxml2 UAF, CVSS 9.8) against `ghcr.io/bboortz/postgres-slim-trixie`. First instinct was "sid-pin libxml2" — the same shape as other recent FG fixes. Investigation showed that's **not viable**:

| Fact | Consequence |
|------|------|
| Debian trixie marks the CVE `<no-dsa>` (Minor issue) | No backport coming |
| Debian split libxml2 into two parallel source packages: `libxml2.9` (ships binary `libxml2`, SONAME `.so.2`, legacy 2.9.14 ABI) and `libxml2` (ships binary `libxml2-16`, SONAME `.so.16`, v2.15.4) | Sid's "fixed libxml2" is `libxml2-16`, a different SONAME |
| postgres:18 binary is dynamically linked to `libxml2.so.2` | Loads the vulnerable library regardless of trixie vs sid base |
| Upstream fix (commit 463bbeec) touches 4+ files, adds a field to `xmlEntity` struct | Backport is non-trivial — not a cherry-pick candidate |
| Homelab postgres has zero XML usage (grep over `docker/` + `ansible/`) | Attack surface is empty unless consumer SELECTs xml functions on attacker-controlled input |

Given all of the above, this FG delivers **two deliverables**:

## Deliverable 1 — Explicit waiver for CVE-2026-6653

Add a waiver entry in `images/postgres-slim-trixie/PROMISES.yaml`'s existing `scan.nonzero-accepted` promise (or in a new `absence.os-cves.waivers` block if the image doesn't have one). Waiver reason cites:

1. Debian `<no-dsa>` ruling (upstream Debian maintainer explicitly declined to fix).
2. Reachability analysis: postgres's libxml2 use is the `xml` data type + `xml2` extension. UAF is reachable only when postgres parses attacker-controlled XML. Homelab postgres has no XML-consuming queries.
3. `until: 2027-05-15` — six-month review window. If Debian ever ships a `.so.2` fix (unlikely per their notes), remove the waiver. If a Forge consumer starts parsing untrusted XML, upgrade to a proper fix (rebuild libxml2 from source).

## Deliverable 2 — New `debian-slim-sid` pre-builder (infrastructure for the next CVE)

Separate image at `images/debian-slim-sid/`. `FROM debian:sid-slim` + `apt-get upgrade` + CA bundle. 2-tag family (`:latest` + `:latest-amd64`), slim contract (shell preserved).

Rationale: FG-058 proves we can't always fix CVEs via sid-pinning when Debian maintains vulnerable legacy packages. But there WILL be future CVEs where sid DOES ship a `.so.2`-compatible fix — e.g. curl, openssl, zlib, where Debian doesn't maintain a legacy ABI bucket. For those cases, having `debian-slim-sid` as a pre-builder on-hand lets a future FG land in ~30 min instead of ~2 hours of apt-source gymnastics in a derivative Dockerfile.

**Policy for `debian-slim-sid` consumption**: documented in `memory/design-decisions.md`. Default is still trixie; sid is an **escape hatch** for specific CVEs or features that trixie can't satisfy and where the operator accepts rolling-release churn. Expected consumers today: **zero**. Future consumers: case-by-case per the same policy as the Ubuntu precedent (FG-051).

## 9 canonical answers

1. **Who** — Forge maintainer wanting a stable position on CVE-2026-6653 (today); future-me needing an escape hatch for a different sid-fixable CVE (later).

2. **When** — Deliverable 1 fires on every subsequent grype scan of postgres-slim-trixie — the scan-regression gate reads the waiver + ignores the CVE until the review date. Deliverable 2 fires every daily cron (publishes the new pre-builder; nobody FROMs it yet, so it's zero-traffic).

3. **What success looks like**:
   - `images/postgres-slim-trixie/PROMISES.yaml` carries a `scan.waivers[].cve == CVE-2026-6653` entry with the three-point reason (Debian status + reachability + review date).
   - `make scan` against `forge-local/postgres-slim-trixie:18` still finds CVE-2026-6653 (fact of the library) but `make scan-regression` (FG-019 gate) passes because the waiver absorbs it.
   - `ghcr.io/bboortz/debian-slim-sid:latest` publishes cleanly with cosign + SBOM + grype triple.
   - `debian-slim-sid` smoke suite proves the base is Debian sid, apt is clean, CA bundle present.
   - `memory/design-decisions.md` gains a `## Exception — Debian sid` section.
   - `scripts/verify-no-upstream-drift.sh` adds `debian:sid-slim` to `_UPSTREAM_ANCHORS` + `_EXPECTED=4`.
   - `scripts/discover-images.sh` `_PRE_BUILDERS` array includes `debian-slim-sid`.
   - Red acceptance test verifies both deliverables.

4. **Urgency** — quality-of-life / correctness. Not an acute threat (zero reachability in homelab). Beaconry alert on hetzner-staging stays open until Forge waiver flows into their view (depends on Beaconry's scanner config) — operator snooze on Beaconry's side is the short-term action.

5. **Happy path**:
   1. Branch `feat/FG-058-libxml2-waiver-plus-debian-sid` from `dev`.
   2. Write waiver entry in postgres-slim-trixie's PROMISES.yaml.
   3. Create `images/debian-slim-sid/{Dockerfile, image.yaml, PROMISES.yaml, scan-baseline.json, tests/smoke_*.sh}` — 4 smoke tests mirroring debian-slim-trixie's shape.
   4. Update `scripts/verify-no-upstream-drift.sh` `_UPSTREAM_ANCHORS` + `_EXPECTED`.
   5. Update `scripts/discover-images.sh` `_PRE_BUILDERS` array.
   6. Update `memory/design-decisions.md` with `## Exception — Debian sid` policy.
   7. Update `docs/CAPABILITIES.md` (new CAP `build.debian-sid-base` + extend `build.pre-builder-tier`).
   8. Red acceptance test `test_FG_058_libxml2-waiver-and-debian-sid-base.sh` with 8 sections (waiver shape + debian-slim-sid dir layout + build + 4 smokes + verify-no-upstream-drift + traceability).
   9. `make check-smart-strict` green locally.
   10. PR to `dev` → CI full-check → auto-merge on green.

6. **Edge cases / failure modes**:
   - **Debian sid is unstable** — breakage isn't a surprise; that's what pinning + daily cron with `--pull` catches. First-consumer story at promotion time documents the "known-to-work today, tomorrow may be different" caveat.
   - **sid's libxml2 is ALSO vulnerable** (confirmed during investigation) — this FG explicitly isn't attempting to use debian-slim-sid as a fix for CVE-2026-6653. Documented in both the story and the plan.
   - **Scan-baseline for debian-slim-sid is unpredictable** — generate on first local build; accept whatever sid currently has. Plan assumes the baseline updates every daily cron (same model as other images).
   - **Chain depth** — `debian-slim-sid` is a sibling pre-builder to trixie-based ones. Doesn't deepen anyone's chain unless a specific image FROMs it (none in this FG).
   - **Waiver review date passes with CVE still open** — PR-time scan-regression gate fails (FG-041 cosign-pin-drift-gate shape). Operator can either extend the review date (if reachability hasn't changed) or decide to actually fix the CVE at that point.

7. **Out of scope**:
   - **Rebuilding libxml2 2.9.14 with the backport** — too much maintenance surface for one `<no-dsa>` CVE with zero reachability.
   - **Switching postgres-slim-trixie to a sid base** — doesn't help (sid's `.so.2` is also vulnerable per the libxml2.9 package relationship).
   - **Moving any existing image to `debian-slim-sid`** — no consumer today; stays zero-traffic.
   - **Writing a reusable `debian-base-<suite>` abstraction** — premature; two concrete suites (trixie + sid) is fine.

8. **How we know it's done** — see Gherkin below.

9. **Capabilities delivered or extended**:
   - NEW `build.debian-sid-base` — Forge-rooted Debian sid slim base. First time we ship a rolling-release Debian variant.
   - EXT `build.pre-builder-tier` — adds `debian-slim-sid` to the 3 existing pre-builders (publish-pre-builders matrix is now 4-wide).
   - EXT `image.forge-rooted-slim-bases` — Debian sid family added.
   - EXT `scan.cve-waivers` — explicitly used for a `<no-dsa>` CVE whose reachability is empty in the Forge consumer set.

## Gherkin acceptance

```
Scenario: postgres-slim-trixie carries a CVE-2026-6653 waiver
  Given images/postgres-slim-trixie/PROMISES.yaml
  When the file is read
  Then a scan.waivers[] entry exists with cve=CVE-2026-6653
  And its reason references Debian's <no-dsa> ruling
  And its reason references zero XML reachability in homelab postgres
  And its until field is 2027-05-15 or later

Scenario: scan-regression gate passes with the waiver present
  Given forge-local/postgres-slim-trixie:18 built from source
  And a fresh grype scan that still reports CVE-2026-6653
  When scripts/verify-scan-regression.sh runs
  Then it exits 0 (waiver absorbs the known CVE)

Scenario: debian-slim-sid publishes with the standard pipeline
  Given images/debian-slim-sid/ exists
  When the daily cron runs the publish-pre-builders tier
  Then ghcr.io/bboortz/debian-slim-sid:latest and :latest-amd64 are tagged + cosign-signed
  And the attached SBOM lists Debian sid packages (not trixie)
  And /etc/os-release inside the image reports VERSION_CODENAME=sid (or trixie/unstable per Debian's conventions)

Scenario: verify-no-upstream-drift accepts the new anchor
  Given scripts/verify-no-upstream-drift.sh
  When it runs
  Then _EXPECTED == 4 and the grep finds exactly 4 Dockerfiles FROMing an upstream anchor
  And debian:sid-slim appears in _UPSTREAM_ANCHORS

Scenario: debian-slim-sid is in the pre-builders tier
  Given scripts/discover-images.sh pre-builders --filter all
  When the script runs
  Then the matrix includes an entry for debian-slim-sid
```
