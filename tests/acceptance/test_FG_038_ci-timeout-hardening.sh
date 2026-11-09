#!/usr/bin/env bash
#
# Covers: FG-038
# CAPs:   ci.timeout-hardened
#
# Validates FG-038: every job in every forge workflow carries an
# explicit `timeout-minutes`; the two known-flaky steps (Cache grype DB
# via actions/cache@v4; Install supply-chain tools) carry short
# step-level timeouts + continue-on-error so a GHA-service hang fails
# fast instead of blocking the pipeline for hours.

set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

say()  { printf '\n\033[1;36m[FG-038]\033[0m %s\n' "$*"; }
pass() { printf '  \033[32m✓\033[0m %s\n' "$*"; }
fail() { printf '  \033[31m✗\033[0m %s\n' "$*" >&2; exit 1; }

# -----------------------------------------------------------------------------
# Section 1 — every job has a sane timeout-minutes
# -----------------------------------------------------------------------------
say "1. every workflow job carries an explicit timeout-minutes"

python3 - <<'PY'
import sys
import pathlib
import yaml

ROOT = pathlib.Path(".")
WF_DIR = ROOT / ".github" / "workflows"

# Expected caps per job. Any missing job is flagged; any job with an
# unexpected cap fails the bounds check.
#
# Values from docs/plan/FG-038-ci-timeout-hardening-plan.md § Per-job
# timeout-minutes table.
EXPECTED = {
    "ci.yml":      {"fast-check": (1, 10), "lint-verify": (1, 10), "discover": (1, 10),
                    "acceptance-matrix": (4, 10), "acceptance-aggregate": (1, 5),
                    "release-check": (1, 10)},
    "build.yml":   {"discover": (1, 10),
                    "publish-builders": (5, 12), "publish-base": (5, 12),
                    "publish-derivatives": (10, 18)},
    "release.yml": {"promote": (1, 10)},
    "nightly.yml": {"check-strict": (40, 60)},
}

errors = []
for wf, want in EXPECTED.items():
    path = WF_DIR / wf
    doc = yaml.safe_load(path.read_text())
    jobs = doc.get("jobs", {})
    for job, (lo, hi) in want.items():
        if job not in jobs:
            errors.append(f"{wf}: missing expected job '{job}'")
            continue
        tm = jobs[job].get("timeout-minutes")
        if tm is None:
            errors.append(f"{wf}:{job}: no timeout-minutes set")
            continue
        if not isinstance(tm, int) or tm < lo or tm > hi:
            errors.append(f"{wf}:{job}: timeout-minutes={tm} outside expected range [{lo},{hi}]")
    # Also: every job should have timeout-minutes, including any we didn't
    # explicitly enumerate (defense against future untracked job additions).
    for job, spec in jobs.items():
        if "timeout-minutes" not in spec:
            errors.append(f"{wf}:{job}: no timeout-minutes set (job not in expected table)")

if errors:
    for e in errors:
        print(f"  ✗ {e}")
    sys.exit(1)
PY
pass "all 12 jobs across 4 workflows have sane timeout-minutes"

# -----------------------------------------------------------------------------
# Section 2 — step-level timeouts on the known-flaky steps
# -----------------------------------------------------------------------------
say "2. Cache grype DB + Install supply-chain tools carry step timeouts"

python3 - <<'PY'
import sys
import pathlib
import yaml

ROOT = pathlib.Path(".")
WF_DIR = ROOT / ".github" / "workflows"

errors = []
for path in sorted(WF_DIR.glob("*.yml")):
    doc = yaml.safe_load(path.read_text())
    for jname, jspec in doc.get("jobs", {}).items():
        for step in jspec.get("steps", []) or []:
            name = step.get("name", "")
            uses = step.get("uses", "") or ""

            # Cache grype DB: actions/cache@v4 with grype key.
            if "Cache grype DB" in name or (uses.startswith("actions/cache@") and
                                             "grype" in str(step.get("with", {})).lower()):
                tm = step.get("timeout-minutes")
                coe = step.get("continue-on-error")
                if tm is None or tm > 5 or tm < 1:
                    errors.append(f"{path.name}:{jname}:{name}: timeout-minutes={tm} not in [1,5]")
                if coe is not True:
                    errors.append(f"{path.name}:{jname}:{name}: continue-on-error must be true (got {coe})")

            # Install supply-chain tools: hits Docker Hub rate-limits occasionally.
            if "Install supply-chain tools" in name or "install-tool-from-docker" in name.lower():
                tm = step.get("timeout-minutes")
                if tm is None or tm > 10 or tm < 1:
                    errors.append(f"{path.name}:{jname}:{name}: timeout-minutes={tm} not in [1,10]")

if errors:
    for e in errors:
        print(f"  ✗ {e}")
    sys.exit(1)
PY
pass "flaky steps carry continue-on-error + short timeouts"

# -----------------------------------------------------------------------------
# Section 3 — CAP registered
# -----------------------------------------------------------------------------
say "3. CAP ci.timeout-hardened registered"
grep -q '^### ci\.timeout-hardened' docs/CAPABILITIES.md \
  || fail "docs/CAPABILITIES.md: missing CAP ci.timeout-hardened"
pass "ci.timeout-hardened entry present"

echo
echo "FG-038 acceptance: all sections passed."
