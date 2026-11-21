#!/usr/bin/env bash
#
# Covers: FG-051
# CAPs:   build.ubuntu-base-noble, image.github-runner-noble-pre-baked,
#         build.ref-latest-release, image.has-shell,
#         scan.regression-gate, test.size-budget

set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

say()  { printf '\n\033[1;36m[FG-051]\033[0m %s\n' "$*"; }
pass() { printf '  \033[32m✓\033[0m %s\n' "$*"; }
fail() { printf '  \033[31m✗\033[0m %s\n' "$*" >&2; exit 1; }

# -----------------------------------------------------------------------------
# §1. ubuntu-slim-noble layout + build
# -----------------------------------------------------------------------------

say "1. images/pre-builder/ubuntu-slim-noble/ has required layout"
for f in Dockerfile image.yaml PROMISES.yaml \
         tests/smoke_os_release.sh \
         tests/smoke_ca_bundle.sh \
         tests/smoke_libicu74_installed.sh; do
  test -e "images/pre-builder/ubuntu-slim-noble/${f}" \
    || fail "images/pre-builder/ubuntu-slim-noble/${f} missing"
done
pass "all required files present"

say "2. ubuntu-slim-noble:24.04 builds from upstream ubuntu:24.04"
grep -qE '^FROM ubuntu:24\.04' images/pre-builder/ubuntu-slim-noble/Dockerfile \
  || fail "images/pre-builder/ubuntu-slim-noble/Dockerfile must FROM ubuntu:24.04 literal (FG-042 grep-invariant)"
bash scripts/build-image.sh pre-builder/ubuntu-slim-noble >/dev/null
docker image inspect forge-local/pre-builder/ubuntu-slim-noble:24.04 >/dev/null \
  || fail "forge-local/pre-builder/ubuntu-slim-noble:24.04 did not materialize"
pass "forge-local/pre-builder/ubuntu-slim-noble:24.04 built"

say "3. ubuntu-slim-noble smoke suite"
for s in images/pre-builder/ubuntu-slim-noble/tests/smoke_*.sh; do
  IMAGE_TAG=24.04 bash "${s}" >/dev/null
done
pass "all ubuntu-slim-noble smokes green"

# -----------------------------------------------------------------------------
# §4. github-runner-noble layout + build
# -----------------------------------------------------------------------------

say "4. images/github-runner-noble/ has required layout"
for f in Dockerfile image.yaml PROMISES.yaml entrypoint.sh \
         requirements-dev.txt ansible-requirements.yml \
         tests/smoke_runner_version.sh \
         tests/smoke_tools_present.sh \
         tests/smoke_ansible_collections.sh \
         tests/smoke_entrypoint_env_validation.sh; do
  test -e "images/github-runner-noble/${f}" \
    || fail "images/github-runner-noble/${f} missing"
done
test -x images/github-runner-noble/entrypoint.sh \
  || fail "images/github-runner-noble/entrypoint.sh must be executable"
pass "all required files present"

say "5. github-runner-noble Dockerfile uses forge-rooted UBUNTU_SLIM_NOBLE_REF + FG-050 latest-resolve"
dockerfile=images/github-runner-noble/Dockerfile
grep -qE 'FROM \$\{(UBUNTU_SLIM_NOBLE_REF|BASE_UBUNTU_SLIM_NOBLE_REF)\}' "$dockerfile" \
  || fail "Dockerfile must FROM \${UBUNTU_SLIM_NOBLE_REF} or FG-077 \${BASE_UBUNTU_SLIM_NOBLE_REF}"
grep -qE '^ARG RUNNER_VERSION=\s*$' "$dockerfile" \
  || fail "Dockerfile must have empty-default RUNNER_VERSION (FG-050 build.ref-latest-release pattern)"
grep -q 'api.github.com/repos/actions/runner/releases/latest' "$dockerfile" \
  || fail "Dockerfile must resolve runner version via GitHub Releases API"
pass "dual-ARG + resolve shape correct"

say "6. github-runner-noble builds via ubuntu-slim-noble base"
bash scripts/build-image.sh github-runner-noble >/dev/null
docker image inspect forge-local/github-runner-noble:latest >/dev/null \
  || fail "forge-local/github-runner-noble:latest did not materialize"
pass "forge-local/github-runner-noble:latest built"

say "7. github-runner-noble smoke suite"
for s in images/github-runner-noble/tests/smoke_*.sh; do
  IMAGE_TAG=latest bash "${s}" >/dev/null
done
pass "all github-runner-noble smokes green"

# -----------------------------------------------------------------------------
# §8. FG-042 upstream-single-consumer invariant: ubuntu:24.04 consumed by
#     exactly ONE Dockerfile (ubuntu-slim-noble).
# -----------------------------------------------------------------------------

say "8. upstream-single-consumer: ubuntu:24.04 FROMs exactly 1 Dockerfile"
hits=$(grep -lE "^FROM ubuntu:24\.04" images/*/Dockerfile images/*/*/Dockerfile 2>/dev/null | wc -l)
[[ "${hits}" -eq 1 ]] \
  || fail "expected 1 Dockerfile FROMing ubuntu:24.04 (the ubuntu-slim-noble pre-builder), got ${hits}"
pass "ubuntu:24.04 consumed by exactly 1 forge pre-builder (ubuntu-slim-noble)"

say "9. image.yaml invariants"
tag=$(awk '$1 == "tag:" {gsub(/["\x27]/,"",$2); print $2; exit}' images/pre-builder/ubuntu-slim-noble/image.yaml)
[[ "$tag" == "24.04" ]] || fail "ubuntu-slim-noble image.yaml tag = '$tag' (want '24.04')"
tag=$(awk '$1 == "tag:" {gsub(/["\x27]/,"",$2); print $2; exit}' images/github-runner-noble/image.yaml)
[[ "$tag" == "latest" ]] || fail "github-runner-noble image.yaml tag = '$tag' (want 'latest')"
pass "image.yaml tags correct"

echo
echo "FG-051 acceptance: all sections passed."
