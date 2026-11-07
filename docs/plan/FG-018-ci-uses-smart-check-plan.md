# FG-018 — Plan: CI PR uses smart-check

**Story**: [`docs/stories/FG-018-ci-uses-smart-check.md`](../stories/FG-018-ci-uses-smart-check.md)
**Status**: shipped
**Branch**: `feat/FG-018-ci-uses-smart-check`

## Design delta

```diff
 # .github/workflows/ci.yml, full-check job
   full-check:
     ...
     steps:
-      - uses: actions/checkout@v4
+      - uses: actions/checkout@v4
+        with:
+          fetch-depth: 0  # smart-check needs full history for origin/dev..HEAD diff

       - name: Install lint + supply-chain tools
         ...

-      - name: make check (fast + acceptance)
-        run: make check
+      - name: Determine gate target
+        id: gate
+        run: |
+          # PR: smart-check unless `full-check` label forces nuclear
+          if [[ "${{ github.event_name }}" == "pull_request" ]]; then
+            labels='${{ toJSON(github.event.pull_request.labels.*.name) }}'
+            if echo "$labels" | grep -q '"full-check"'; then
+              echo "target=check-strict" >> "$GITHUB_OUTPUT"
+            else
+              echo "target=check-smart" >> "$GITHUB_OUTPUT"
+            fi
+          else
+            # push to dev — full baseline
+            echo "target=check" >> "$GITHUB_OUTPUT"
+          fi
+
+      - name: make ${{ steps.gate.outputs.target }}
+        run: make ${{ steps.gate.outputs.target }}
```

No other changes. FG-017's `scripts/smart-check.sh` already:
- Reads `GITHUB_BASE_REF` and dispatches correctly.
- Bails out to `check-strict` on structural changes.
- Honors `>4 images` cap.
- Runs full-repo lint always (FG-017 Part C) — no CI-only drift risk.

## Alternatives rejected

- **Swap push-to-dev too**: dev is the stable base; smart-check would (correctly) dispatch on dev's own delta, which doesn't match the "every image is known-green" invariant we want for dev. Keep `make check` on push-to-dev.
- **Nuclear by default, label for smart-check**: wrong default; defeats the "fast CI" purpose. Current direction: smart by default, `full-check` label as the escape hatch.
- **Matrix per-image parallelism** (separate FG): orthogonal to scoping; could ship together but adds workflow complexity. Defer.

## Breaking changes

None. `make check` still exists; dev-push + nightly cron keep running it. PR CI output format unchanged (same smart-check `→` log lines as pre-push).

## Rollout

- Merged to `dev` → next PR automatically uses the smart gate.
- First few PRs: watch CI time to confirm the speedup matches the proposal.
- If a smart-check false-negative is caught by nightly within the first week, add that case to FG-017's bailout rules + patch.

## Shipping evidence

| Item | Pointer | Status |
|------|---------|--------|
| Scenario: PR job uses `make check-smart` | FG-018 acceptance § section 1 | ⏳ |
| Scenario: `full-check` label forces `check-strict` | FG-018 acceptance § section 2 | ⏳ |
| Scenario: push-to-dev keeps `make check` | FG-018 acceptance § section 3 | ⏳ |
| Scenario: `GITHUB_BASE_REF` drives dispatch | FG-018 acceptance § section 4 | ⏳ |
| `make check-smart` locally with `GITHUB_BASE_REF=dev` | validates CI's env assumption | ⏳ |
| Nightly cron + full-check safety net | FG-017's `nightly.yml` | ✅ |
| Measured CI wall-clock on this PR | post-merge | ⏳ |
