#!/usr/bin/env bash
#
# Covers: FG-068
# CAPs:   build.l0-1-source-inventory, arch.l4-absorbs-from-source

set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

say()  { printf '\n\033[1;36m[FG-068]\033[0m %s\n' "$*"; }
pass() { printf '  \033[32m✓\033[0m %s\n' "$*"; }
fail() { printf '  \033[31m✗\033[0m %s\n' "$*" >&2; exit 1; }

# --- (1) inventory module exists + shape ---
say "1. scripts/_upstream_sources.py exists + _UPSTREAM_SOURCES is a dict with ≥10 entries"
test -f scripts/_upstream_sources.py \
  || fail "scripts/_upstream_sources.py missing"
n=$(python3 -c "import sys; sys.path.insert(0,'scripts'); from _upstream_sources import _UPSTREAM_SOURCES; print(len(_UPSTREAM_SOURCES))")
[[ "${n}" -ge 10 ]] \
  || fail "_UPSTREAM_SOURCES has ${n} entries, want ≥10"
# Values must be lists (not strings / sets).
python3 -c "
import sys; sys.path.insert(0,'scripts')
from _upstream_sources import _UPSTREAM_SOURCES
for k, v in _UPSTREAM_SOURCES.items():
    assert isinstance(v, list), f'{k!r}: value must be a list, got {type(v).__name__}'
    assert all(isinstance(c, str) for c in v), f'{k!r}: list must contain str consumer names'
    assert len(v) >= 1, f'{k!r}: must have ≥1 declared consumer'
print('shape ok')
" | grep -q 'shape ok' \
  || fail "_UPSTREAM_SOURCES value shape invalid"
pass "inventory present + shape correct (${n} entries)"

# --- (2) verifier runs clean on current HEAD ---
say "2. verify-source-inventory.py exits 0 on current HEAD"
python3 scripts/verify-source-inventory.py >/dev/null \
  || fail "verify-source-inventory.py failed on current fleet"
# Also asserts stdout contains the "ok" banner.
python3 scripts/verify-source-inventory.py 2>&1 | grep -q 'verify-source-inventory: ok' \
  || fail "verifier output missing 'ok' banner"
pass "verifier green on current HEAD"

# --- (3) synthetic drift — missing inventory entry ---
say "3. verifier catches synthetic drift: new source not in inventory"
_tmp=$(mktemp -d)
# shellcheck disable=SC2064  # _tmp is final — expand-now is intentional
trap "rm -rf '${_tmp}'" EXIT
# Create a tmp images/ tree + copy actual inventory to it so the SKIP list works,
# but add one offending image that clones a NEW URL not registered.
mkdir -p "${_tmp}/scripts"
cp scripts/_upstream_sources.py scripts/verify-source-inventory.py "${_tmp}/scripts/"
mkdir -p "${_tmp}/images/pretend-bot"
cat > "${_tmp}/images/pretend-bot/Dockerfile" <<'EOF'
FROM scratch
RUN git clone https://github.com/some/not-registered-source.git /src
EOF
cat > "${_tmp}/images/pretend-bot/image.yaml" <<'EOF'
tag: "0.1"
platforms: [linux/amd64]
EOF
set +e
# The verifier reads REPO_ROOT from its own location, so running the copy in tmp
# gives it a tmp REPO_ROOT. images/ there has only the offending dir.
cd "${_tmp}"
out=$(python3 scripts/verify-source-inventory.py 2>&1)
rc=$?
cd - >/dev/null
set -e
if [[ $rc -eq 0 ]]; then
  echo "${out}" >&2
  fail "synthetic drift (missing inventory entry) did not trigger failure"
fi
echo "${out}" | grep -qE 'not in inventory|not-registered-source' \
  || { echo "${out}" >&2; fail "failure message didn't flag the missing entry"; }
pass "missing-inventory-entry drift detected"

# --- (4) synthetic drift — undeclared consumer ---
say "4. verifier catches synthetic drift: inventory entry references undeclared consumer"
_tmp2=$(mktemp -d)
# shellcheck disable=SC2064
trap "rm -rf '${_tmp}' '${_tmp2}'" EXIT
mkdir -p "${_tmp2}/scripts"
cp scripts/verify-source-inventory.py "${_tmp2}/scripts/"
# Craft an inventory that points at cadvisor's URL but lists a bogus consumer.
cat > "${_tmp2}/scripts/_upstream_sources.py" <<'EOF'
_UPSTREAM_SOURCES = {
    "github.com/google/cadvisor": ["bogus-image-name"],
}
def canonical_url(url):
    u = url.strip().rstrip('/')
    for p in ("https://","http://"):
        if u.startswith(p): u = u[len(p):]; break
    if u.endswith(".git"): u = u[:-4]
    return u
EOF
# Create a real-URL-using image but under a DIFFERENT name (not "bogus-image-name").
mkdir -p "${_tmp2}/images/cadvisor-slim-trixie"
cat > "${_tmp2}/images/cadvisor-slim-trixie/Dockerfile" <<'EOF'
FROM scratch
RUN git clone https://github.com/google/cadvisor.git /src
EOF
cat > "${_tmp2}/images/cadvisor-slim-trixie/image.yaml" <<'EOF'
tag: "0.1"
platforms: [linux/amd64]
EOF
set +e
cd "${_tmp2}"
out=$(python3 scripts/verify-source-inventory.py 2>&1)
rc=$?
cd - >/dev/null
set -e
if [[ $rc -eq 0 ]]; then
  echo "${out}" >&2
  fail "synthetic drift (undeclared consumer) did not trigger failure"
fi
# Either "consumer drift" OR "inventory drift" (stale bogus-image-name) works —
# both indicate the two-way check fired.
echo "${out}" | grep -qE 'consumer drift|inventory drift' \
  || { echo "${out}" >&2; fail "failure message didn't flag consumer/inventory drift"; }
pass "undeclared-consumer / stale-inventory drift detected"

# --- (5) dep-graph L0.1 subgraph + edges ---
say "5. dep graph emits L0.1 subgraph with ≥10 source nodes + representative edges"
_graph=$(python3 scripts/image_from_graph.py --emit=mermaid)
echo "${_graph}" | grep -q 'subgraph L0_1_sources' \
  || fail "dep graph missing L0_1_sources subgraph"
# Count SRC_* nodes inside the L0.1 subgraph block.
_src_count=$(echo "${_graph}" | awk '/subgraph L0_1_sources/,/^    end$/' | grep -cE '^\s+SRC_[A-Z0-9_]+\[')
[[ "${_src_count}" -ge 10 ]] \
  || fail "L0.1 subgraph has ${_src_count} source nodes, want ≥10"
# Representative edges.
echo "${_graph}" | grep -qE 'SRC_GH_BBOORTZ_BEACONRY -\.-> beaconry-' \
  || fail "L0.1 edge missing: beaconry-* consumers"
echo "${_graph}" | grep -qE 'SRC_ZIGLANG_ORG_DOWNLOAD -\.-> pre-builder_zig_slim_trixie' \
  || fail "L0.1 edge missing: pre-builder/zig-slim-trixie ← ziglang.org/download"
pass "L0.1 subgraph present with ${_src_count} sources + edges"

# --- (6) Makefile wires verify-source-inventory into test-fast ---
say "6. Makefile has verify-source-inventory target + test-fast depends on it"
grep -qE '^verify-source-inventory:' Makefile \
  || fail "Makefile missing verify-source-inventory target"
grep -qE '^test-fast:.*verify-source-inventory' Makefile \
  || fail "Makefile test-fast target doesn't depend on verify-source-inventory"
pass "Makefile wired"

# --- (7) CAPs + memory documented ---
say "7. CAPABILITIES + memory document the new CAPs"
grep -q '^### build.l0-1-source-inventory' docs/CAPABILITIES.md \
  || fail "docs/CAPABILITIES.md missing ### build.l0-1-source-inventory"
grep -q '^### arch.l4-absorbs-from-source' docs/CAPABILITIES.md \
  || fail "docs/CAPABILITIES.md missing ### arch.l4-absorbs-from-source"
grep -q 'L0.1 inventory' memory/docker-standard.md \
  || fail "memory/docker-standard.md missing 'L0.1 inventory' reference"
pass "CAPs + memory present"

# --- (8) [retired FG-069] FG-068 originally asserted "no image dirs moved
# in this PR" — a PR-scoped check that false-positives on every later PR
# that legitimately moves images (starting with FG-069). The assertion
# belonged in the one-time pre-ship audit, not a permanent acceptance
# test. FG-068's real deliverables (L0.1 inventory + verifier + dep-graph
# subgraph + Makefile wiring) are asserted in §§1-7 above.
say "8. FG-068 deliverables remain present (asserted in §§1-7)"
pass "FG-068 asserts its own deliverables, not external state"

echo
echo "FG-068 acceptance: all sections passed."
