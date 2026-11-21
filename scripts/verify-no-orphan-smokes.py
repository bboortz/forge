#!/usr/bin/env python3
# verify-no-orphan-smokes — every images/*/tests/smoke_*.sh must be
# referenced by at least one `tests:` entry in some PROMISES.yaml
# (FG-083 Rule a).
#
# Enforces the "DD-TGD inverse" — the existing `verify-traceability`
# rule guarantees every CAP has a test; this script guarantees every
# smoke test has a contract line (promise). Prior gap allowed CI to
# run a test that proved a behaviour the contract never stated
# (surfaced in FG-082's 4-orphan cleanup).
#
# Allowlist is kept empty. If a legitimate orphan ever needs to live
# (e.g. a reusable fixture), add it here with a story reference
# explaining why the DD-TGD convention doesn't apply.

from __future__ import annotations

import sys
from pathlib import Path

try:
    import yaml  # type: ignore
except ImportError:
    sys.stderr.write(
        "verify-no-orphan-smokes: PyYAML not installed; install via "
        "`python3 -m pip install --user pyyaml` or system packager.\n"
    )
    sys.exit(2)

ROOT = Path(__file__).resolve().parents[1]

# Intentionally-orphan smokes. Keep empty; every addition must cite
# a story / cap reason inline.
_ORPHAN_SMOKES_ALLOWLIST: set[str] = set()


def _collect_smokes() -> set[str]:
    out: set[str] = set()
    for p in sorted(ROOT.glob("images/*/tests/smoke_*.sh")):
        out.add(str(p.relative_to(ROOT)))
    for p in sorted(ROOT.glob("images/*/*/tests/smoke_*.sh")):
        out.add(str(p.relative_to(ROOT)))
    return out


def _collect_referenced() -> set[str]:
    out: set[str] = set()
    paths = list(ROOT.glob("images/*/PROMISES.yaml")) + list(
        ROOT.glob("images/*/*/PROMISES.yaml")
    )
    for p in paths:
        try:
            doc = yaml.safe_load(p.read_text())
        except Exception as e:
            sys.stderr.write(
                f"verify-no-orphan-smokes: cannot parse {p.relative_to(ROOT)}: {e}\n"
            )
            continue
        for promise in (doc or {}).get("promises", []) or []:
            for t in promise.get("tests", []) or []:
                out.add(str(t))
    return out


def main() -> int:
    smokes = _collect_smokes()
    referenced = _collect_referenced()
    orphans = sorted((smokes - referenced) - _ORPHAN_SMOKES_ALLOWLIST)

    if orphans:
        sys.stderr.write(
            f"verify-no-orphan-smokes: {len(orphans)} orphan smoke(s) "
            "(not referenced by any PROMISES.yaml tests: entry):\n"
        )
        for o in orphans:
            sys.stderr.write(f"  {o}\n")
        sys.stderr.write(
            "\nEach smoke must be tied to a promise. Either (a) add a "
            "`tests:` line in the image's PROMISES.yaml pointing at "
            "this file, or (b) delete the smoke if it's obsolete.\n"
        )
        return 1

    print(
        f"verify-no-orphan-smokes: ok "
        f"({len(smokes)} smoke(s), {len(referenced)} referenced, 0 orphan(s))."
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
