# FG-030 — Plan: healthy-scratch-trixie v2 (hc)

**Story**: [`docs/stories/FG-030-healthy-scratch-v2.md`](../stories/FG-030-healthy-scratch-v2.md)
**Status**: in-progress — blocked on HC-005 publishing `ghcr.io/bboortz/hc:0.1.0`
**Branch**: `feat/FG-030-healthy-scratch-v2`

## Design delta

### `images/healthy-scratch-trixie/` — new content

- `image.yaml`: tag `"2"`, no `depends_on` (raw FROM scratch, no scratch-base-trixie).
- `Dockerfile`: three-stage.
  - Stage 0: `FROM ${HC_REF} AS hc` (default `ghcr.io/bboortz/hc:0.1.0`; local override `forge-local/hc:0.1.0` for testing).
  - Stage 1: `FROM forge-builder-trixie AS builder` — `syft dir:/ … > /sbom.json`; stage sleep + libc + ld-linux into `/out`.
  - Stage 2: `FROM scratch AS runtime` — `COPY --from=hc /hc /hc`, `COPY --from=builder /out /`, `/sbom.json`. USER 65532; CMD = `["/usr/bin/sleep", "infinity"]`.
- `PROMISES.yaml`: 8 promises (runtime.hc + sleep + sidecar-compat + user-nonroot + no-shell + absence.wget + sbom-embed + size-budget).
- No `EXPECTATIONS.yaml` — image depends on nothing in Forge's inventory.

### Smoke tests (6)

- `smoke_binary_runs.sh` — /hc runs (exits 2 on no-args usage error, that's OK), /usr/bin/sleep runs, /usr/bin/wget is deliberately ABSENT.
- `smoke_cmd_sleeps.sh` — default CMD = sleep infinity, container stays up, clean SIGTERM.
- `smoke_sidecar_healthcheck.sh` — end-to-end: boot redis-scratch-trixie :6379, run hc tcp://localhost:6379 via shared netns → exit 0; hc tcp://localhost:9999 → exit 1.
- `smoke_contents.sh` — /hc + sleep + libc + ld-linux + /sbom.json present; /usr/bin/wget + /usr/bin/nc + libgnutls absent (v1→v2 drop).
- `smoke_no_shell.sh` — /bin/{sh,bash,dash}, /usr/bin/sh absent.
- `smoke_size.sh` — ≤ 5 MB hard ceiling (3.5 MB actual).

### Acceptance test

`tests/acceptance/test_FG_030_healthy-scratch-v2.sh` with 4 sections: file layout, build, smoke suite, image.yaml.

### No workflow changes

`.github/workflows/build.yml`'s discover job auto-detects the image dir. BUT — until HC-005 publishes `ghcr.io/bboortz/hc:0.1.0`, the build job will fail to resolve `FROM ${HC_REF}`. **This PR must remain DRAFT until HC-005 lands.**

## Alternatives rejected

- **Grow hc to include a "sleep forever" mode** — eliminates the need for coreutils sleep + libc + ld-linux; image would drop to ~500 KB. Deferred to HC-006 in the healthy repo.
- **Keep FG-029's `:1` as-is + run them side-by-side** — two tags in flight, migration churn. Ship `:2` and let consumers migrate on their own cadence; `:1` stays published until Forge prunes it.
- **Include wget + hc + nc in the same image** — defeats the entire size-reduction win. Pick one HTTP/TCP client.
- **Base on scratch-base-trixie for the CA bundle** — hc doesn't trust system CAs by design (`--ca file` flag explicitly overrides). The baseline's TLS stack + nss + zoneinfo are unused; raw FROM scratch is correct.

## Breaking changes

**For `:1` consumers upgrading to `:2`:**
- `healthcheck.test:` line must be rewritten. Flag surface changes:
  - `wget -qO- -T 5 URL` → `hc -t 5 URL`
  - `wget --ca-certificate=FILE URL` → `hc --ca FILE URL`
  - `wget -O /dev/null URL` → `hc URL` (hc discards response body)
- `/usr/bin/wget`, `/usr/bin/nc` are no longer present. If any consumer `docker exec`'s into the sidecar to run wget/nc, that breaks. (Unlikely — the sidecar is behind `network_mode:` and typically isn't exec'd.)

**For HC-005 upstream contract:**
- `ghcr.io/bboortz/hc:0.1.0` must publish a Linux amd64 image with `/hc` at the root (static binary). We rely on the published image shape; HC-005's work includes publishing this shape.

## Merge plan

- HC-005 ships first (upstream dependency) OR we vendor hc as a pre-built binary via a local build workflow in forge. Current PR assumes HC-005.
- All gates per `memory/workflow.md § Blocking gates` must pass.
- FG-030 acceptance test green.
- Full acceptance sweep passes (no regression in other images).

## Rollout plan

1. Land FG-030 on `dev` once HC-005 is published.
2. Promote to `main` via `release.yml`.
3. Next 03:00 UTC `build.yml` cron publishes `ghcr.io/bboortz/healthy-scratch-trixie:2`.
4. Homelab PRs update the 4 stacks (image + healthcheck.test rewrite).
5. `:1` stays published for ~6 months as a deprecation window, then is pruned.

## Shipping evidence

| Item | Pointer | Status |
|------|---------|--------|
| Scenario: :2 publishes with standard triple | `tests/acceptance/test_FG_030_healthy-scratch-v2.sh` § 2 | ⏳ (blocked on HC-005) |
| Scenario: image size under 5 MB | § 3 + smoke_size.sh | ✅ (3.5 MB measured locally) |
| Scenario: hc exit codes | § 3 + smoke_sidecar_healthcheck.sh | ✅ |
| Scenario: default CMD sleeps forever | § 3 + smoke_cmd_sleeps.sh | ✅ |
| Scenario: GnuTLS stack is gone | § 3 + smoke_contents.sh | ✅ |
| Scenario: no shell | § 3 + smoke_no_shell.sh | ✅ |
| CAP `image.healthy-sidecar` (updated) | `docs/CAPABILITIES.md` | ⏳ |
| EXT `scan.sbom-embed` + `image.no-shell` + `test.size-budget` | smokes + scan-baseline | ⏳ |
