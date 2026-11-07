# FG-023 — Plan: Stamp-based rebuild skip

**Story**: [`docs/stories/FG-023-smart-rebuild-skip.md`](../stories/FG-023-smart-rebuild-skip.md)
**Status**: in-progress
**Branch**: `feat/FG-023-smart-rebuild-skip`

## Design delta

### New helper: `scripts/stamp-image.sh`

Computes a deterministic stamp for a given image dir. The stamp is a single SHA-256 over:

- **`git ls-tree -r HEAD images/<dir>/`** — content hash of every tracked file under the image dir (Dockerfile, `build.sh`, `image.yaml`, `sid-pins/`, `tests/`, `PROMISES.yaml`, `EXPECTATIONS.yaml`). If a file is modified but not committed, hash its working-tree content instead (keeps dev-loop honest).
- **Resolved FROM digest** — parse `FROM` from the Dockerfile, run `docker buildx imagetools inspect <ref>` or `docker manifest inspect <ref>`, extract the OCI digest. For externally-sourced images (FG-012), parse FROM from the resolved-upstream Dockerfile.
- **Baseline image ID** (scratch derivatives only) — `docker image inspect <baseline> --format {{.Id}}`. Transitive invalidation: baseline rebuild → derivative stamp miss.
- **Resolved external SHA** (FG-012 only) — read from the clone; already computed in `build-image.sh`.

Output: single hex string on stdout. Stamp file path: `.make/stamps/<image>.stamp`.

### `scripts/build-image.sh` integration

Before launching `docker build`:

```bash
NEW_STAMP="$(scripts/stamp-image.sh "${IMAGE_DIR}")"
STAMP_FILE=".make/stamps/${IMAGE_DIR}.stamp"
if [[ "${FORGE_NO_SKIP:-0}" != "1" ]] \
   && [[ -f "${STAMP_FILE}" ]] \
   && [[ "$(cat "${STAMP_FILE}")" == "${NEW_STAMP}" ]] \
   && docker image inspect "${IMAGE_REF}" >/dev/null 2>&1; then
  echo "→ stamp-skip: ${IMAGE_REF} (inputs unchanged, tag present)"
  exit 0
fi

# ... existing build logic ...

mkdir -p "$(dirname "${STAMP_FILE}")"
echo "${NEW_STAMP}" > "${STAMP_FILE}"
```

### Makefile integration

```make
clean-stamps:
	rm -rf .make/stamps/

# check-strict wipes stamps so the strict path is truly cold
check-strict: clean-local-images clean-stamps check
```

### `.gitignore`

Add `.make/stamps/`.

### CAPABILITIES

Add `build.stamp-skip` → test pointer `tests/acceptance/test_FG_023_smart-rebuild-skip.sh`. Extends `tooling.ci-build-cache` + `tooling.smart-check`.

## Alternatives rejected

- **Pin `FROM` to a digest** — defeats the daily-rebuild policy (digest would need daily bump). Our rebuild cadence requires a mutable tag + daily `--pull`.
- **Cache stamp in GHCR as an OCI referrer** — overkill for V1. CI runners are cold; intra-run dedup is the primary win. Cross-machine persistence can come later if measurements show marginal benefit.
- **Hash just the Dockerfile** — misses sid-pin changes, build.sh edits, EXPECTATIONS/PROMISES file changes. Tree hash catches all of these at ~constant cost (`git ls-tree` is O(ms)).
- **Skip scan + smoke too when stamp hits** — correctness risk: a stamp bug would ship an unvalidated image. Stamp-skip stays scoped to `docker build` only; everything downstream still runs against the daemon tag.
- **Store stamps under `$HOME/.cache/forge`** — breaks CI (fresh runners have no cache); repo-local `.make/stamps/` works both local + CI.

## Breaking changes

None. Additive. The stamp check is pre-build and silently falls through to build on any miss.

**Documented new behavior**:
- `.make/stamps/` directory introduced (gitignored). A fresh clone has no stamps; first `make build` populates.
- `make check-strict` now includes `clean-stamps`. Previously identical to `check` modulo image wipe; now also wipes stamps (users who ran `check-strict` to force a full rebuild still get what they wanted).

## Merge plan

Pass all gates from `memory/workflow.md § Blocking gates`:

- hadolint, shellcheck, yamllint
- `make verify-sid-pins`, `make verify-traceability`, `make verify-contracts`
- `make test-acceptance` including the new `test_FG_023_smart-rebuild-skip.sh`
- `make check-smart` passes with stamps populated (second run demonstrates skip)

## Rollout plan

Lands on `dev`. Merges to `main` via next `release.yml` dispatch. Daily `build.yml` is unaffected (does not call `build-image.sh` via check-smart; publishes come through a separate matrix that always rebuilds cold with `--pull`).

## Shipping evidence

| Item | Pointer | Status |
|------|---------|--------|
| Scenario: Stamp-skip avoids redundant rebuilds within a single check-smart run | `tests/acceptance/test_FG_023_smart-rebuild-skip.sh` § 1 | ⏳ |
| Scenario: Stamp invalidates on Dockerfile change | § 2 | ⏳ |
| Scenario: Stamp invalidates on upstream FROM digest change | § 3 (stub via faked digest) | ⏳ |
| Scenario: Stamp invalidates when baseline image ID changes | § 4 | ⏳ |
| Scenario: make check-strict bypasses stamps | § 5 | ⏳ |
| Scenario: FORGE_NO_SKIP=1 bypasses stamps | § 6 | ⏳ |
| CAP `build.stamp-skip` | `tests/acceptance/test_FG_023_smart-rebuild-skip.sh` + `docs/CAPABILITIES.md#buildstamp-skip` | ⏳ |
| EXT `tooling.ci-build-cache` | same | ⏳ |
| EXT `tooling.smart-check` | § 5 | ⏳ |
