#!/usr/bin/env bash
#
# Covers: FG-050
# CAPs:   build.ref-latest-release,
#         image.cadvisor-serves-metrics, image.ipmi-exporter-serves-metrics,
#         image.node-exporter-serves-metrics,
#         scan.regression-gate, test.size-budget

set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

say()  { printf '\n\033[1;36m[FG-050]\033[0m %s\n' "$*"; }
pass() { printf '  \033[32m✓\033[0m %s\n' "$*"; }
fail() { printf '  \033[31m✗\033[0m %s\n' "$*" >&2; exit 1; }

# ---------------------------------------------------------------------------
# §1. Dockerfiles + image.yaml carry the expected pin shape per image.
# ---------------------------------------------------------------------------

say "1. Dockerfile ARG + image.yaml tag correctness per image"

# --- cadvisor-slim-trixie: :latest pattern (empty ARG) ---
dockerfile=images/cadvisor-slim-trixie/Dockerfile
imageyaml=images/cadvisor-slim-trixie/image.yaml
if ! grep -qE '^ARG CADVISOR_VERSION=\s*$' "$dockerfile"; then
  fail "${dockerfile} must have an EMPTY-default ARG CADVISOR_VERSION= (FG-013/045 pattern)"
fi
tag=$(awk '$1 == "tag:" {gsub(/["\x27]/,"",$2); print $2; exit}' "$imageyaml")
[[ "$tag" == "latest" ]] || fail "${imageyaml}: tag = '${tag}' (want 'latest')"
pass "cadvisor-slim-trixie: ARG CADVISOR_VERSION= empty, image.yaml tag=latest"

# --- ipmi-exporter-scratch-trixie AND -slim-trixie: :latest pattern, shared ARG shape ---
scratch_df=images/ipmi-exporter-scratch-trixie/Dockerfile
slim_df=images/ipmi-exporter-slim-trixie/Dockerfile
scratch_yaml=images/ipmi-exporter-scratch-trixie/image.yaml
slim_yaml=images/ipmi-exporter-slim-trixie/image.yaml

for df in "$scratch_df" "$slim_df"; do
  if ! grep -qE '^ARG IPMI_EXPORTER_VERSION=\s*$' "$df"; then
    fail "${df} must have an EMPTY-default ARG IPMI_EXPORTER_VERSION= (FG-013/045 pattern)"
  fi
done
for yml in "$scratch_yaml" "$slim_yaml"; do
  tag=$(awk '$1 == "tag:" {gsub(/["\x27]/,"",$2); print $2; exit}' "$yml")
  [[ "$tag" == "latest" ]] || fail "${yml}: tag = '${tag}' (want 'latest')"
done
# Symmetry check — the ipmi-exporter pair must stay in lockstep so they
# resolve to the same upstream version on a given build.
scratch_arg=$(grep -E '^ARG IPMI_EXPORTER_VERSION' "$scratch_df")
slim_arg=$(grep -E '^ARG IPMI_EXPORTER_VERSION' "$slim_df")
[[ "$scratch_arg" == "$slim_arg" ]] \
  || fail "ipmi-exporter scratch + slim Dockerfiles have diverged on IPMI_EXPORTER_VERSION ARG shape"
pass "ipmi-exporter (scratch + slim): ARG empty + image.yaml tag=latest + ARG symmetry"

# --- node-exporter-scratch-trixie: pinned v1.12.1 ---
dockerfile=images/node-exporter-scratch-trixie/Dockerfile
imageyaml=images/node-exporter-scratch-trixie/image.yaml
if ! grep -qE '^ARG NODE_EXPORTER_VERSION=v1\.12\.1$' "$dockerfile"; then
  got=$(grep -E '^ARG NODE_EXPORTER_VERSION=' "$dockerfile" || true)
  fail "${dockerfile}: expected ARG NODE_EXPORTER_VERSION=v1.12.1; got: ${got}"
fi
tag=$(awk '$1 == "tag:" {gsub(/["\x27]/,"",$2); print $2; exit}' "$imageyaml")
[[ "$tag" == "1.12" ]] || fail "${imageyaml}: tag = '${tag}' (want '1.12')"
pass "node-exporter-scratch-trixie: ARG=v1.12.1, image.yaml tag=1.12"

# --- alertmanager-scratch-trixie: DEFERRED at v0.28.1 ---
# Upstream v0.32.0+ needs a Node.js UI build pipeline (ui/web.go embeds
# ui/app/dist/ via //go:embed, which upstream no longer ships in-tree).
# Blocked on FG-048's forge-builder-node-trixie extraction. The Dockerfile
# must stay on v0.28.1 AND carry a comment naming the FG-048 blocker so
# future maintainers understand this isn't just stale — it's parked on
# purpose.
dockerfile=images/alertmanager-scratch-trixie/Dockerfile
imageyaml=images/alertmanager-scratch-trixie/image.yaml
if ! grep -qE '^ARG ALERTMANAGER_VERSION=v0\.28\.1$' "$dockerfile"; then
  got=$(grep -E '^ARG ALERTMANAGER_VERSION=' "$dockerfile" || true)
  fail "${dockerfile}: expected ARG ALERTMANAGER_VERSION=v0.28.1 (bump deferred); got: ${got}"
fi
tag=$(awk '$1 == "tag:" {gsub(/["\x27]/,"",$2); print $2; exit}' "$imageyaml")
[[ "$tag" == "0.28" ]] || fail "${imageyaml}: tag = '${tag}' (want '0.28' — bump deferred)"
if ! grep -qE 'FG-048|forge-builder-node-trixie' "$dockerfile"; then
  fail "${dockerfile} must carry a comment naming the FG-048 / forge-builder-node-trixie blocker"
fi
pass "alertmanager-scratch-trixie: deferred at v0.28.1 with documented FG-048 blocker"

# ---------------------------------------------------------------------------
# §2. PROMISES.yaml version banner strings updated to new upstream versions.
# ---------------------------------------------------------------------------

say "2. PROMISES.yaml version banner matches the bumped pin"

if ! grep -qF 'version 1.12.1' images/node-exporter-scratch-trixie/PROMISES.yaml; then
  fail "node-exporter PROMISES.yaml missing updated version banner 'version 1.12.1'"
fi
pass "node-exporter PROMISES version banner is 1.12.1"

# alertmanager: deferred — PROMISES should still read "version 0.28.1".
if ! grep -qF 'version 0.28.1' images/alertmanager-scratch-trixie/PROMISES.yaml; then
  fail "alertmanager PROMISES.yaml should still read 'version 0.28.1' (bump deferred)"
fi
pass "alertmanager PROMISES version banner is 0.28.1 (deferred)"

# ---------------------------------------------------------------------------
# §3. Each affected image builds + all its smokes pass.
# ---------------------------------------------------------------------------

say "3. Build + per-image smoke suite for the 3 bumped images (alertmanager deferred)"

for img_dir in cadvisor-slim-trixie \
               ipmi-exporter-scratch-trixie \
               ipmi-exporter-slim-trixie \
               node-exporter-scratch-trixie; do
  echo "   → building ${img_dir}"
  bash scripts/build-image.sh "${img_dir}" >/dev/null
  # Resolve the tag we just built against (needed because :latest images
  # have a floating tag; FG-004 publishes them as forge-local/<img>:<tag>).
  tag=$(awk '$1 == "tag:" {gsub(/["\x27]/,"",$2); print $2; exit}' "images/${img_dir}/image.yaml")
  docker image inspect "forge-local/${img_dir}:${tag}" >/dev/null \
    || fail "forge-local/${img_dir}:${tag} did not materialize after build"
  echo "   → running smoke suite for ${img_dir}"
  for s in "images/${img_dir}/tests/"smoke_*.sh; do
    IMAGE_NAME="${img_dir}" IMAGE_TAG="${tag}" bash "${s}" >/dev/null
  done
done
pass "all 4 affected images built + smoked green"

# ---------------------------------------------------------------------------
# §4. Operator-facing v0.34 reason-label split documented in the plan.
# ---------------------------------------------------------------------------

say "4. Alertmanager deferral + FG-048 blocker documented in plan"

plan=docs/plan/FG-050-freshen-upstream-pins-plan.md
if ! grep -qE 'FG-048|forge-builder-node-trixie' "$plan"; then
  fail "${plan}: expected a reference to FG-048 / forge-builder-node-trixie (the UI-pipeline blocker that defers alertmanager v0.35)"
fi
if ! grep -q 'app/dist' "$plan"; then
  fail "${plan}: plan must name the specific build-time failure (ui/web.go embedding app/dist/ that upstream no longer ships)"
fi
# The v0.34 reason-label notes should still exist in the audit section for
# future reference (even though we're not shipping the bump this cycle).
if ! grep -q 'alertmanager_notifications_failed_total' "$plan"; then
  fail "${plan}: expected the audit section to still name alertmanager_notifications_failed_total (future-ref)"
fi
pass "plan doc documents FG-048 blocker + v0.34 audit preserved for future bump"

echo
echo "FG-050 acceptance: all sections passed."
