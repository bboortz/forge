---
id: FG-060
slug: parallel-downstream-builds
status: ready
owner: bboortz
created: 2026-11-16
---

# FG-060 — smart-check: parallel downstream builds for fan-out images

FG-059 shipped Dockerfile FROM-graph fan-out — a base-image edit (e.g. `forge-builder-python-trixie/Dockerfile`) now exercises every downstream scratch derivative in the SAME PR. Correctness win, but pre-push went from "2-6 min scoped" to "15-20 min" because the 7 fan-out downstreams build serially.

FG-060 splits the AFFECTED set into **direct** (image whose dir was in the diff) vs **fan-out** (transitively affected via FROM-graph). Direct images build sequentially — they must finish before fan-outs can `FROM` their `forge-local/*` tag. Fan-outs then build in parallel via `xargs -P $(nproc)/4` (capped; env-tunable via `FORGE_PARALLEL`).

Expected impact on the base-image-edit case:
- Sequential (post-FG-059): 1 direct + 7 fan-out × 3 min each = **~24 min**
- Parallel-3 (post-FG-060): 3 min direct + ceil(7/3) × 3 min = **~12 min** (50% faster)
- Parallel-4: **~9 min** (62% faster)

## 9 canonical answers

1. **Who** — any dev editing a shared base image (forge-builder-python-trixie, forge-builder-go-trixie, forge-builder-node-trixie, python-slim-trixie, ubuntu-slim-noble, debian-slim-trixie). Local `git push` takes 15-20 min today; target ~9-12 min.

2. **When** — fires on every `make check-smart-strict` run (pre-push + local dev). Also helps CI PR timing if the PR's smart-check path lands on a fan-out shape.

3. **What success looks like**:
   - `scripts/affected_images.py --classify <BASE>` emits `direct:<img>` for files-in-diff entries and `fanout:<img>` for FROM-graph-derived entries. Legacy caller (no flag) still gets a plain sorted list.
   - `scripts/smart-check.sh` reads the classified output: builds DIRECT serially, then parallelizes FANOUT via `xargs -P $cap`.
   - Parallelism cap: default `max(1, $(nproc)/4)` — `FORGE_PARALLEL=N` overrides.
   - All fan-out worker invocations share the same build cache (BuildKit handles concurrent builds); no data race on image tags because each image has a unique `forge-local/<repo>:<tag>` name.
   - FG-017's `_FORGE_IN_CHECK=1` env still propagates to acceptance tests from each parallel worker.
   - Measurable: a synthetic bump to `images/forge-builder-python-trixie/Dockerfile` should trigger fan-out, and total wall-clock for `make check-smart-strict` should drop to ≤12 min (from the current 20+ min baseline).

4. **Urgency** — direct answer to user's "git push takes often long" ask. Not security-material; pure dev-loop productivity.

5. **Happy path**:
   1. Branch `feat/FG-060-parallel-downstream-builds` from `dev`.
   2. Extend `scripts/affected_images.py` with a `--classify` flag that prefixes each image with `direct:` or `fanout:`.
   3. New `scripts/smart-check-image.sh` — extracts the per-image build+smoke+scan+accept block from smart-check.sh into a standalone, callable-by-xargs worker. Takes `<image_dir>` as arg + reads `FORGE_IN_CHECK`, `FORGE_SKIP_WIPE` from env.
   4. Refactor `scripts/smart-check.sh` to:
      - Call `affected_images.py --classify <BASE>`.
      - Partition output into `DIRECT` + `FANOUT` arrays.
      - Build DIRECT serially (loop `smart-check-image.sh "$img"`).
      - Fan-out: `printf '%s\n' "${FANOUT[@]}" | xargs -r -P "$cap" -I{} bash scripts/smart-check-image.sh {}`.
   5. Red acceptance test `test_FG_060_parallel-downstream-builds.sh` with 5 sections (classify flag shape, smart-check-image.sh standalone, smart-check.sh parallelism knob, direct-before-fanout ordering, DRY_RUN exposure of parallelism count).
   6. `make check-smart-strict` green locally.
   7. PR to `dev` → CI full-check → auto-merge on green.

6. **Edge cases / failure modes**:
   - **Fan-out fails**: xargs-P fails as a whole; one image's error masks others. Use `xargs --process-slot-var=N` + explicit result aggregation, OR fall back to `set +e` + collect rc. Simplest: `xargs -P N` with `exit $?` propagation — if any worker fails, overall exit is non-zero. Acceptable.
   - **CPU contention**: default cap is nproc/4. On a 16-core machine → 4 parallel. On a 4-core laptop → 1 (= serial, same as pre-FG-060 for safety).
   - **Docker daemon serialization**: BuildKit DOES parallelize builds across different contexts (verified via Docker docs). No daemon-level lock.
   - **Image cross-dependency within fan-out**: if two fan-out images A and B both FROM a third C, and C is also in FANOUT, parallel ordering could race. **Mitigation**: C would actually be DIRECT (if changed) or an earlier fan-out generation. Current FG-059 fan-out is BFS from DIRECT — the first fan-out generation depends only on DIRECT, so no intra-generation conflict. Future-proof: order FANOUT by shortest-depth-from-DIRECT (already the BFS order) + build generation-by-generation. V1 can rely on BFS order ≡ safe parallel.
   - **Interleaved build logs**: xargs -P scrambles stdout. Workers prefix each log line with `[<image>]`. Easy addition.
   - **`FORGE_SKIP_WIPE`**: still honored by worker.

7. **Out of scope**:
   - **Skipping scan-regression on fan-outs** (Option B from the design discussion). Fine to accept the correctness trade-off separately; this FG focuses on wall-clock reduction via parallelism only.
   - **Minimum-viable smoke suite** (Option C). Deferred.
   - **CI-side parallelism**: GHA already parallelizes acceptance tests (FG-024). smart-check.sh's parallelism helps local pre-push and CI's `check-smart` step (which still runs sequentially per image today).
   - **Build-image.sh changes**: FG-023 stamp-skip interaction. Each worker is a separate `scripts/build-image.sh` invocation; stamps work independently.

8. **How we know it's done** — see Gherkin below.

9. **Capabilities delivered or extended**:
   - EXT `tooling.smart-check` — scoped run now parallelizes the FROM-graph fan-out set.
   - No new CAPs.

## Gherkin acceptance

```
Scenario: affected_images.py --classify prefixes with direct: or fanout:
  Given a diff that touches images/forge-builder-python-trixie/Dockerfile only
  When scripts/affected_images.py --classify <BASE> runs
  Then output includes "direct:forge-builder-python-trixie"
    AND at least one "fanout:*-scratch-trixie" entry
    AND NO "direct:" entry for a fan-out image

Scenario: smart-check-image.sh is independently callable
  Given scripts/smart-check-image.sh exists
  When `bash scripts/smart-check-image.sh python-scratch-trixie` runs
  Then it performs the same build+smoke+scan+accept sequence smart-check used to inline
  And exits 0 on success

Scenario: smart-check parallelizes fan-out
  Given a diff producing DIRECT=[one image] + FANOUT=[≥3 images]
  And FORGE_PARALLEL=3
  When smart-check.sh --dry-run runs
  Then the DRY_RUN output exposes "FANOUT_PARALLEL=3 fanout_count=<N>"

Scenario: FORGE_PARALLEL env var caps parallelism
  Given FORGE_PARALLEL=1
  When smart-check runs with fan-out present
  Then fan-out builds run serially (xargs -P 1)

Scenario: DIRECT builds before FANOUT
  Given fan-out depends on DIRECT images being built first (for local FROM)
  When smart-check runs
  Then DIRECT phase completes before FANOUT phase starts
```
