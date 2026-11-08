# FG-031 — Plan: Embed `hc` in service scratch images

**Story**: [`docs/stories/FG-031-hc-in-service-images.md`](../stories/FG-031-hc-in-service-images.md)
**Status**: in-progress
**Branch**: `feat/FG-031-hc-in-service-images`

## Design delta

### `images/nginx-scratch-trixie/` — add `/hc` + bake HEALTHCHECK

- **Dockerfile**: add `ARG HC_REF=ghcr.io/bboortz/hc:0.1.0` + `FROM ${HC_REF} AS hc` at the top. In the runtime stage, `COPY --from=hc /hc /hc`. Add `HEALTHCHECK --interval=30s --timeout=5s --start-period=5s --retries=3 CMD ["/hc", "-t", "3", "http://127.0.0.1/healthz"]`.
- **nginx.conf**: add a dedicated `location = /healthz { access_log off; return 200 "ok\n"; }` inside the default `server {}`. Non-logged so the healthcheck doesn't flood stdout.
- **PROMISES.yaml**: new promise `runtime.hc-binary` (caps: `image.hc-embedded`) + `runtime.healthz-endpoint` (caps: `image.nginx-serves-http`, ties to the baked HEALTHCHECK). Bump `version: "0.2"` → `"0.3"` (new runtime behavior).
- **Smoke test**: `images/nginx-scratch-trixie/tests/smoke_hc_healthcheck.sh` boots the image, invokes `/hc` via `docker exec` against `/healthz` (expect 0) and against a closed port (expect non-zero).

### `images/python-scratch-trixie/` — add `/hc` only

- **Dockerfile**: same `ARG HC_REF` + `FROM ${HC_REF} AS hc` + `COPY --from=hc /hc /hc`. No HEALTHCHECK (consumer apps vary in port and path).
- **PROMISES.yaml**: new promise `runtime.hc-binary` (caps: `image.hc-embedded`). Bump `version: "0.2"` → `"0.3"`.
- **Smoke test**: `images/python-scratch-trixie/tests/smoke_hc_present.sh` extracts the image via `docker save | tar tf`, asserts `/hc` is present, and runs `/hc` with no args via `docker run --entrypoint=/hc` (expect exit 2 = usage error, hc's documented no-args RC).

### Acceptance test

`tests/acceptance/test_FG_031_hc-in-service-images.sh` with 5 sections:
1. Required files present (both Dockerfiles reference `${HC_REF}`; both PROMISES.yaml carry `runtime.hc-binary`; nginx.conf has `/healthz`; nginx Dockerfile has `HEALTHCHECK`).
2. Build both images via `scripts/build-image.sh`.
3. nginx: `docker inspect` shows a Healthcheck.Test containing `/hc` and `/healthz`; container becomes "healthy" within 30s.
4. python: `docker inspect` shows no Healthcheck; `/hc` present in the image.
5. End-to-end hc runs — nginx case + python case as described in Gherkin.

### No workflow changes

`build.yml` discover job already matches both image dirs; no edits needed.

### No change to the DB/broker trio

`redis-scratch-trixie`, `postgres-scratch-trixie`, `mosquitto-scratch-trixie` keep their native CLIs. Documented in the story's § 7 Out of scope so future readers don't ask "why not redis too?".

## Alternatives rejected

- **Add `/hc` to `scratch-base-trixie` (baseline bump 0.2 → 0.3).** Would propagate to all 5 derivatives in one edit, with one source of truth for the hc version. Rejected because `memory/scratch-closures.md` locks the baseline to a "strict intersection of library closures" — hc is a convenience binary, not a lib, and three of the five derivatives explicitly don't need it (redis/postgres/mosquitto). Baseline growing by 400 KB for three derivatives to carry a binary they don't use violates the principle more than it helps. Revisit if a future scratch image lands that would also want hc (then 3-of-6 grows toward intersection).
- **Bake HEALTHCHECK into python-scratch-trixie too.** Consumer apps vary in port (8000 vs 8080 vs 5000), path (`/health`, `/healthz`, `/-/healthy`), and whether they serve HTTP at all (a pure script image doesn't). A wrong default is worse than no default — consumer adds their own.
- **Ship hc at `/usr/local/bin/hc` instead of `/hc`.** FG-030 established `/hc` as the convention. Changing it would fragment the API across images. Keep `/hc` everywhere.
- **Vendor the hc binary into forge instead of `FROM ghcr.io/bboortz/hc:0.1.0`.** Vendoring means every hc fix requires a forge PR. The published image is small, signed, and the upstream is ours. Stick with `FROM` composition.
- **Drop `healthy-scratch-trixie:2` after this ships.** Keeping it supports consumers who prefer the sidecar-netns pattern (one hc container per host, multiple target services). Removing it would break FG-030 consumers for no benefit.

## Breaking changes

- **nginx-scratch-trixie consumers who mount their own `nginx.conf` wholesale.** The baked HEALTHCHECK points at `/healthz`. If their custom config doesn't define that location, the healthcheck fails. Two mitigations:
  1. Document the `/healthz { return 200; }` contract in a comment in the shipped `nginx.conf`.
  2. Consumers can override the HEALTHCHECK in their derived Dockerfile: `HEALTHCHECK NONE` or a custom one.

  This is the only observable behavior change in FG-031. New `/hc` binary is additive.

- **Image size bumps** (both ≤ 1 MB): nginx ~15 MB → ~15.4 MB; python ~44 MB → ~44.4 MB. Both well within existing budgets.

- No change to the public verify command, tag naming, GHCR repo structure, or attestation format.

## Merge plan

- All gates per `memory/workflow.md § Blocking gates` must pass.
- FG-031 red acceptance test green.
- All existing nginx + python smoke suites still green (regression guard).
- `make test-fast` clean locally before push.
- CI full acceptance sweep green before merge.

## Rollout plan

1. Land FG-031 on `dev` via PR.
2. Promote to `main` via `release.yml` dispatch.
3. Next 03:00 UTC `build.yml` cron publishes `nginx-scratch-trixie:latest` + `python-scratch-trixie:latest` with the new behavior.
4. Homelab follow-up PRs (separate repo, separate PRs):
   - `nextcloud/`: delete `web-hc` service, add `healthcheck:` to `web` service pointing at `/hc -t 5 http://127.0.0.1/`.
   - `sni-router/`: same pattern for its `*-hc` sidecars.
   - `website/`: same, ×2.
5. `healthy-scratch-trixie:2` stays published — supports the sidecar-netns pattern for multi-target checks.

## Shipping evidence

| Item | Pointer | Status |
|------|---------|--------|
| Scenario: nginx ships /hc + auto-healthchecks | `tests/acceptance/test_FG_031_hc-in-service-images.sh` § 3 | ⏳ |
| Scenario: python ships /hc, no baked HEALTHCHECK | § 4 | ⏳ |
| Scenario: nginx /healthz answers 200 end-to-end | § 5 | ⏳ |
| Scenario: homelab drops nginx-hc sidecar | documented in story § 5 (consumer-side; measured in homelab PR follow-ups) | ⏳ |
| Scenario: no size regression | smoke_size.sh in both images (unchanged ceilings) | ⏳ |
| Scenario: no regression in existing smoke suites | full `make test-images` run for nginx + python | ⏳ |
| CAP `image.hc-embedded` (new) | `docs/CAPABILITIES.md#image.hc-embedded` + acceptance + smokes | ⏳ |
| EXT `image.nginx-serves-http` | nginx.conf `/healthz` + smoke_hc_healthcheck.sh | ⏳ |
| EXT `image.python-scratch-nonroot` | python smoke_hc_present.sh | ⏳ |
