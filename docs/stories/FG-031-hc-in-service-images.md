---
id: FG-031
slug: hc-in-service-images
status: shipped
owner: bboortz
created: 2026-11-08
---

# FG-031 — Embed `hc` in service scratch images (drop sidecar containers)

FG-030 shipped `healthy-scratch-trixie:2` as a 405 KB scratch sidecar — the current homelab pattern is one `*-hc` companion per service, linked via `network_mode: service:<svc>`. Four homelab stacks run this pattern today (`nextcloud/web-hc`, `sni-router/*-hc`, `website/*-hc` ×2).

FG-031 removes the sidecar entirely for the images that actually need it. `nginx-scratch-trixie` gains an in-image `/hc` + a baked `HEALTHCHECK` on `/healthz`; `python-scratch-trixie` gains `/hc` (no baked HEALTHCHECK — consumer apps vary in port + path). The DB/broker trio (`redis`, `postgres`, `mosquitto`) keep their native healthcheck CLIs (`redis-cli PING`, `pg_isready`, `mosquitto_pub`) — `hc` would be redundant there.

## 9 canonical answers

1. **Who** — homelab operator (me) first, every downstream consumer of `nginx-scratch-trixie` / `python-scratch-trixie` second. Also: Forge maintainer auditing the scratch suite.

2. **When** — fires every time a consumer wants a docker-native healthcheck for a scratch nginx or python-scratch service and today has to run a sidecar. Pipeline fires on next 03:00 UTC cron after this lands on `main`.

3. **What success looks like**:
   - `ghcr.io/bboortz/nginx-scratch-trixie:latest` ships `/hc` at the root + a `HEALTHCHECK` instruction. `docker inspect` shows `Healthcheck.Test` populated. `docker run -d` → healthy in <30s.
   - `ghcr.io/bboortz/python-scratch-trixie:latest` ships `/hc` at the root. No `HEALTHCHECK` baked (consumer sets it).
   - Both images stay under their current size budgets (nginx ≤ 18 MB; python ≤ 60 MB).
   - Homelab: `web-hc` / `sni-router-hc` / `website-*-hc` sidecar containers are removed; healthchecks move into the service container's compose block.
   - grype scan stays clean (hc has no OS footprint).

4. **Urgency** — Quality-of-life for the homelab operator. Each sidecar removed is one less container, one less image pull, one less set of scan/sign artifacts to manage. Not security-critical; FG-030's sidecar pattern works today.

5. **Happy path**:
   1. Forge publishes `nginx-scratch-trixie:latest` with `/hc` + baked HEALTHCHECK.
   2. Forge publishes `python-scratch-trixie:latest` with `/hc`.
   3. Homelab rewrites each stack's compose: delete the `*-hc` service, move the `healthcheck:` block into the primary service, point `test:` at `/hc <scheme://127.0.0.1/path>`.
   4. `docker compose up -d` — service turns healthy via the in-container `/hc` call, no sidecar needed.

6. **Edge cases / failure modes**:
   - **Nginx's default HEALTHCHECK URL must actually answer 200.** Today `nginx.conf` serves `/` from `/usr/share/nginx/html` which returns 200 — but any consumer who mounts their own `nginx.conf` without a `/healthz` (or `/`) handler would see the baked HEALTHCHECK fail. Mitigation: add a dedicated `location = /healthz { return 200 "ok\n"; }` to the shipped default config, point HEALTHCHECK at `/healthz`, and document in the plan that consumers who swap `nginx.conf` wholesale should either add their own `/healthz` or override the HEALTHCHECK in their Dockerfile.
   - **Consumer's python app serves on a non-8000 port, or doesn't serve HTTP at all.** This is why we don't bake a HEALTHCHECK into python-scratch-trixie — each consumer adds their own. `/hc` is still present for them to use.
   - **hc version drift.** We pin `HC_REF=ghcr.io/bboortz/hc:0.1.0` identically in both Dockerfiles (same ARG default as FG-030). Future bumps edit three Dockerfiles. Acceptable for V1; could be hoisted later if frequency warrants.
   - **Image size creep.** hc is ~400 KB; neither image's size budget is tight enough for this to bite (nginx is ~15 MB, budget 18; python is ~44 MB, budget 60).

7. **Out of scope**:
   - Adding `/hc` to `redis-scratch-trixie`, `postgres-scratch-trixie`, `mosquitto-scratch-trixie` — they ship native CLIs that already do exactly this (`redis-cli PING`, `pg_isready`, `mosquitto_sub -C 1`). Adding hc there is redundancy.
   - Adding `/hc` to `scratch-base-trixie` — would propagate automatically to all derivatives but violates the baseline's locked "strict intersection of libraries" principle (`memory/scratch-closures.md`). Baseline is for shared libs; hc is a convenience binary for a subset. Deferred unless/until every scratch derivative wants it.
   - Removing `healthy-scratch-trixie:2`. That image remains published for legacy sidecar flows (consumers who don't want to rebuild) and for stacks where sidecar-netns is architecturally preferred (e.g. multi-target checks from a single sidecar).
   - Bundling a sample Prometheus exporter or k8s-liveness-style endpoint — scope creep.
   - python-scratch HEALTHCHECK defaults. Consumer-side decision.

8. **How we know it's done** — see Gherkin below.

9. **Capabilities delivered or extended**:
   - NEW `image.hc-embedded` — nginx-scratch-trixie + python-scratch-trixie carry `/hc` as a first-party in-image healthcheck tool.
   - EXT `image.nginx-serves-http` — gains a baked HEALTHCHECK against `/healthz`; default config serves that path.
   - EXT `image.python-scratch-nonroot` — `/hc` present; consumer configures HEALTHCHECK.

## Gherkin acceptance

```
Scenario: nginx-scratch-trixie ships /hc and auto-healthchecks itself
  Given forge-local/nginx-scratch-trixie:latest is built
  When the container runs with default config
   And `docker inspect --format {{.Config.Healthcheck.Test}}` is read
  Then Healthcheck.Test contains "/hc" and "/healthz"
   And within 30s the container status becomes "healthy"

Scenario: python-scratch-trixie ships /hc for consumer use
  Given forge-local/python-scratch-trixie:latest is built
  When the image contents are inspected via `docker save | tar tf`
  Then /hc is present
   And no HEALTHCHECK is baked into the image (`docker inspect` → None)

Scenario: nginx /healthz answers 200 end-to-end
  Given a running forge-local/nginx-scratch-trixie:latest container on :80
  When `/hc -t 3 http://127.0.0.1/healthz` is invoked via `docker exec`
  Then it exits 0 (healthy)
  When `/hc -t 3 http://127.0.0.1:9999/` is invoked (closed port)
  Then it exits non-zero (unhealthy)

Scenario: homelab drops its nginx-hc sidecar
  Given a homelab compose file with a nginx service + nginx-hc sidecar
  When the sidecar block is removed
   And healthcheck is added to the nginx service with test = [CMD, /hc, -t, 5, http://127.0.0.1/healthz]
  Then `docker compose up -d` produces exactly one container that reports healthy
   And the sidecar image is no longer referenced

Scenario: no size regression
  Given the built nginx + python scratch images
  Then nginx-scratch-trixie size ≤ 18 MB (unchanged ceiling)
   And python-scratch-trixie size ≤ 60 MB (unchanged ceiling)

Scenario: hc doesn't break existing smoke suites
  Given the FG-006 + FG-003 acceptance tests
  When they are re-run against the FG-031 images
  Then every existing assertion still passes
```

## References

- Plan: `docs/plan/FG-031-hc-in-service-images-plan.md`
- Red test: `tests/acceptance/test_FG_031_hc-in-service-images.sh`
- Capabilities: see `docs/CAPABILITIES.md`
- Upstream: `bboortz/healthy` (`ghcr.io/bboortz/hc:0.1.0`)
- Predecessor: FG-030 (healthy-scratch-trixie:2 — sidecar pattern)
- Homelab touchpoints: `~/git/homelab/docker/{nextcloud,sni-router,website}/docker-compose.yml.j2` (4 `*-hc` sidecars to retire)
