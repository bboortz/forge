---
id: FG-012
slug: external-sourced-images
status: in-progress
owner: bboortz
created: 2026-11-05
---

# FG-012 — Externally-sourced images (`source:` in image.yaml) + beaconry-scout

Extend Forge's image factory to publish images whose `Dockerfile` + sources live **upstream**, not in this repo. `image.yaml` gains an optional `source:` block (`git` / `ref` / optional `dockerfile` / `context`); `scripts/build-image.sh` resolves `ref` to a concrete commit sha, clones at that sha, builds, scan + sign + publish as usual. The resolved sha is baked into `org.opencontainers.image.revision` so attestation is honest even for floating refs.

First consumer: **beaconry-scout**. Beaconry's `poc/scout/Dockerfile` already `FROM`s our FG-009 hardened `python-scratch-trixie:3.13` — it's a model downstream consumer and simpler than hub (no docker CLI, no grype DB download, standalone-bootable). Shipping scout proves the mechanism end-to-end. Hub is a straight-line follow-up (FG-013).

Design constraint from the user: beaconry devs must not wait for a Forge rebuild during normal iteration. The `source:` design preserves that — devs build locally via beaconry's own `docker compose up` against the already-published hardened scratch base; Forge publishes signed, scanned builds on its own cadence (daily cron + manual `workflow_dispatch`).

## 9 canonical answers

1. **Who** — Forge maintainers (adding external images); Beaconry devs (continue to `docker compose up` locally, zero friction); auditors (every published external-source digest ties to a specific upstream commit sha via the OCI `revision` label).
2. **When** — on every PR / pre-push / daily cron. Daily cron re-resolves any floating `ref` (`latest` / branch name) to that day's upstream HEAD and rebuilds.
3. **What success looks like** —
   - `images/<name>/image.yaml` supports `source:` (`git` + `ref` + optional `dockerfile` + `context`).
   - `source:` present ⇒ **no local `Dockerfile`** at `images/<name>/Dockerfile` (lint rejects it).
   - `ref:` accepts commit sha, git tag, `latest` (Forge keyword → upstream default branch HEAD), or any branch name. Resolved at build time to a concrete sha.
   - `scripts/build-image.sh <name>` clones at the resolved sha, builds, scan + sign + publish.
   - Resolved sha ends up in `org.opencontainers.image.revision` on the published image.
   - `images/beaconry-scout/image.yaml` points at `bb-claw/beaconry@665370e7…` and successfully publishes `ghcr.io/bboortz/beaconry-scout:0.1`.
   - Forge-side smokes (readyz response, syft binary present, no-shell, zero OS CVEs, size) all pass against the local build.
4. **Urgency** — product tier. Blocks Beaconry's "ship signed images via Forge" story.
5. **Happy path** —
   1. `scripts/_image_yaml.sh`: add `image_yaml_source_*` helpers.
   2. `scripts/build-image.sh`: branch on `source:` present; `git fetch --depth=1` the ref; `git checkout FETCH_HEAD`; resolve to concrete sha; `docker build` against the clone; pass the resolved sha as a build-arg so the Dockerfile can set `org.opencontainers.image.revision`.
   3. `scripts/verify-image-dirs.sh` (new): reject an image dir carrying both `source:` and a local `Dockerfile`, or `source:` with an empty/missing `ref`. Wire into `make test-fast`.
   4. `images/beaconry-scout/`:
      - `image.yaml` with `source.git: https://github.com/bboortz/beaconry`, `source.ref: 665370e…`, `source.dockerfile: poc/scout/Dockerfile`, `source.context: poc/`.
      - `PROMISES.yaml` — Forge-authored; promises cover readyz, bundled syft, nonroot inherited from base, no-shell, zero OS CVEs, size budget.
      - `EXPECTATIONS.yaml` — depends on `python-scratch-trixie@>=3.13` (reuses FG-010 contract; every FG-009 guarantee is transitively asserted).
      - `tests/smoke_readyz.sh` — `docker run -d`, wait for `/readyz`, assert 200, stop + clean.
      - `tests/smoke_syft_bundled.sh` — `docker run --entrypoint=/usr/local/bin/syft <image> --version` returns 0.
      - `tests/smoke_no_shell.sh` — standard (inherited pattern).
      - `tests/smoke_zero_os_cves.sh` — standard.
      - `tests/smoke_size.sh` — ≤ 150 MB hard ceiling (python-scratch 45 MB + scout overlay ~50 MB + headroom).
   5. CAPs: `build.external-source`, `publish.external-image`, `image.beaconry-scout`, `image.beaconry-scout-bundled-syft`.
   6. FG-012 acceptance test: encodes the Gherkin.
6. **Edge cases / failure modes** —
   - Upstream rejects fetch-by-sha from non-tip commits. Fallback: full `git clone` + `git checkout <ref>`.
   - Upstream Dockerfile moves (e.g., `poc/scout/Dockerfile` → `services/scout/Dockerfile`). Pin update required; verifier won't catch stale dockerfile path until build. Error surfaces as "dockerfile not found at <path>" — fine; auditable.
   - `ref: latest` mutable. Honest attestation: we bake the **resolved** sha into the image. Daily cron may produce different digests from day to day — audit still works because `org.opencontainers.image.revision` is always a sha.
   - Clone size: beaconry repo is ~50 MB; `--depth=1` keeps it minimal. Not a concern.
7. **Out of scope** —
   - beaconry-hub (follow-up FG-013 — needs docker CLI, grype DB, and more smoke machinery; one at a time).
   - telegram_mock (test-only; not a published artifact).
   - Running beaconry's own integration tests inside Forge — those stay in beaconry CI.
   - Automated "bump pin when beaconry main moves" GHA workflow — meta-automation, add later if the churn is painful.
8. **How we know it's done** — Gherkin + FG-012 acceptance test + `make check-strict` green with `beaconry-scout` included.
9. **Capabilities** —
   - NEW `build.external-source` — `image.yaml` supports `source:`; build-image.sh clones upstream at a pinned ref
   - NEW `publish.external-image` — Forge's scan/sign/publish pipeline applies to externally-sourced images
   - NEW `image.beaconry-scout` — scout image published by Forge with full supply-chain triple
   - NEW `image.beaconry-scout-bundled-syft` — scout image ships `/usr/local/bin/syft` ready to run

## Gherkin acceptance

```
Scenario: source + local Dockerfile are mutually exclusive
  Given an image dir has both source: in image.yaml AND a Dockerfile
  When make test-fast runs
  Then verify-image-dirs fails naming the dir

Scenario: source without ref is rejected
  Given source: present with empty ref: field
  When verify-image-dirs runs
  Then it fails with a precise diagnostic

Scenario: external build works at a pinned sha
  Given images/beaconry-scout/image.yaml has source.git + source.ref = 665370e7...
  When scripts/build-image.sh beaconry-scout runs
  Then forge-local/beaconry-scout:0.1 exists
   And docker inspect reports org.opencontainers.image.revision = 665370e7...

Scenario: scout serves /readyz
  Given forge-local/beaconry-scout:0.1
  When the container is run
  Then GET /readyz returns 200 within 60 seconds

Scenario: scout ships a working syft
  Given forge-local/beaconry-scout:0.1
  When docker run --entrypoint=/usr/local/bin/syft <image> --version
  Then it exits 0

Scenario: verify-contracts stays green with the new image
  Given beaconry-scout PROMISES + EXPECTATIONS
  When make verify-contracts runs
  Then it exits 0
```

## References

- Plan: [`docs/plan/FG-012-external-sourced-images-plan.md`](../plan/FG-012-external-sourced-images-plan.md)
- Red test: [`tests/acceptance/test_FG_012_external-sourced-images.sh`](../../tests/acceptance/test_FG_012_external-sourced-images.sh)
- Beaconry upstream: [`bboortz/beaconry@665370e7…`](https://github.com/bboortz/beaconry/commit/665370e7d793968b5b8fc550fbd0582993a829fc)
- Capabilities: [`docs/CAPABILITIES.md`](../CAPABILITIES.md)
