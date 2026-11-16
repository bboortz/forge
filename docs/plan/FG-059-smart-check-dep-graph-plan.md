---
id: FG-059
slug: smart-check-dep-graph
story: ../stories/FG-059-smart-check-dep-graph.md
---

# FG-059 plan — smart-check dep-graph + finer scripts triage

Story: [FG-059](../stories/FG-059-smart-check-dep-graph.md).

## Edit catalogue

### 1. `scripts/image_from_graph.py` (NEW)

Stand-alone script that parses every `images/*/Dockerfile` and emits a JSON reverse-dependency map.

Parser rules (keep narrow — don't over-engineer):

- Match lines matching `^ARG\s+[A-Z_]+_REF=ghcr\.io/bboortz/([a-z0-9-]+)[:@]` → dependency on `<basename>` IF `images/<basename>/image.yaml` exists.
- Match lines matching `^FROM\s+ghcr\.io/bboortz/([a-z0-9-]+)[:@]` (bare FROM, no ARG) → same.
- Ignore `scratch`, Docker Hub refs, gcr.io refs, etc.
- Ignore commented lines (`#` at column 0 or after whitespace).

Output JSON shape:

```json
{
  "forge-builder-python-trixie": ["python-scratch-trixie", "nginx-scratch-trixie", ...],
  "scratch-base-trixie": ["alertmanager-scratch-trixie", "python-scratch-trixie", ...],
  "python-slim-trixie": ["forge-builder-python-trixie"],
  ...
}
```

Keys are "image that is depended on"; values are "images that FROM it". Reverse-dep orientation (= fan-out when key changes).

Cycle detection: DFS with visited set; nonzero exit + stderr message if a cycle appears.

### 2. `scripts/affected_images.py` (EDIT)

Current structure after the EXPECTATIONS fan-out loop (line ~135):

```python
affected = set(direct)
# ...EXPECTATIONS fan-out loop...
for name in sorted(affected):
    print(name)
```

Add AFTER EXPECTATIONS fan-out, BEFORE printing:

```python
# FG-059: fan out through the Dockerfile FROM graph too. An image's bump
# propagates to every image that FROMs it (recursively, depth ≤ 3 per
# memory/docker-standard.md's chain-depth invariant).
try:
    from_graph = load_from_graph()  # new helper — reads image_from_graph.py's output
except FileNotFoundError:
    from_graph = {}
pending = list(affected)
seen = set(pending)
depth_cap = 5  # generous; chain depth is bounded at 5 anyway
for _ in range(depth_cap):
    next_round = []
    for img in pending:
        for dependent in from_graph.get(img, []):
            if dependent not in seen:
                seen.add(dependent)
                affected.add(dependent)
                next_round.append(dependent)
    if not next_round:
        break
    pending = next_round
```

Helper `load_from_graph()`: shells out to `python3 scripts/image_from_graph.py` and reads the JSON. This keeps the parser in one script.

### 3. `scripts/smart-check.sh` (EDIT)

Current bailout:
```bash
FULL_RE='^(scripts/|Makefile$|\.pre-commit-config\.yaml$|\.github/workflows/|images/scratch-base-trixie/)'
```

Replace with:

```bash
# FG-059: finer scripts/ triage. Core scripts affect every image; non-core
# scripts are image helpers that get their scope via AFFECTED (through
# their caller images).
_CORE_SCRIPTS=(
  scripts/build-image.sh
  scripts/affected_images.py
  scripts/smart-check.sh
  scripts/_image_yaml.sh
  scripts/discover-images.sh
  scripts/stamp-image.sh
  scripts/scan-regression.py
  scripts/verify-no-upstream-drift.sh
  scripts/verify-traceability.sh
  scripts/verify-contracts.py
  scripts/install-tool-from-docker.sh
  scripts/image_from_graph.py          # new — tooling
)

FULL_RE='^(Makefile$|\.pre-commit-config\.yaml$|\.github/workflows/|images/scratch-base-trixie/)'
if changed_matches "${FULL_RE}"; then
  bailout_reason="tooling-or-baseline path=<matched>"
elif changed_matches_core_scripts; then
  bailout_reason="tooling-core path=<matched>"
else
  bailout_reason=""
fi
```

A separate helper `changed_matches_core_scripts` iterates `_CORE_SCRIPTS` against `${CHANGED}`.

### 4. `tests/acceptance/test_FG_059_smart-check-dep-graph.sh` (NEW)

6 sections encoding the Gherkin scenarios. Dry-run smart-check against a simulated commit for the fan-out scenarios (uses `git stash` + `git commit --allow-empty --amend` tricks OR a simpler approach: test `affected_images.py` directly by passing a crafted BASE ref).

### 5. `docs/CAPABILITIES.md` (EDIT)

Extend `tooling.smart-check` (bidirectional link to new test).

### 6. `docs/stories/INDEX.md` (EDIT)

FG-059 row.

## Merge order

1. Branch from `dev`.
2. All edits in one commit.
3. `make check-smart-strict` green locally (requires the graph + script).
4. PR to `dev` → CI full-check → auto-merge.

## Shipping evidence

| Lens | Item | Status |
|------|------|--------|
| Gherkin — graph output shape | Scenario 1 (image_from_graph.py reverse-deps) | ⏳ |
| Gherkin — affected_images fan-out | Scenario 2 (forge-builder-python-trixie fans out) | ⏳ |
| Gherkin — core script full-run | Scenario 3 (scripts/build-image.sh → full) | ⏳ |
| Gherkin — non-core script scoped | Scenario 4 (scripts/smoke-server.sh → scoped) | ⏳ |
| Gherkin — cycle guard | Scenario 5 (parser rejects cycles) | ⏳ |
| Gherkin — no regression | Scenario 6 (image-only change unchanged) | ⏳ |
| Build symmetry | No image rebuilds / no publish changes | ✅ |
| Self-consistency | `tooling.smart-check` CAP extended + wired | ⏳ |
