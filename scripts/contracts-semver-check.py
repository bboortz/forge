#!/usr/bin/env python3
# Semver gate for PROMISES.yaml edits. Runs as a pre-commit hook.
#
# For each staged images/*/PROMISES.yaml, compares the staged version vs the
# version in HEAD and infers the change class:
#
#   add    (new promise(s))    → declared version must be >= old minor + 1
#   remove (missing promise(s))→ declared version must be >= old major + 1
#   modify (changed description on same id) → requires --allow-modify in the
#                                            commit message OR a new id
#
# No change → version may stay the same.
#
# Exit codes:
#   0 — change class matches version bump (or no changes)
#   1 — gate failed
#   2 — environment/parse problem
#
# Accepts file paths from pre-commit (via argv). With --from-git it diffs
# every staged PROMISES.yaml against HEAD automatically.

from __future__ import annotations

import re
import subprocess
import sys
from pathlib import Path

try:
    import yaml
except ImportError:
    sys.stderr.write("contracts-semver-check: python3-yaml missing. Install via your package manager.\n")
    sys.exit(2)


REPO_ROOT = Path(__file__).resolve().parent.parent
VERSION_RE = re.compile(r"^(\d+)\.(\d+)(?:\.(\d+))?$")


def parse_version(v: str) -> tuple[int, int, int] | None:
    m = VERSION_RE.match(v or "")
    if not m:
        return None
    return (int(m.group(1)), int(m.group(2)), int(m.group(3) or 0))


def load_yaml_text(text: str) -> dict | None:
    try:
        return yaml.safe_load(text) or {}
    except yaml.YAMLError:
        return None


def git_show(path: Path) -> str | None:
    rel = path.relative_to(REPO_ROOT).as_posix()
    p = subprocess.run(
        ["git", "show", f"HEAD:{rel}"],
        cwd=REPO_ROOT, capture_output=True, text=True,
    )
    if p.returncode != 0:
        # File didn't exist in HEAD — brand new PROMISES.yaml file.
        return None
    return p.stdout


def staged_files_from_git() -> list[Path]:
    p = subprocess.run(
        ["git", "diff", "--cached", "--name-only", "--diff-filter=AMR"],
        cwd=REPO_ROOT, capture_output=True, text=True, check=True,
    )
    paths = []
    for line in p.stdout.splitlines():
        if line.startswith("images/") and line.endswith("/PROMISES.yaml"):
            paths.append(REPO_ROOT / line)
    return paths


def commit_message_allows_modify() -> bool:
    """Pre-commit runs before the message is finalized, but if a message file
    is available (COMMIT_EDITMSG) we can read it. For `git commit -m "..."`
    the message is also written to COMMIT_EDITMSG before the hooks run."""
    msg_file = REPO_ROOT / ".git" / "COMMIT_EDITMSG"
    if msg_file.exists():
        try:
            return "--allow-modify" in msg_file.read_text()
        except OSError:
            return False
    return False


def commit_message_allows_breaking() -> bool:
    msg_file = REPO_ROOT / ".git" / "COMMIT_EDITMSG"
    if msg_file.exists():
        try:
            return "--allow-breaking" in msg_file.read_text()
        except OSError:
            return False
    return False


def promise_map(data: dict) -> dict[str, str]:
    """id → description, for diff comparison."""
    out = {}
    for p in data.get("promises", []) or []:
        pid = p.get("id")
        if isinstance(pid, str):
            out[pid] = p.get("description", "")
    return out


def check_file(path: Path, errors: list[str]) -> None:
    rel = path.relative_to(REPO_ROOT).as_posix()
    staged_text = path.read_text()
    staged = load_yaml_text(staged_text)
    if staged is None:
        errors.append(f"{rel}: staged content is not valid YAML")
        return

    head_text = git_show(path)
    if head_text is None:
        # New file. Declared version must parse; nothing else to compare.
        v = staged.get("version")
        if not parse_version(v or ""):
            errors.append(f"{rel}: new file but version: {v!r} is not semver")
        return

    head = load_yaml_text(head_text)
    if head is None:
        errors.append(f"{rel}: HEAD content is not valid YAML — can't diff")
        return

    old_ver = parse_version(head.get("version", ""))
    new_ver = parse_version(staged.get("version", ""))
    if new_ver is None:
        errors.append(f"{rel}: version: {staged.get('version')!r} is not semver")
        return
    if old_ver is None:
        # Old file had no parseable version — treat as fresh, no gate.
        return

    old_p = promise_map(head)
    new_p = promise_map(staged)

    added = sorted(set(new_p) - set(old_p))
    removed = sorted(set(old_p) - set(new_p))
    modified = sorted(k for k in set(old_p) & set(new_p) if old_p[k] != new_p[k])

    if not (added or removed or modified) and new_ver == old_ver:
        return  # no change; no bump required

    # Classify minimum required bump.
    required_part = None  # 0 = major, 1 = minor, 2 = patch
    classification = []
    if removed:
        required_part = 0
        classification.append(f"removed {len(removed)} promise(s): {', '.join(removed)}")
    if added:
        required_part = min(required_part, 1) if required_part is not None else 1
        classification.append(f"added {len(added)} promise(s): {', '.join(added)}")
    if modified:
        if not commit_message_allows_modify():
            errors.append(
                f"{rel}: modified description on id(s) {', '.join(modified)} without --allow-modify in commit message. "
                f"Either introduce a new id OR add '--allow-modify' to the commit message body."
            )
            return
        required_part = min(required_part, 1) if required_part is not None else 1
        classification.append(f"modified description on {len(modified)} promise(s) (with --allow-modify): {', '.join(modified)}")

    # Check the version bump is at least as large as required_part.
    if required_part is None:
        return

    diff = tuple(a - b for a, b in zip(new_ver, old_ver))
    # Minimum valid new versions:
    expected_major = (old_ver[0] + 1, 0, 0)
    expected_minor = (old_ver[0], old_ver[1] + 1, 0)

    if required_part == 0:
        if new_ver < expected_major:
            errors.append(
                f"{rel}: {'; '.join(classification)}; "
                f"this is a major bump — version must be at least {expected_major[0]}.{expected_major[1]}.{expected_major[2]} "
                f"(have {staged.get('version')})."
            )
            return
        if removed and not commit_message_allows_breaking():
            errors.append(
                f"{rel}: removed promise(s) {', '.join(removed)} is a breaking change for any dependent EXPECTATIONS.yaml. "
                f"Either (a) update every dependent EXPECTATIONS.yaml to no longer reference the removed id(s) in this same commit, "
                f"or (b) add '--allow-breaking' to the commit message body to override."
            )
    elif required_part == 1:
        if new_ver < expected_minor:
            errors.append(
                f"{rel}: {'; '.join(classification)}; "
                f"this is at least a minor bump — version must be at least {expected_minor[0]}.{expected_minor[1]}.{expected_minor[2]} "
                f"(have {staged.get('version')})."
            )


def check_pair(old_text: str, new_text: str, label: str, errors: list[str]) -> None:
    """Testable entry point — classify change between two literal YAML strings."""
    old = load_yaml_text(old_text)
    new = load_yaml_text(new_text)
    if old is None:
        errors.append(f"{label}: OLD content not valid YAML")
        return
    if new is None:
        errors.append(f"{label}: NEW content not valid YAML")
        return
    old_ver = parse_version(old.get("version", ""))
    new_ver = parse_version(new.get("version", ""))
    if new_ver is None:
        errors.append(f"{label}: NEW version: {new.get('version')!r} is not semver")
        return
    if old_ver is None:
        return
    old_p = promise_map(old)
    new_p = promise_map(new)
    added = sorted(set(new_p) - set(old_p))
    removed = sorted(set(old_p) - set(new_p))
    modified = sorted(k for k in set(old_p) & set(new_p) if old_p[k] != new_p[k])
    if not (added or removed or modified) and new_ver == old_ver:
        return
    required_part = None
    classification = []
    if removed:
        required_part = 0
        classification.append(f"removed {len(removed)} promise(s): {', '.join(removed)}")
    if added:
        required_part = min(required_part, 1) if required_part is not None else 1
        classification.append(f"added {len(added)} promise(s): {', '.join(added)}")
    if modified:
        if not commit_message_allows_modify():
            errors.append(
                f"{label}: modified description on id(s) {', '.join(modified)} without --allow-modify in commit message. "
                f"Either introduce a new id OR add '--allow-modify' to the commit message body."
            )
            return
        required_part = min(required_part, 1) if required_part is not None else 1
        classification.append(f"modified description on {len(modified)} promise(s) (with --allow-modify): {', '.join(modified)}")
    if required_part is None:
        return
    expected_major = (old_ver[0] + 1, 0, 0)
    expected_minor = (old_ver[0], old_ver[1] + 1, 0)
    if required_part == 0:
        if new_ver < expected_major:
            errors.append(
                f"{label}: {'; '.join(classification)}; "
                f"this is a major bump — version must be at least {expected_major[0]}.{expected_major[1]}.{expected_major[2]} "
                f"(have {new.get('version')})."
            )
            return
        if removed and not commit_message_allows_breaking():
            errors.append(
                f"{label}: removed promise(s) {', '.join(removed)} is a breaking change for any dependent EXPECTATIONS.yaml. "
                f"Either (a) update every dependent EXPECTATIONS.yaml to no longer reference the removed id(s) in this same commit, "
                f"or (b) add '--allow-breaking' to the commit message body to override."
            )
    elif required_part == 1:
        if new_ver < expected_minor:
            errors.append(
                f"{label}: {'; '.join(classification)}; "
                f"this is at least a minor bump — version must be at least {expected_minor[0]}.{expected_minor[1]}.{expected_minor[2]} "
                f"(have {new.get('version')})."
            )


def main() -> int:
    argv = sys.argv[1:]
    errors: list[str] = []

    if argv and argv[0] == "--compare":
        if len(argv) != 3:
            sys.stderr.write("usage: contracts-semver-check.py --compare OLD.yaml NEW.yaml\n")
            return 2
        old_p = Path(argv[1])
        new_p = Path(argv[2])
        check_pair(old_p.read_text(), new_p.read_text(), new_p.name, errors)
        if errors:
            sys.stderr.write(f"contracts-semver-check: FAIL ({len(errors)} issue(s))\n")
            for e in errors:
                sys.stderr.write(f"  ✗ {e}\n")
            return 1
        print(f"contracts-semver-check: ok ({new_p})")
        return 0

    if argv and argv[0] != "--from-git":
        paths = [Path(p).resolve() for p in argv]
        paths = [p for p in paths if p.name == "PROMISES.yaml"]
    else:
        paths = staged_files_from_git()

    if not paths:
        return 0

    for p in paths:
        try:
            check_file(p, errors)
        except Exception as e:  # noqa: BLE001
            errors.append(f"{p}: internal error — {e}")

    if errors:
        sys.stderr.write("contracts-semver-check: FAIL ({} issue(s))\n".format(len(errors)))
        for e in errors:
            sys.stderr.write(f"  ✗ {e}\n")
        return 1

    print(f"contracts-semver-check: ok ({len(paths)} file(s))")
    return 0


if __name__ == "__main__":
    sys.exit(main())
