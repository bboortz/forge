---
id: FG-013
slug: scout-ref-latest
status: in-progress
owner: bboortz
created: 2026-11-05
---

# FG-013 — beaconry-scout: floating `ref: latest` (daily cron tracks upstream main)

Flip `images/beaconry-scout/image.yaml` from `source.ref: "665370e7..."` (pinned sha, FG-012) to `source.ref: "latest"` (Forge keyword → upstream default branch HEAD). Daily `build.yml` cron re-resolves `latest` at build time and bakes the **resolved** sha into `org.opencontainers.image.revision` — so attestation is honest even though the ref itself is floating.

Motivation: beaconry devs merge to `main` on their own cadence. A pinned sha would require a Forge PR per beaconry merge (manual bump); `latest` lets the daily rebuild carry the delta automatically. Audit trail stays intact via the resolved-sha label.

## 9 canonical answers (compressed — trivial delta)

1. **Who** — Beaconry devs (they don't open a Forge PR per merge); auditors (resolved sha still on every image).
2. **When** — daily 03:00 UTC cron + any manual `workflow_dispatch`.
3. **Success** — `source.ref: "latest"`; local build resolves to current HEAD; `org.opencontainers.image.revision` = resolved sha (not literal "latest").
4. **Urgency** — quality-of-life.
5. **Happy path** — one-line YAML change; FG-013 acceptance test verifies resolution + label.
6. **Edge cases** — upstream force-pushes `main`: resolved sha reflects the current tip at build time; no corruption; audit shows the specific sha.
7. **Out of scope** — a pin-bump GHA workflow; mirroring to `beaconry-scout:<beaconry-version-tag>` (future).
8. **Done** — FG-013 acceptance green + `make check` green.
9. **Capabilities**:
   - EXT `build.external-source` — proves `ref: latest` keyword resolves to upstream HEAD and bakes the resolved sha into `org.opencontainers.image.revision`

## Gherkin acceptance

```
Scenario: ref: latest resolves to upstream main HEAD
  Given images/beaconry-scout/image.yaml has source.ref: "latest"
  When scripts/build-image.sh beaconry-scout runs
  Then forge-local/beaconry-scout:0.1 exists
   And docker inspect reports org.opencontainers.image.revision = <upstream main HEAD sha>
   And the label is NOT the literal string "latest"
```

## References

- Plan: [`docs/plan/FG-013-scout-ref-latest-plan.md`](../plan/FG-013-scout-ref-latest-plan.md)
- Red test: [`tests/acceptance/test_FG_013_scout-ref-latest.sh`](../../tests/acceptance/test_FG_013_scout-ref-latest.sh)
