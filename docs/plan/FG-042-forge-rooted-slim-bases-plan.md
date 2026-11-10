# FG-042 — Plan: forge-rooted slim bases + build.yml pre-builders tier

**Story**: [`docs/stories/FG-042-forge-rooted-slim-bases.md`](../stories/FG-042-forge-rooted-slim-bases.md)
**Status**: draft
**Branch**: `feat/FG-042-forge-rooted-slim-bases`

## Design delta

### `images/debian-slim-trixie/` (new)

Pre-builder tier image. Sibling of `python-slim-trixie` (also pre-builder post-FG-042).

- `image.yaml`: tag `"0.1"`, platforms `[linux/amd64]`, no `depends_on`.
- `Dockerfile`: `FROM debian:trixie-slim` → apt-upgrade + ca-certificates. Minimal — just apt-upgrade + CA, no builder tooling. (For scanning, syft is pulled in-line by the `make scan` step in CI; no need to bake it into the image.)
- `PROMISES.yaml`: 6 promises — `files.ca-certificates`, `apt.freshly-upgraded`, `apt.no-cache` (inverse), `presence.shell`, `shape.size-budget` (≤110 MB), `scan.nonzero-accepted`. Capabilities: `image.forge-rooted-slim-bases`, `image.has-shell`, `test.size-budget`, `scan.regression-gate`.
- 5 smokes: smoke_ca_bundle.sh, smoke_apt_upgraded.sh, smoke_no_apt_cache.sh, smoke_has_shell.sh, smoke_size.sh.
- Measured size: 78.7 MB (budget 110 MB).

### `scripts/discover-images.sh` plumbing

Add a 4th mode (`pre-builders`) to the existing `builders`/`base`/`derivatives` triplet. Pre-builder list explicit in `_PRE_BUILDERS` array (mirrors `_FORGE_BUILDERS`). Side-effect fix: `forge-builder-go-trixie` added to `_FORGE_BUILDERS` (was being classified as `base` before — latent FG-046 oversight, caught on this story's survey).

New mode semantics:
- `pre-builders`: image name in `_PRE_BUILDERS` (debian-slim-trixie, python-slim-trixie)
- `builders`: image name in `_FORGE_BUILDERS` (forge-builder-trixie, forge-builder-go-trixie)
- `base`: no `depends_on` AND not pre-builder AND not builder
- `derivatives`: has `depends_on`

### `scripts/build-image.sh` plumbing

Three additions:
1. Auto-build `debian-slim-trixie` on-demand when the current image's Dockerfile contains `DEBIAN_SLIM_REF` (same pattern as existing forge-builder-trixie / forge-builder-go-trixie auto-build).
2. Auto-build `python-slim-trixie` on-demand when the current image's Dockerfile contains `PYTHON_SLIM_REF`.
3. ARG resolution for `DEBIAN_SLIM_REF` + `PYTHON_SLIM_REF` — prefer `forge-local/<name>:<tag>` if present in daemon, else fall back to `ghcr.io/bboortz/<name>:<tag>`. Pass as `--build-arg` to docker build. Drop `--pull` guard when forge-local.
4. `_HAS_LOCAL_DEP` check extended so buildx cache is disabled when either new ref is forge-local (daemon-only tag).

### Migrated Dockerfiles

| Image | Before | After |
|---|---|---|
| `forge-builder-trixie` | `ARG DEBIAN_BASE=python:3.14-slim-trixie` → `FROM ${DEBIAN_BASE}` | `ARG PYTHON_SLIM_REF=ghcr.io/bboortz/python-slim-trixie:latest` → `FROM ${PYTHON_SLIM_REF}` |
| `cadvisor-slim-trixie` | `ARG DEBIAN_BASE=debian:trixie-slim` → `FROM ${DEBIAN_BASE}` | `ARG DEBIAN_SLIM_REF=ghcr.io/bboortz/debian-slim-trixie:latest` → `FROM ${DEBIAN_SLIM_REF}` |
| `ipmi-exporter-slim-trixie` | `ARG DEBIAN_BASE=debian:trixie-slim` → `FROM ${DEBIAN_BASE}` | `ARG DEBIAN_SLIM_REF=ghcr.io/bboortz/debian-slim-trixie:latest` → `FROM ${DEBIAN_SLIM_REF}` |

Each migrated image preserves:
- Exact wire-level contract (version string, HEALTHCHECK, ENTRYPOINT, CMD, USER, EXPOSE, WORKDIR unchanged)
- Existing smoke suite + acceptance tests
- Runtime behavior

### `.github/workflows/build.yml`

Four-tier publish:
1. **NEW** `publish-pre-builders` (`needs: discover`) — debian-slim-trixie, python-slim-trixie in parallel
2. `publish-builders` (`needs: [discover, publish-pre-builders]`) — forge-builder-trixie, forge-builder-go-trixie
3. `publish-base` (`needs: [discover, publish-builders]`) — unchanged
4. `publish-derivatives` (`needs: [discover, publish-base]`) — unchanged

Discover job emits an additional `pre_builders` output in GITHUB_OUTPUT.

Projected daily-cron wall clock: +2 min (new tier adds ~2 min; existing tiers unchanged).

### `docs/CAPABILITIES.md`

- NEW `build.pre-builder-tier` — four-tier daily-cron publish ordering
- NEW `image.forge-rooted-slim-bases` — forge owns the Debian + Python slim bases
- EXT `build.shared-builder` (FG-025) — now notes the dogfood

### `docs/stories/INDEX.md`

New FG-042 row.

### `docs/plan/IDEAS.md`

- Strike-through + link the original "forge-builder-trixie dogfood" entry (now shipped as FG-042)
- NEW entry: `node-slim-trixie` + `postgres-slim-trixie` renewal candidates (same pattern, promotion trigger: 2nd consumer)

### Red acceptance test — `tests/acceptance/test_FG_042_forge-rooted-slim-bases.sh`

7 sections:
1. **Required files** — debian-slim-trixie Dockerfile + image.yaml + PROMISES.yaml + 5 smokes + scan-baseline.
2. **Build** — debian-slim-trixie builds + all 5 smokes pass.
3. **forge-builder-trixie dogfoods python-slim-trixie** — Dockerfile grep + successful rebuild via forge-local python-slim-trixie.
4. **cadvisor-slim-trixie + ipmi-exporter-slim-trixie FROM debian-slim-trixie** — Dockerfile grep + successful rebuild + FG-037/044 smoke suites still pass.
5. **4-tier publish ordering** — build.yml inspection: publish-pre-builders needs:[], publish-builders needs:publish-pre-builders, chain intact.
6. **discover-images.sh pre-builders mode** — returns debian-slim-trixie + python-slim-trixie (and nothing else).
7. **Upstream grep count drops** — `grep -E "^FROM.*debian:trixie-slim\|python:3.14-slim-trixie" images/*/Dockerfile` matches exactly 2 files (debian-slim-trixie + python-slim-trixie).

## Alternatives rejected

- **python-slim-trixie FROM debian-slim-trixie (deeper dogfood)** — Python 3.14 isn't in trixie's apt (trixie ships 3.13); python-slim-trixie necessarily FROMs upstream `python:3.14-slim-trixie` until we rebuild Python from source. Not worth the effort.
- **forge-builder-go-trixie FROM debian-slim-trixie + apt install go** — Debian trixie's Go is 1.24; forge-builder-go-trixie needs 1.27+ for CVE fixes (which is why FG-046 exists). Golang's official Docker image is the pragmatic source.
- **node-slim-trixie / postgres-slim-trixie now** — single-consumer; adding the pre-builder tier is justified by multi-consumer drift risk. Defer per IDEAS.md renewal entry.
- **Narrow FG-042 (forge-builder-trixie only)** — original 2026-11-09 shelved proposal. Only captured one of three structural wins. The expanded scope (incl. debian-slim-trixie for 2 slim consumers) is justified by the dependency graph's explicit multi-consumer anchors.

## Breaking changes

None observable at the image-contract level:
- Every migrated image's wire-level output (version string, metrics, HEALTHCHECK, etc.) is unchanged.
- Downstream consumers (every scratch image's builder stage) continue to work — forge-builder-trixie still provides syft + CA + apt-upgrade via its new python-slim-trixie base.

Internal (visible only to Forge maintainers):
- 3 Dockerfiles change their ARG name (DEBIAN_BASE → PYTHON_SLIM_REF / DEBIAN_SLIM_REF).
- build.yml gains a new tier.
- scripts/build-image.sh + scripts/discover-images.sh gain new ARG resolution + mode.

## Merge plan

- All blocking gates pass.
- FG-042 acceptance test green (7 sections).
- Every downstream image's existing acceptance test + smoke suite passes unchanged.
- scan-baselines regenerated for cadvisor-slim-trixie + ipmi-exporter-slim-trixie + debian-slim-trixie (first-ever).
- `make test-fast` green.
- Pre-push `check-smart-strict` green.

## Rollout plan

1. Land FG-042 on `dev` via PR → autonomous merge on green CI.
2. Promote dev → main via `release.yml` (user triggers).
3. Daily cron publishes:
   - tier 1: debian-slim-trixie + python-slim-trixie (NEW tier)
   - tier 2: forge-builder-trixie (now dogfoods python-slim-trixie) + forge-builder-go-trixie
   - tier 3 + 4 unchanged; downstream images rebuild against the new refs
4. Operator sees no change in image behavior; Beaconry sees same scan results (no CVE delta expected since the forge-signed intermediates replicate upstream's apt-upgrade state).

## Shipping evidence

| Item | Pointer | Status |
|------|---------|--------|
| Scenario: debian-slim-trixie builds + smokes | `tests/acceptance/test_FG_042_...sh` § 1-2 | ⏳ |
| Scenario: forge-builder-trixie dogfoods python-slim-trixie | § 3 | ⏳ |
| Scenario: cadvisor + ipmi-slim FROM debian-slim-trixie | § 4 | ⏳ |
| Scenario: 4-tier publish ordering | § 5 | ⏳ |
| Scenario: python-slim-trixie in pre-builders tier | § 6 | ⏳ |
| Scenario: upstream grep count drops | § 7 | ⏳ |
| NEW `build.pre-builder-tier` | `docs/CAPABILITIES.md` entry | ⏳ |
| NEW `image.forge-rooted-slim-bases` | `docs/CAPABILITIES.md` entry | ⏳ |
| EXT `build.shared-builder` | `docs/CAPABILITIES.md` update | ⏳ |
| Dependency graph re-traced (post-merge) | `docs/image-dependency-graph.md` | ⏳ (operator-side; follow-up if drift) |
