# FG-013 — Plan: scout `ref: latest`

**Story**: [`docs/stories/FG-013-scout-ref-latest.md`](../stories/FG-013-scout-ref-latest.md)
**Status**: shipped
**Branch**: `feat/FG-013-scout-ref-latest`

## Design delta

One-line change to `images/beaconry-scout/image.yaml`:

```diff
 source:
   git: https://github.com/bboortz/beaconry
-  ref: "665370e7d793968b5b8fc550fbd0582993a829fc"
+  ref: "latest"
   dockerfile: poc/scout/Dockerfile
   context: poc
```

The FG-012 mechanism already handles `latest` as a keyword — `scripts/build-image.sh` does `git fetch --depth=1 origin HEAD` → `git rev-parse HEAD` → bakes the resolved sha into `org.opencontainers.image.revision` via `--label`. No code change needed; this story just flips one YAML scalar and proves the floating-ref path works end-to-end.

## Alternatives rejected

- **Track a specific tag** (`ref: "v0.15.0"`): beaconry doesn't release-tag yet. Would require re-pinning per tag.
- **Automated bump-pin GHA workflow** (bot-PR'd per beaconry main advance): more moving parts; defer until pin-churn becomes painful.
- **Separate `beaconry-scout:main` + `beaconry-scout:<sha>` tags**: operator friction (what to pull?); tag family already includes `latest` via the publish matrix.

## Breaking changes

None. Consumers pinning `ghcr.io/bboortz/beaconry-scout:0.1` get the same tag; the content moves. Consumers who want immutability pin the digest.

## Merge plan

Single PR. One YAML line + acceptance test.

## Shipping evidence

| Item | Pointer | Status |
|------|---------|--------|
| Scenario: `latest` resolves + label carries sha | `tests/acceptance/test_FG_013_scout-ref-latest.sh` | ✅ |
| `make check-strict` green on cold cache | local | ⏳ |
| Post-publish: next daily cron produces a different digest than today's | post-publish | ⚠️ |
