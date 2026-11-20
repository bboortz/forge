# FG-075 — Plan: base/ becomes Forge's public API

**Story**: [`docs/stories/FG-075-base-tier-public-api.md`](../stories/FG-075-base-tier-public-api.md)
**Status**: ready → shipped
**Branch**: `feat/FG-075-base-tier-public-api`

## Design delta

Three atomic moves that reframe `base/*` as Forge's public API tier:

**1. Rework Rule 12.** Current rule (post-FG-069) requires every L3 `base/*` image to (a) `FROM scratch` AND (b) have ≥1 forge-internal consumer. Both constraints block slim foundations and zero-internal-consumer "public API" images. Reworked rule drops both and adds a positive requirement: a `base/*` image must have `image.yaml` + `PROMISES.yaml` + be published by the `publish-base` CI tier. Enforcement delegates to Rule 1 (existence) + CI publishing matrix (coverage).

**2. Rename `base/python-trixie` → `base/python-scratch-trixie`.** Reverses decision O3 (drop the redundant `-scratch-` token) for a concrete reason: after FG-075 there are two Python foundations in the tier, slim and scratch; the leaf names must disambiguate. Updates the 3 beaconry `image.yaml depends_on:` atomically.

**3. Create `base/python-slim-trixie`.** New L3 image. FROMs `pre-builder/python-slim-trixie` + installs `python3-pip`, bakes in `/hc` (via `COPY --from=${HC_REF}`), USER 65532, ENTRYPOINT `python3`. Serves dual duty: final runtime for slim Python apps AND builder stage for consumers who want a scratch runtime via `base/python-scratch-trixie` overlay.

The public/internal boundary:
- **Public API**: `base/*` + flat L4 runtimes + (optionally) `mirror/*` for tools.
- **Internal**: `pre-builder/*`, `builder/*`. Paths may be refactored without notice; external consumers should not FROM these.

## Alternatives rejected

- **Keep Rule 12 strict + add a new L4 flat `python-slim-trixie-runtime`** — adds a tier-conflicting name next to existing flat L4 application images (nginx-scratch-trixie, postgres-slim-trixie). Semantic cleaner as `base/python-slim-trixie` where the tier prefix encodes "foundation."
- **Expose `pre-builder/*` as public API** — contradicts the user's stated constraint ("don't use pre-builder/builder outside forge"). The pre-builder/ tier exists for Forge's build-time dedup; leaking it externally couples consumers to internal refactors.
- **Dual-publish both flat `python-slim-trixie` (public) + `pre-builder/python-slim-trixie` (internal)** — doubles the publish matrix; the flat path is a cosmetic alias. Rejected.
- **Add a 5th token to all base/ leaves (`base/python-scratch-trixie` + `base/scratch-scratch-trixie`)** — ridiculous for `scratch-trixie` (would become `base/scratch-scratch-trixie`). Keep `base/scratch-trixie` as the special internal overlay name; apply `-{slim,scratch}-` tokens only to language-family foundations.
- **Bake syft into `base/python-slim-trixie`** — would blur the tier semantic (syft is dev-time, not runtime). Consumers who want syft: `COPY --from=ghcr.io/bboortz/mirror/syft /syft /usr/local/bin/syft` (mirror/ is public-API-eligible for tool passthroughs).

## Breaking changes

**Internal breaking**: `base/python-trixie` rename to `base/python-scratch-trixie`. The 3 beaconry `image.yaml depends_on:` entries update atomically in this FG.

**External breaking** (not addressed in this FG, covered by follow-up):
- `ghcr.io/bboortz/base/python-trixie:*` stops receiving daily-cron updates; last published digest remains fetchable. Downstream consumers (Beaconry's upstream repo) need to update their Dockerfile FROM to `ghcr.io/bboortz/base/python-scratch-trixie:latest` in a separate PR.
- Homelab bots currently FROM `ghcr.io/bboortz/python-slim-trixie:latest` (pre-FG-070 flat path, frozen). They can migrate to `ghcr.io/bboortz/base/python-slim-trixie:latest` (new, daily-cron) in a separate FG-074 revision.

## Merge plan

Full `memory/workflow.md § Blocking gates` matrix. `make test-fast` + PR CI (all FG-NNN acceptance tests) + `make build && scan && verify` locally against the new base/python-slim-trixie digest. No gates waived.

## Rollout plan

1. PR → dev (auto-merge on green CI)
2. Manual `release.yml` dispatch — fast-forward main from dev
3. Manual `build.yml` dispatch on main — publishes 2 new `base/*` tags (slim + renamed scratch)
4. Verify `base/python-slim-trixie:latest` + `base/python-scratch-trixie:latest` live on GHCR via `docker manifest inspect`
5. Follow-up FGs (separate PRs):
   - FG-074 revision: homelab's 7 bots migrate to `base/python-{slim,scratch}-trixie`
   - bboortz/beaconry upstream PR: Dockerfile FROMs flip to `base/python-scratch-trixie` + `builder/python-trixie` (beaconry is forge-published, so builder/ is technically still allowed — but we'll evaluate exposing `base/python-slim-trixie` as a dual-use builder+runtime)

## Shipping evidence

Filled at pre-ship audit. All rows ✅ before merge.

| Item | Pointer | Status |
|------|---------|--------|
| Scenario: rename lands cleanly | `tests/acceptance/test_FG_075_base-tier-public-api.sh:§1` | ✅ |
| Scenario: new slim foundation builds + smokes pass | `tests/acceptance/test_FG_075_base-tier-public-api.sh:§2` | ✅ |
| Scenario: Rule 12 reworked | `tests/acceptance/test_FG_075_base-tier-public-api.sh:§3` | ✅ |
| Scenario: beaconry consumers updated | `tests/acceptance/test_FG_075_base-tier-public-api.sh:§4` | ✅ |
| Scenario: public API documented | `tests/acceptance/test_FG_075_base-tier-public-api.sh:§5` | ✅ |
| Scenario: upstream drift unchanged | `tests/acceptance/test_FG_075_base-tier-public-api.sh:§6` | ✅ |
| CAP `arch.base-tier-public-api` | `tests/acceptance/test_FG_075_base-tier-public-api.sh:§5` + `docs/CAPABILITIES.md#arch.base-tier-public-api` | ✅ |
| CAP `arch.base-tier-images` (EXT) | `docs/CAPABILITIES.md#arch.base-tier-images` | ✅ |
| CAP `image.python-slim-foundation` | `tests/acceptance/test_FG_075_base-tier-public-api.sh:§2` + `docs/CAPABILITIES.md#image.python-slim-foundation` | ✅ |
