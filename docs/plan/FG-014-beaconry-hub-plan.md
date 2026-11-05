# FG-014 — Plan: beaconry-hub

**Story**: [`docs/stories/FG-014-beaconry-hub.md`](../stories/FG-014-beaconry-hub.md)
**Status**: shipped
**Branch**: `feat/FG-014-beaconry-hub`

## Design delta

Mirror of the scout shape (FG-012/FG-013):

```
images/beaconry-hub/
  image.yaml      — source.git=bboortz/beaconry, source.ref=latest, source.dockerfile=poc/hub/Dockerfile, source.context=poc
  PROMISES.yaml   — 7 promises
  EXPECTATIONS.yaml — depends on python-scratch-trixie@>=0.2
  tests/
    smoke_http_healthz.sh      — /healthz 200 (with BEACONRY_SKIP_GRYPE_DB=1)
    smoke_docker_bundled.sh    — docker --version
    smoke_grype_bundled.sh     — grype --version
    smoke_syft_bundled.sh      — syft --version
    smoke_no_shell.sh
    smoke_zero_os_cves.sh
    smoke_size.sh              — ≤ 350 MB
```

No code changes outside the image dir + CAP docs + acceptance test. The FG-012 mechanism handles everything.

## Alternatives rejected

- **Ship hub without bundled grype** (consumers install at runtime): hub's `DockerAdapter` + CVE waterfall need grype at startup. Not optional.
- **Don't bundle docker CLI** (use python-on-whales or docker-py): adds Python-side deps and loses the "same CLI on host and in container" audit property beaconry explicitly wanted (BC-009).

## Breaking changes

None. New image dir.

## Merge plan

Single PR. Mirror scout structure. Pre-push runs `make check-strict`.

## Shipping evidence

| Item | Pointer | Status |
|------|---------|--------|
| Scenario: /healthz 200 | `images/beaconry-hub/tests/smoke_http_healthz.sh` | ⏳ |
| Scenario: bundled CLIs | 3 bundled smokes | ⏳ |
| Scenario: OCI labels | FG-014 acceptance § section 3 | ⏳ |
| NEW CAP `image.beaconry-hub` | CAPABILITIES.md | ⏳ |
| NEW CAP `image.beaconry-hub-bundled-tools` | CAPABILITIES.md | ⏳ |
| `make check-strict` green | local | ⏳ |
