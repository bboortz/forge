# FG-077 — Plan: 3 new base/*-slim-trixie siblings (debian + ubuntu + node)

**Story**: [`docs/stories/FG-077-base-slim-foundations.md`](../stories/FG-077-base-slim-foundations.md)
**Status**: ready → shipped
**Branch**: `feat/FG-077-base-slim-foundations`
**Precedent**: FG-075 `base/python-slim-trixie`

## Design delta

3 new L3 base siblings, one per L1 pre-builder family currently consumed as a final-stage FROM by at least one L4 runtime:

| New image | FROMs (L1) | Current L4 consumer(s) that flip |
|---|---|---|
| `base/debian-slim-trixie` | `pre-builder/debian-slim-trixie` | `cadvisor-slim-trixie`, `ipmi-exporter-slim-trixie` |
| `base/ubuntu-slim-noble` | `pre-builder/ubuntu-slim-noble` | `github-runner-noble` |
| `base/node-slim-trixie` | `pre-builder/node-slim-trixie` | `uptime-kuma-slim-trixie` |

Each image's Dockerfile:
- 2-stage: `FROM ${HC_REF} AS hc` → `FROM ${<family>_SLIM_REF}` runtime
- `COPY --from=hc /hc /hc` — healthcheck probe binary (consumer convenience)
- `USER 65532` — nonroot baseline (distroless parity)
- Family-sensible `ENTRYPOINT`:
  - debian + ubuntu → no ENTRYPOINT (shell is the default; consumers set their own)
  - node → `ENTRYPOINT ["node"]` (parallel to `base/python-slim-trixie`'s `python3`)
- OCI labels per fleet convention

4 consumer Dockerfile edits (final-stage FROM flip only):

| Consumer | Before | After |
|---|---|---|
| github-runner-noble | `FROM ${UBUNTU_SLIM_NOBLE_REF}` | `FROM ${BASE_UBUNTU_SLIM_NOBLE_REF}` + `USER 0` override |
| cadvisor-slim-trixie | `FROM ${DEBIAN_SLIM_REF}` | `FROM ${BASE_DEBIAN_SLIM_REF}` + `USER 0` override |
| ipmi-exporter-slim-trixie | `FROM ${DEBIAN_SLIM_REF}` | `FROM ${BASE_DEBIAN_SLIM_REF}` + `USER 0` override |
| uptime-kuma-slim-trixie | `FROM ${NODE_SLIM_REF}` | `FROM ${BASE_NODE_SLIM_REF}` + override as needed |

Builder-stage FROMs (`BUILDER_GO_REF`, `BUILDER_NODE_REF`) unchanged — the "don't FROM internal tiers" rule applies to the *runtime* FROM; builder stages discard their content.

The USER 0 overrides are needed for the 4 consumers because:
- github-runner-noble: GitHub Actions runner startup script requires root
- cadvisor-slim-trixie: cadvisor requires /sys mount access + root-equivalent capabilities
- ipmi-exporter-slim-trixie: ipmi-exporter requires /dev/ipmi0 device access
- uptime-kuma-slim-trixie: upstream Dockerfile already manages its own user

## Tooling updates

- `scripts/discover-images.sh _BASELINE` set — grows by 3 entries (currently 3 → post-FG-077 6).
- `scripts/verify-dockerfile-conformance.py`:
  - `_BASELINE` set grows by 3.
  - `_INTRA_LAYER_EXEMPTIONS` set grows by 3 (each new base/ FROMs its sibling pre-builder/ — same pattern as `base/python-slim-trixie` → `pre-builder/python-slim-trixie`). **Important**: these are L3 → L1 edges, not strictly "intra-layer", but the exemption set name is `_INTRA_LAYER_EXEMPTIONS` historically for any narrow allowed-FROM-edge that would otherwise trip Rule 6. Reuse for symmetry.
- `scripts/image_from_graph.py _BASELINE` list grows by 3.
- `scripts/build-image.sh`:
  - Add 3 new ARG resolvers (`BASE_DEBIAN_SLIM_REF`, `BASE_UBUNTU_SLIM_NOBLE_REF`, `BASE_NODE_SLIM_REF`) with the standard "prefer local tag, fall back to ghcr" pattern.
  - Add 3 build-arg passes to the `docker build` invocation.
- `_KNOWN_REF_ARGS` in `verify-dockerfile-conformance.py` + `image_from_graph.py` gains the 3 new ARG names.

## Chain-depth impact

| Family | Pre-FG-077 | Post-FG-077 | Cap? |
|---|---|---|---|
| Debian cadvisor + ipmi-exporter-slim | 3 hops | 4 hops | OK |
| Ubuntu github-runner-noble | 3 hops | 4 hops | OK |
| **Node uptime-kuma-slim-trixie** | 4 hops | **5 hops** | **at cap** |

All within the FG-042 ≤5 ceiling. Node is now at cap — explicitly documented in this plan + `memory/docker-standard.md` so any future "Node scratch" addition is flagged as blocked without chain restructuring.

## Alternatives rejected

- **Collapse pre-builder/ INTO base/** — discussed as "Option A" in the FG-076 trade-off review. Buys -1 tier but costs: (a) every current forge builder gets `USER 0 + ENTRYPOINT []` boilerplate; (b) reverses FG-070's pre-builder/ migration; (c) loses the "Forge reserves refactor rights on internal tier" story. Rejected: cost too high for one tier of savings at Forge's current scale.
- **Skip the /hc + USER + entrypoint conveniences in base/*-slim** — reduces base/* to a cosmetic alias of pre-builder/*. Then why have two tiers? Rejected: loses the "/hc for free" value that makes homelab + Beaconry migration attractive.
- **One base/*-slim image shared across families** — doesn't fit; slim bases are family-specific (debian ≠ ubuntu ≠ node; each has its own OS layer).
- **Only ship 1 new base/ (highest-value)** — github-runner-noble is the only pure "pre-builder FROM, no builder" case. But the 3 hybrid cases (cadvisor + ipmi + uptime-kuma) still violate the public-API boundary on their final stage. Shipping incrementally doesn't help; the gap stays open.

## Breaking changes

**None public**. The consumer Dockerfiles' builder-stage FROMs stay (so pulled-image cache, image sizes, and scan baselines don't shift). The final-stage FROM swap adds the `/hc` binary (~1 MB) to each consumer's runtime, which is new behavior — the 4 consumers didn't ship `/hc` before. This is additive; nothing is removed. Scan baselines may shift by one line (hc's SBOM entry).

## Merge plan

Full `memory/workflow.md § Blocking gates`. `make test-fast` + PR CI acceptance suite + visual check on the new SVG + local `make build && scan && verify` on each of the 3 new base/* images.

## Rollout plan

1. PR → dev (auto-merge on green CI).
2. `release.yml` dispatch — fast-forward main from dev.
3. `build.yml` dispatch on main — publishes 3 new `base/*` tags + rebuilds all 4 downstream consumers to pick up the new `/hc` layer.
4. Verify 3 new tags via `docker manifest inspect ghcr.io/bboortz/base/{debian-slim-trixie,ubuntu-slim-noble,node-slim-trixie}:latest`.

## Shipping evidence

Filled at pre-ship audit. All rows ✅ before merge.

| Item | Pointer | Status |
|------|---------|--------|
| Scenario: 3 new base/*-slim exist with explicit repo: | `tests/acceptance/test_FG_077_base-slim-foundations.sh:§1` | ✅ |
| Scenario: all 3 build + smokes pass | `tests/acceptance/test_FG_077_base-slim-foundations.sh:§2` | ✅ |
| Scenario: 4 consumer Dockerfiles flipped | `tests/acceptance/test_FG_077_base-slim-foundations.sh:§3` | ✅ |
| Scenario: Rule 12 passes on 3 new images | `tests/acceptance/test_FG_077_base-slim-foundations.sh:§4` | ✅ |
| Scenario: verify-no-upstream-drift unchanged | `tests/acceptance/test_FG_077_base-slim-foundations.sh:§5` | ✅ |
| Scenario: dep graph includes all 3 foundations | `tests/acceptance/test_FG_077_base-slim-foundations.sh:§6` | ✅ |
| CAP `image.debian-slim-foundation` | test §2 + `docs/CAPABILITIES.md#image.debian-slim-foundation` | ✅ |
| CAP `image.ubuntu-slim-foundation` | test §2 + CAPABILITIES | ✅ |
| CAP `image.node-slim-foundation` | test §2 + CAPABILITIES | ✅ |
| CAP `arch.base-tier-public-api` (EXT) | test §3 + CAPABILITIES | ✅ |
