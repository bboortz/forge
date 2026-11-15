---
id: FG-058
slug: libxml2-waiver-and-debian-sid-base
story: ../stories/FG-058-libxml2-waiver-and-debian-sid-base.md
---

# FG-058 plan — libxml2 CVE-2026-6653 waiver + `debian-slim-sid` pre-builder

Story: [FG-058](../stories/FG-058-libxml2-waiver-and-debian-sid-base.md). Implementation blueprint.

## Design delta

### Deliverable 1 — `postgres-slim-trixie` PROMISES.yaml gains a `scan.waivers` doc block

New promise at the bottom:

```yaml
  - id: scan.nonzero-accepted
    description: |
      scan-baseline.json accepts a nonzero CRITICAL CVE list — slim images
      inherit the Debian dpkg closure of postgres:18. The PR scan-regression
      gate (FG-019) fails only on NEW CRITICALs beyond the baseline. The
      waivers below document the accepted CVEs' reachability analysis
      for operator audit.
    caps: [scan.regression-gate]
    tests:
      - images/postgres-slim-trixie/tests/smoke_size.sh   # smoke exists; baseline is the real gate
    waivers:
      - cve: CVE-2026-6653
        reason: |
          libxml2 UAF in SAX2 external-subset parsing. Debian trixie
          marks this <no-dsa> (Minor issue; UAF reachable only via
          CVE-2021-3541 backport, upstream fix requires libxml2 2.11.0+
          which Debian deliberately keeps separate as libxml2-16/.so.16).
          postgres:18 is dynamically linked to libxml2.so.2 — the legacy
          2.9.14 ABI bucket that Debian maintains without this fix.
          Reachability: UAF triggers only when postgres parses attacker-
          controlled XML via the `xml` data type or `xml2` contrib
          extension. Homelab postgres has zero such usage (verified via
          grep across docker/* + ansible/*). Attack surface is empty for
          the current Forge consumer set. Remove this waiver if:
          (a) Debian backports a .so.2 fix (unlikely per <no-dsa>), OR
          (b) a Forge consumer begins parsing untrusted XML (then
          upgrade to from-source libxml2 rebuild).
        until: "2027-05-15"
```

(The scan-regression gate's current consumer — `scripts/scan-regression.py` — only reads waivers from the `absence.os-cves` promise. The waiver block here is documentation-grade; the real gate is `scan-baseline.json`, which already lists `CVE-2026-6653`.)

### Deliverable 2 — New `debian-slim-sid` pre-builder

#### Layout

```
images/debian-slim-sid/
├── Dockerfile          — FROM debian:sid-slim + apt-upgrade + ca-certificates
├── image.yaml          — tag: "latest" (floating; rolling-release)
├── PROMISES.yaml       — mirror debian-slim-trixie's shape + sid-specific caveats
├── scan-baseline.json  — first-build-generated; expected to drift with sid
├── sid-pins/           — empty dir (consumer-level sid pins, if any)
└── tests/
    ├── smoke_apt_upgraded.sh    — apt lists cleared post-upgrade
    ├── smoke_ca_bundle.sh       — /etc/ssl/certs/ca-certificates.crt present
    ├── smoke_has_shell.sh       — /bin/sh present
    ├── smoke_is_sid.sh          — VERSION_CODENAME=sid in /etc/os-release
    ├── smoke_no_apt_cache.sh    — /var/lib/apt/lists/ empty
    └── smoke_size.sh            — size ≤ base × 1.1
```

#### image.yaml

```yaml
# FG-058: forge-rooted Debian sid slim base. Companion to
# debian-slim-trixie — same shape, rolling-release lineage. Expected
# consumer today: zero (escape hatch for a future CVE that needs
# sid-pinning when trixie's package is stuck unfixed).
# Policy: see memory/design-decisions.md § "Exception — Debian sid".
tag: "latest"
platforms:
  - linux/amd64
```

#### Dockerfile (mirrors debian-slim-trixie almost verbatim)

```dockerfile
# syntax=docker/dockerfile:1.7
#
# FG-058: forge-rooted Debian sid slim base. Companion to FG-042's
# debian-slim-trixie — same shape, rolling-release lineage.
#
# Rationale: trixie occasionally ships CVE-exposed legacy-ABI packages
# that Debian explicitly won't fix (e.g. libxml2.so.2's 2.9.14 bucket;
# see FG-058 story). For CVEs that sid DOES fix at the .so.2 SONAME
# (e.g. curl, openssl rolling point releases), having a Forge-rooted
# sid pre-builder available makes the escape-hatch story a 30-min FG
# instead of an in-Dockerfile apt-source gymnastics.
#
# Consumer policy: default is still trixie (memory/design-decisions.md).
# Reach for this only when a specific trixie package is stuck unfixed
# AND sid's version is compatible with the downstream consumer's ABI
# requirements.
#
# Literal FROM (not ARG-indirected) so FG-042's upstream-grep invariant
# can cheaply catch future drift.

FROM debian:sid-slim

ARG GIT_SHA=unknown
ARG BUILD_TIMESTAMP=unknown

LABEL org.opencontainers.image.source="https://github.com/bboortz/forge"
LABEL org.opencontainers.image.licenses="Apache-2.0"
LABEL org.opencontainers.image.description="Forge-rooted Debian sid (unstable) slim base — apt-upgraded + CA certs, escape-hatch for CVEs that trixie leaves unfixed"
LABEL org.opencontainers.image.revision="${GIT_SHA}"
LABEL org.opencontainers.image.created="${BUILD_TIMESTAMP}"

COPY sid-pins/ /etc/apt/preferences.d/

# hadolint ignore=DL3005,DL3008
RUN set -eux; \
    apt-get update; \
    apt-get -y --no-install-recommends upgrade; \
    apt-get -y --no-install-recommends install ca-certificates; \
    rm -rf /var/lib/apt/lists/*

WORKDIR /
```

### scripts + CI wiring

- `scripts/discover-images.sh` — `_PRE_BUILDERS` array gains `debian-slim-sid`.
- `scripts/verify-no-upstream-drift.sh` — `_UPSTREAM_ANCHORS` adds `'debian:sid-slim'`, `_EXPECTED` bumps 3 → 4.
- `memory/design-decisions.md` — new `## Exception — Debian sid (FG-058)` section documenting the policy.
- `docs/CAPABILITIES.md` — NEW `build.debian-sid-base` + EXT `build.pre-builder-tier` + EXT `image.forge-rooted-slim-bases`.
- `docs/stories/INDEX.md` — FG-058 row.

### Red acceptance test

`tests/acceptance/test_FG_058_libxml2-waiver-and-debian-sid-base.sh` with 8 sections:

1. `postgres-slim-trixie/PROMISES.yaml` carries a waiver block with cve=CVE-2026-6653 + three-point reason + future `until` date.
2. `images/debian-slim-sid/` exists with required files.
3. `debian-slim-sid/image.yaml` tag = "latest".
4. Full build: `scripts/build-image.sh debian-slim-sid` succeeds.
5. All 6 smokes pass (incl. the new `smoke_is_sid.sh`).
6. `scripts/verify-no-upstream-drift.sh` returns 4 pre-builders.
7. `scripts/discover-images.sh pre-builders` includes `debian-slim-sid`.
8. `make verify-traceability` passes with the new CAP wired.

## Merge order

1. Branch from `dev`.
2. All edits in one commit.
3. Build + smoke locally.
4. PR to `dev`, CI full-check, auto-merge on green.

## Shipping evidence (filled before commit)

| Lens | Item | Status |
|------|------|--------|
| Gherkin coverage | Scenario 1 (waiver block in PROMISES) | ⏳ |
| Gherkin coverage | Scenario 2 (scan-regression gate passes) | ⏳ (already passes via baseline; test added for visibility) |
| Gherkin coverage | Scenario 3 (debian-slim-sid publishes) | ⏳ |
| Gherkin coverage | Scenario 4 (verify-no-upstream-drift _EXPECTED=4) | ⏳ |
| Gherkin coverage | Scenario 5 (pre-builders matrix includes debian-slim-sid) | ⏳ |
| Self-consistency | Chain depth unchanged (debian-slim-sid is a sibling leaf pre-builder) | ✅ |
| Self-consistency | `memory/design-decisions.md` policy documented | ⏳ |
| Build symmetry | All 4 pre-builders publish via existing 4-tier pipeline | ✅ unchanged |
