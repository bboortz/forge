---
id: FG-060
slug: parallel-downstream-builds
story: ../stories/FG-060-parallel-downstream-builds.md
---

# FG-060 plan — parallel downstream builds in smart-check

Story: [FG-060](../stories/FG-060-parallel-downstream-builds.md).

## Edit catalogue

### 1. `scripts/affected_images.py` — add `--classify` flag

Current output: one image dir name per line.

Add: `--classify` → prefix each name with `direct:` or `fanout:`.
- `direct:` = image dir appeared in `git diff --name-only`.
- `fanout:` = image pulled in by EXPECTATIONS or FG-059 FROM-graph fan-out.

Legacy caller behaviour unchanged (prints bare names).

### 2. `scripts/smart-check-image.sh` (NEW)

Extracts the per-image loop body from `smart-check.sh`. Takes `<image_dir>` as `$1`. Reads `FORGE_IN_CHECK`, `FORGE_SKIP_WIPE` from env. Performs:

```
docker rmi forge-local/<repo>:<tag>   # if !FORGE_SKIP_WIPE
bash scripts/build-image.sh <img>
bash scripts/test-images.sh <img>
python3 scripts/scan-regression.py <img>   # if grype installed
bash tests/acceptance/test_FG_*_<img-slug>*.sh   # if any
```

Log lines prefixed with `[<image>] ` so parallel output stays attributable.

### 3. `scripts/smart-check.sh` — split + parallelize

Replace the current for-loop with:

```bash
mapfile -t CLASSIFIED < <(python3 scripts/affected_images.py --classify "${BASE}")
DIRECT=()
FANOUT=()
for line in "${CLASSIFIED[@]}"; do
  case "${line}" in
    direct:*) DIRECT+=("${line#direct:}") ;;
    fanout:*) FANOUT+=("${line#fanout:}") ;;
  esac
done

# Phase 1: direct — serial. Fan-out images FROM these; must complete first.
for img in "${DIRECT[@]}"; do
  bash scripts/smart-check-image.sh "${img}"
done

# Phase 2: fan-out — parallel.
if [[ ${#FANOUT[@]} -gt 0 ]]; then
  nproc_count=$(nproc 2>/dev/null || echo 4)
  default_cap=$(( nproc_count / 4 ))
  [[ $default_cap -lt 1 ]] && default_cap=1
  cap="${FORGE_PARALLEL:-$default_cap}"
  say "fan-out: ${#FANOUT[@]} image(s), parallelism=${cap}"
  printf '%s\n' "${FANOUT[@]}" \
    | xargs -r -n1 -P "${cap}" bash scripts/smart-check-image.sh
fi
```

DRY_RUN output extended to expose `FANOUT_PARALLEL=<cap> fanout_count=<N>`.

### 4. `tests/acceptance/test_FG_060_parallel-downstream-builds.sh` (NEW)

5 sections encoding the Gherkin scenarios.

### 5. `docs/CAPABILITIES.md` — extend `tooling.smart-check`

Add fan-out parallelism to the description + bidirectional link.

### 6. `docs/stories/INDEX.md` — FG-060 row.

## Merge order

1. Branch from `dev`.
2. All edits in one commit.
3. Red test green locally.
4. PR → CI full-check → auto-merge.

## Shipping evidence

| Lens | Item | Status |
|------|------|--------|
| Gherkin — classify flag | Scenario 1 (direct: + fanout: prefixes) | ⏳ |
| Gherkin — worker standalone | Scenario 2 (smart-check-image.sh callable) | ⏳ |
| Gherkin — DRY_RUN shows parallelism | Scenario 3 (FANOUT_PARALLEL exposure) | ⏳ |
| Gherkin — env knob | Scenario 4 (FORGE_PARALLEL caps) | ⏳ |
| Gherkin — ordering | Scenario 5 (DIRECT before FANOUT) | ⏳ |
| Self-consistency | `tooling.smart-check` CAP extended | ⏳ |
| No contract change | ✅ (dev-loop tooling only) | ✅ |
