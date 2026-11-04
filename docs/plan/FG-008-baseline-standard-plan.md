# FG-008 — Plan: scratch-base-trixie:0.2 baseline-as-standard

**Story**: [`docs/stories/FG-008-baseline-standard.md`](../stories/FG-008-baseline-standard.md)
**Status**: in-progress
**Branch**: `feat/FG-008-baseline-standard`

## Design delta

Baseline evolves from "strict intersection of python+nginx+postgres closures" (0.1) to **a published common standard** (0.2) that any future Forge scratch image can rely on. Additive — no breaking changes. Additions were prioritized from real consumer feedback (Beaconry) plus the file-layout guarantees that distroless and Chainguard have independently converged on.

New guarantees in 0.2:

| File / entity | Reason |
|---|---|
| `/etc/passwd` nonroot line (uid 65532, home `/nonroot`) | Libraries that `pwd.getpwuid(geteuid())` crash on unknown UIDs; distroless convention |
| `/etc/group` nonroot line (gid 65532) | Same |
| `/nonroot` directory (0755, 65532:65532) | HOME for the nonroot user |
| `/etc/services` | `socket.getservbyname('http')` returns 80 instead of raising |
| `/etc/protocols` | `socket.getprotobyname('tcp')` works |
| `/etc/hosts` | Minimal `127.0.0.1 localhost` + `::1 localhost ip6-localhost ip6-loopback`; makes `getaddrinfo('localhost')` resolve without docker-injected overrides |
| `/etc/localtime` → `/usr/share/zoneinfo/Etc/UTC` | Many apps read /etc/localtime first; symlink gives deterministic UTC behavior |
| `/var/tmp` (1777) | Apps that distinguish `/tmp` (volatile) from `/var/tmp` (persists across reboots in traditional unix) |

New in the repo surface:

- **`docs/baseline-contract.md`** — authoritative audit surface. File-layout API, reserved UIDs, composition contract, ENV re-declaration requirement (the FG-009 Beaconry fix depends on this being documented), non-guarantees, versioning policy.
- **`scripts/build-image.sh`** — reads baseline tag from `images/scratch-base-trixie/image.yaml` so derivatives build against whatever version is current without script edits.

Baseline size: 13.15 MB (+16 KB vs 0.1, mostly /etc/services at 13 KB).

## Alternatives rejected

- **Bake `/etc/machine-id`** — security bug (must be unique per container). Container runtime handles this.
- **Ship `/etc/resolv.conf`** — docker injects per-container; shipping a file in the image preempts that and breaks custom DNS configs.
- **Include `libnss-db` or NSS modules beyond dns/files** — our baseline uses `files dns` policy; LDAP / sssd / systemd NSS modules are workload-specific.
- **Add `/dev/null`, `/dev/urandom`** — docker runtime creates `/dev/*` at container start.
- **Machine-readable JSON schema for the contract** — overkill until tooling consumes it. Markdown is enough for humans; derivatives are tested against actual files, not a schema.
- **Reserve UID 1000 (first regular user)** — collides with developer workstation UIDs; distroless learned to avoid it.

## Breaking changes

None. Additive. Existing consumers of `:0.1` get the same bits they always did; new ones using `:0.2` or `:latest` get the additions.

Baseline `:latest` moves to point at `:0.2` on the first publish of this PR. Consumers pinned to `@sha256:...` are unaffected.

## Merge plan

Fast tier (`make check-strict`): lint, verify-sid-pins, verify-traceability, test-acceptance (incl. new FG-008 + existing FG-001–007), test-images (now 33 smoke scripts: baseline +4, rest unchanged).

## Rollout plan

Standard: merge to `dev`, operator triggers `release.yml` → `main`, then `build.yml` publishes. Baseline publishes in the `publish-base` matrix before derivatives; derivatives automatically pick up the new `:latest` on next rebuild.

## Shipping evidence

| Item | Pointer | Status |
|------|---------|--------|
| Scenario: tag bumps 0.1 → 0.2 | `images/scratch-base-trixie/image.yaml` + FG-008 acceptance (s1) | ✅ |
| Scenario: nonroot identity | `images/scratch-base-trixie/tests/smoke_contents_users.sh` | ✅ |
| Scenario: network-resolution data | `images/scratch-base-trixie/tests/smoke_contents_network_data.sh` | ✅ |
| Scenario: /etc/localtime symlink | `images/scratch-base-trixie/tests/smoke_contents_time.sh` | ✅ |
| Scenario: /tmp + /var/tmp + /nonroot | `images/scratch-base-trixie/tests/smoke_contents_writable_dirs.sh` | ✅ |
| Scenario: contract doc exists | FG-008 acceptance (s6) | ✅ |
| Scenario: existing derivatives still pass | all images/*/tests/smoke_*.sh under make check-strict | ✅ |
| EXT `build.scratch-baseline` | docs/CAPABILITIES.md | ✅ |
| EXT `test.scratch-contents` | 4 new content smokes | ✅ |
| NEW `docs.baseline-contract` | `docs/baseline-contract.md` | ✅ |
| dynamic baseline tag in build-image.sh | `scripts/build-image.sh` reads image_yaml_get | ✅ |
| Scenario: baseline publishes to GHCR (post-publish) | matrix publish-base | ⚠️ post-publish |
| Scenario: cosign verify against 0.2 (post-publish) | matrix sanity step | ⚠️ post-publish |

Local measurements:
- baseline size: **13.15 MB** (+16 KB vs 0.1, 53 % of 25 MB ceiling)
- grype: 0 Debian-source matches
- 33 smoke scripts across 5 images, 0 failures under `make check-strict`
