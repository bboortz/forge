---
id: FG-052
slug: alertmanager-v0.35
story: ../stories/FG-052-alertmanager-v0.35.md
---

# FG-052 plan — alertmanager v0.28.1 → v0.35.0

Story: [FG-052](../stories/FG-052-alertmanager-v0.35.md). This plan captures the design delta, alternatives, merge + rollout order, and the pre-ship evidence table.

## Design delta

### Current (post-FG-046)

```
images/alertmanager-scratch-trixie/Dockerfile
├─ ARG ALERTMANAGER_VERSION=v0.28.1
├─ Stage: scratch_base (FROM scratch-base-trixie)
├─ Stage: hc (FROM ghcr.io/bboortz/hc:0.1.0)
├─ Stage: builder (FROM forge-builder-go-trixie)
│    └─ git clone --branch v0.28.1
│    └─ go build -tags netgo (UI assets ship in source tree, embedded via older embed pattern)
│    └─ cp template/default.tmpl + email.tmpl
└─ Stage: runtime (FROM scratch)
     └─ COPY --from=scratch_base / /
     └─ COPY --from=builder /out /
     └─ COPY --from=builder /sbom.json /sbom.json
     └─ COPY --from=hc /hc /hc
     └─ ENV SSL_CERT_FILE + USER 65534
     └─ HEALTHCHECK /hc → /-/healthy
     └─ ENTRYPOINT [/usr/bin/prometheus-alertmanager]

image.yaml tag: "0.28"
```

### Target (post-FG-052)

```
images/alertmanager-scratch-trixie/Dockerfile
├─ ARG ALERTMANAGER_VERSION=        ← EMPTY (FG-050 build.ref-latest-release)
├─ ARG FORGE_BUILDER_NODE_REF=ghcr.io/bboortz/forge-builder-node-trixie:latest  ← NEW
├─ Stage: scratch_base (unchanged)
├─ Stage: hc (unchanged)
├─ Stage: ui-builder (FROM forge-builder-node-trixie)  ← NEW
│    └─ resolve version via curl + jq (FG-050 pattern) if ARG empty
│    └─ git clone --branch <resolved>
│    └─ (cd ui/app && npm ci && npm run build)         ← Elm UI → ui/app/dist/
│    └─ (cd ui/mantine-ui && npm ci && npm run build)  ← Mantine UI → ui/app/dist/mantine/
│    └─ echo <resolved-version> > /tmp/resolved-version
├─ Stage: builder (FROM forge-builder-go-trixie)
│    └─ COPY --from=ui-builder /src /src    ← includes ui/app/dist/ with both UIs
│    └─ go build -tags "netgo builtinassets" (BUILTINASSETS NEW — was netgo only)
│    └─ cp template/default.tmpl + email.tmpl
│    └─ syft scan dir:/src/ > /sbom.json
└─ Stage: runtime (FROM scratch)
     └─ COPY unchanged + 1 extra label: image.version=<resolved>

image.yaml tag: "latest"          ← was "0.28"
image.yaml tags: ["latest", "latest-amd64"]   ← 2-tag family (floating; same as cadvisor, ipmi-exporter, uptime-kuma)
```

### Delta summary

- **+1 build stage** (`ui-builder`, FROM `forge-builder-node-trixie`) consuming `forge-builder-node-trixie` for the first time in this image.
- **+1 go build tag** (`builtinassets`) so the compiled binary embeds `ui/app/dist/`.
- **-1 version pin** (empty default ARG + build-time GitHub API resolve).
- **1 tag shape change**: `0.28` → `latest` (homelab already references `:latest`, no consumer change).
- **0 wire-level contract changes**: `/-/healthy`, `/-/ready`, `/api/v2/*`, `/`, `/ui/` all respond with same semantics. `webhook_configs` schema unchanged.

## Alternatives rejected

- **Download upstream's pre-built `alertmanager-0.35.0.linux-amd64.tar.gz`** — simpler but regresses FG-046's "we control the toolchain" guarantee. Upstream's Go version happens to match ours today (both 1.27.x) but a future upstream release could drop to an older toolchain silently.
- **Install Elm separately (`curl` elm binary into the builder)** — not needed; Elm 0.19.1-6 is already an npm `devDependency` in `ui/app/package.json`. `npm ci` installs it automatically.
- **Skip the Elm classic UI entirely** (only build Mantine) — would ship an image where `/` 404s. Classic UI is still present in upstream v0.35; dropping it is a shape change we shouldn't introduce unilaterally.
- **Pin to a specific numeric tag** (e.g. `tag: "0.35"`) instead of `:latest` — consistent with FG-050's precedent for images whose upstream has stable release discipline. Alertmanager has that discipline (semver, no CLI contract churn within a minor). Floating is the right call.
- **Separate alertmanager-slim-trixie variant** (shelled sibling like FG-037/044) — no consumer asking. Add if homelab or another consumer requests an interactive shell path.

## Breaking changes (public contract)

- **Image tag**: `ghcr.io/bboortz/alertmanager-scratch-trixie:0.28` is **retired** after next daily cron. Consumers pinned to `:0.28` must switch to `:latest` or a `@sha256:...` digest. Homelab is on `:latest` already — no action. No other known consumer.
- **No consumer CLI change** for `cosign verify` — workflow path unchanged.
- **Alertmanager internal behavior**:
  - `alertmanager_notifications_failed_total{reason="clientError"}` **split** into `reason="authError"` (HTTP 401/403) + `reason="rateLimited"` (HTTP 429) at v0.34. Audit: `grep -rn "notifications_failed_total" /home/benni/git/homelab` → 0 hits. No homelab rule or dashboard touches this metric. Operator-facing note documented in this plan for future consumers.
  - `--enable-feature=auto-gomemlimit` removed; promoted to `--auto-gomemlimit` flag. Homelab doesn't set either. No action.
  - `eventrecorder` config now requires `name` field + new `events/v2` protobuf schema. Homelab doesn't use `eventrecorder`. No action.
  - `types` Go package removed. Internal Go API only; no operator impact.
  - **Rest of the 60+ changelog items are features/bugfixes, non-breaking for config.**

## Merge plan

1. Write story + plan + red test (this commit range).
2. Modify `images/alertmanager-scratch-trixie/Dockerfile` (3-stage dual-builder).
3. Flip `image.yaml` `tag: "0.28"` → `"latest"`.
4. Build + run local smokes to confirm new UIs serve from embedded assets.
5. Regenerate `scan-baseline.json` (will shift: fresh source tree means different Go module versions in the SBOM; expect more CRITICALs than v0.28.1 because 13 months of new deps + occasional transitive-dep CVEs).
6. `make check` + traceability.
7. PR to `dev` → CI full-check → auto-merge on green.
8. Manual release.yml promote dev → main.
9. Trigger `build.yml` manual run to publish immediately (optional; next daily cron also works).

## Rollout plan

- **Homelab**: zero-touch. `docker compose pull && docker compose up -d` on server2 + hetzner-staging picks up the new image via `:latest`. State in `/var/lib/prometheus/alertmanager` is schema-compatible.
- **Rollback**: if v0.35 misbehaves, pin homelab to the last known-good digest via `image: ghcr.io/bboortz/alertmanager-scratch-trixie@sha256:<v0.28-digest>`. The cosign-signed v0.28 digest stays on GHCR indefinitely.
- **Observability**: homelab's existing `/-/healthy` healthcheck + `alertmanager_notifications_failed_total` (for whatever still references it externally — grep said zero on homelab, but not surveyed on beaconry) continues to work.

## Shipping evidence (filled before commit)

| Lens | Item | Status |
|------|------|--------|
| Gherkin coverage | Scenario 1 (ui-builder resolves + both UIs build) | ⏳ pending test |
| Gherkin coverage | Scenario 2 (HTTP API endpoints) | ⏳ pending test |
| Gherkin coverage | Scenario 3 (amtool --version) | ⏳ pending test |
| Gherkin coverage | Scenario 4 (homelab config compat) | ⏳ pending test |
| Build/scan symmetry | alertmanager-scratch-trixie builds from forge-builder-node + forge-builder-go | ⏳ |
| Build/scan symmetry | scan-baseline.json regenerated for v0.35 | ⏳ |
| Build/scan symmetry | cosign + syft + grype all run on the digest | ✅ unchanged pipeline |
| Self-consistency | `image.has-shell` NOT claimed (still scratch) | ✅ |
| Self-consistency | `absence.os-cves` promise still holds (no dpkg in runtime) | ⏳ verify via scan |
| Self-consistency | Homelab compose unchanged | ✅ compose points at :latest |
