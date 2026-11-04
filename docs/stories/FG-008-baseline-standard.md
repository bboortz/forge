---
id: FG-008
slug: baseline-standard
status: in-progress
owner: bboortz
created: 2026-11-04
---

# FG-008 — scratch-base-trixie:0.2: baseline evolves to a common standard

Bump `scratch-base-trixie` from 0.1 (intersection-only) to 0.2 (common-standard). Adds guarantees every Forge scratch image can rely on: the nonroot (65532) distroless identity + `/nonroot` home, network-resolution data (`/etc/services` + `/etc/protocols` + `/etc/hosts`), `/etc/localtime` → UTC, writable `/var/tmp`. Publishes `docs/baseline-contract.md` as the audit surface for current and future consumers.

Addresses parts of Beaconry's feedback on the python-scratch-trixie image (specifically claims #2 and parts of #3 — the nonroot identity). Claim #1 (HTTPS broken by default) and the python-scratch-specific hardening (USER, ENTRYPOINT, PYTHONDONTWRITEBYTECODE) land in FG-009 which depends on this story.

Versioned deliberately: 0.1 → 0.2 reflects an additive API change. Existing derivatives keep working without modification.

## 9 canonical answers

1. **Who** — Forge maintainer adding future scratch variants (redis, go, caddy, builder variants) who gets a single-digest contract to inherit; security engineer auditing "what every Forge scratch image guarantees"; Beaconry (consumer) who hit the missing nonroot uid + friends.
2. **When** — on PR / pre-push / daily cron matrix. Baseline publishes in `publish-base` matrix before derivatives (FG-005 ordering).
3. **What success looks like** —
   - `ghcr.io/bboortz/scratch-base-trixie:0.2` + `:latest` (+ `-amd64` variants) publishes; ≤ 25 MB
   - 8 smoke tests pass (4 from FG-005: contents_no_shell, contents_required_files, contents_zero_os_cves, size; 4 new: contents_users, contents_network_data, contents_time, contents_writable_dirs)
   - `docs/baseline-contract.md` documents every guarantee
   - Existing derivatives (python/nginx/postgres scratch) continue to pass their own smoke suites unchanged — the baseline evolution is additive
4. **Urgency** — product tier. Beaconry needs it; future scratch images will rely on it.
5. **Happy path** —
   1. `image.yaml` tag `0.1 → 0.2`.
   2. Dockerfile adds nonroot user to `/etc/passwd` + `/etc/group`, creates `/nonroot` (0755, 65532:65532).
   3. Dockerfile copies `/etc/services`, `/etc/protocols` from builder base; writes minimal `/etc/hosts`; symlinks `/etc/localtime` → `/usr/share/zoneinfo/Etc/UTC`.
   4. Dockerfile creates `/var/tmp` (1777).
   5. 4 new content-style smoke tests (`docker save` + tar inspection).
   6. `scripts/build-image.sh` reads baseline tag dynamically from `image.yaml` so future bumps don't need script edits.
   7. `docs/baseline-contract.md` publishes the contract.
   8. Red test asserts baseline is 0.2 + content checks + contract doc exists + derivatives still pass.
6. **Edge cases / failure modes** —
   - `cp /etc/services` fails if netbase isn't installed in the builder base. `python:3.13-slim-trixie` ships netbase; verified.
   - `/etc/localtime` symlink target resolution: baseline ships `/usr/share/zoneinfo/Etc/UTC` + `/usr/share/zoneinfo/UTC` (symlink). The symlink chain is intact after `cp -r`.
   - `nonroot` uid collision with a derivative's service user — avoided because 65532 is reserved in the contract.
   - Derivatives built against `:0.1` would fail if baseline is deleted; CI publishes BOTH `:0.1` and `:0.2` on every daily cron thanks to the 4-tag family + the version bump (`:latest` moves to `:0.2`).
7. **Out of scope** — python-scratch-trixie USER/ENTRYPOINT changes (FG-009); re-declaring SSL_CERT_FILE in derivatives (FG-009); multi-arch (future); machine-readable baseline-contract JSON schema (deferred).
8. **How we know it's done** — see Gherkin + FG-008 acceptance test.
9. **Capabilities** —
   - EXT `build.scratch-baseline` — now includes nonroot identity + network data + time + /var/tmp
   - EXT `test.scratch-contents` — 4 new content-style smokes added
   - NEW `docs.baseline-contract` — `docs/baseline-contract.md` is the canonical audit surface

## Gherkin acceptance

```
Scenario: baseline tag bumps to 0.2
  Given the repo at HEAD
  Then images/scratch-base-trixie/image.yaml has `tag: "0.2"`
   And forge-local/scratch-base-trixie:0.2 builds

Scenario: baseline provides the nonroot identity
  Given a fresh baseline build
  When /etc/passwd + /etc/group are inspected
  Then they contain lines matching root (0), nonroot (65532) with home /nonroot, nobody (65534)

Scenario: baseline provides network-resolution data
  Given a fresh baseline build
  Then /etc/services (with 'http 80/tcp'), /etc/protocols (with 'tcp 6'), /etc/hosts (with 127.0.0.1 localhost) are present

Scenario: baseline provides /etc/localtime → UTC
  Given a fresh baseline build
  Then /etc/localtime is a symlink pointing at /usr/share/zoneinfo/Etc/UTC

Scenario: baseline provides /tmp, /var/tmp, /nonroot
  Given a fresh baseline build
  Then /tmp and /var/tmp are mode 1777
   And /nonroot is owned 65532:65532 with mode 0755

Scenario: docs/baseline-contract.md exists and documents the API
  Given the repo at HEAD
  Then docs/baseline-contract.md exists
   And references scratch-base-trixie and reserved UIDs 0, 33, 999, 65532, 65534

Scenario: existing scratch derivatives continue to pass against 0.2
  Given python-scratch-trixie + nginx-scratch-trixie + postgres-scratch-trixie rebuilt
  Then every existing smoke test still passes
```

## References

- Plan: [`docs/plan/FG-008-baseline-standard-plan.md`](../plan/FG-008-baseline-standard-plan.md)
- Red test: [`tests/acceptance/test_FG_008_baseline-standard.sh`](../../tests/acceptance/test_FG_008_baseline-standard.sh)
- Contract: [`docs/baseline-contract.md`](../baseline-contract.md)
- Capabilities: [`docs/CAPABILITIES.md`](../CAPABILITIES.md)
