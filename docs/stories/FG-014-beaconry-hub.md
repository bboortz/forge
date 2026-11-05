---
id: FG-014
slug: beaconry-hub
status: in-progress
owner: bboortz
created: 2026-11-05
---

# FG-014 — Add beaconry-hub (externally-sourced)

Second externally-sourced Forge image: `beaconry-hub` published from `bboortz/beaconry@latest` using the FG-012 mechanism. Hub's `poc/hub/Dockerfile` already composes on the FG-009 hardened `python-scratch-trixie:3.13` and bundles three CLIs — docker (29.9.2), grype, syft — plus the hub Python app. Serves `/healthz` + `/readyz` on :8000.

Delta vs scout: three bundled binaries instead of one, much larger image (~350 MB), boot path touches more subsystems (grype DB, telegram client). Smoke suite uses `BEACONRY_SKIP_GRYPE_DB=1` to avoid the ~90s DB download that beaconry's own test compose also skips.

## 9 canonical answers (compressed)

1. **Who** — Beaconry operators who want Forge-signed hub digests; auditors.
2. **When** — on every PR / pre-push / daily cron; `ref: latest` tracks beaconry main.
3. **Success** — `ghcr.io/bboortz/beaconry-hub:0.1` publishes; `/healthz` → 200; docker/grype/syft all `--version`-invocable; `revision` label is a 40-char sha from upstream HEAD.
4. **Urgency** — product tier. Beaconry needs hub published signed-by-Forge.
5. **Happy path** —
   1. `images/beaconry-hub/image.yaml` → source.git + ref: latest + dockerfile: poc/hub/Dockerfile + context: poc
   2. `PROMISES.yaml` — runtime.http-server, runtime.bundled-docker, runtime.bundled-grype, runtime.bundled-syft, absence.shell, absence.os-cves, shape.size-budget (≤350 MB)
   3. `EXPECTATIONS.yaml` — depends on python-scratch-trixie@>=0.2 (same inheritance as scout)
   4. 7 smokes (incl. 3 bundled-binary checks)
   5. FG-014 acceptance test
6. **Edge cases** —
   - Hub boot requires enough env for uvicorn to start: `BEACONRY_SKIP_GRYPE_DB=1`, dummy telegram tokens, `BEACONRY_FIX_ENABLED=0`.
   - Hub uses docker socket for its DockerAdapter; in smoke we don't mount — /healthz returns degraded 200.
   - Hub's `/data` dir needs to be writable (owned 65532:65532) — baked in by the upstream Dockerfile.
7. **Out of scope** — full integration path (hub+scout handshake stays in beaconry CI). docker-socket-mounted production readiness.
8. **Done** — FG-014 acceptance + `make check-strict` green.
9. **Capabilities**:
   - NEW `image.beaconry-hub` — hub image published by Forge
   - NEW `image.beaconry-hub-bundled-tools` — ships working docker, grype, syft CLIs
   - EXT `build.external-source` — second consumer validates mechanism beyond scout

## Gherkin acceptance

```
Scenario: beaconry-hub builds + /healthz = 200
  Given forge-local/beaconry-hub:0.1
  When the container runs with BEACONRY_SKIP_GRYPE_DB=1 + dummy telegram env
  Then GET /healthz on :8000 returns 200 within 30s

Scenario: bundled CLIs are invocable
  Given forge-local/beaconry-hub:0.1
  When docker/grype/syft --version is run
  Then each exits 0 and prints its version

Scenario: image labels pin upstream provenance
  Given hub published with ref: latest
  Then org.opencontainers.image.revision is a 40-char sha
   And org.opencontainers.image.source is bboortz/beaconry
```

## References

- Plan: [`docs/plan/FG-014-beaconry-hub-plan.md`](../plan/FG-014-beaconry-hub-plan.md)
- Red test: [`tests/acceptance/test_FG_014_beaconry-hub.sh`](../../tests/acceptance/test_FG_014_beaconry-hub.sh)
- Upstream: `bboortz/beaconry@main` → `poc/hub/Dockerfile`
