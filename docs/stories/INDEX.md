# Stories — status board

One line per story. Keep in ID order. Status mirrors each story's frontmatter.

| ID | Slug | Status | One-liner |
|----|------|--------|-----------|
| FG-001 | [python-slim-pipeline](FG-001-python-slim-pipeline.md) | shipped | Full publish pipeline for `python:3.13-slim-trixie` (no scratch, no sid pin, amd64-only) |
| FG-002 | [python-image-smoke-suite](FG-002-python-image-smoke-suite.md) | shipped | Per-image smoke test convention (`images/<name>/tests/`) + 6 python smoke scripts + `make test-images` target |
| FG-003 | [python-scratch-runtime](FG-003-python-scratch-runtime.md) | shipped | `FROM scratch` python variant (44.45 MB, zero OS CVEs) + central build/test scripts + GHA matrix auto-discovery; retains slim variant |
| FG-004 | [per-variant-ghcr-repos](FG-004-per-variant-ghcr-repos.md) | shipped | One GHCR repo per variant (`python-slim-trixie`, `python-scratch-trixie`) + 4-tag family per publish (`:3.13`, `:3.13-amd64`, `:latest`, `:latest-amd64`); hard cut on old `python` repo |
| FG-006 | [nginx-scratch-trixie](FG-006-nginx-scratch-trixie.md) | shipped | Second scratch image: nginx 1.26 FROM scratch (15.34 MB, zero OS CVEs); introduces reusable `scripts/smoke-server.sh` helper |
| FG-007 | [postgres-scratch-trixie](FG-007-postgres-scratch-trixie.md) | shipped | Third scratch image: PostgreSQL 17.11 FROM scratch (104 MB, zero OS CVEs, no LLVM JIT); introduces sidecar-init pattern for shell-requiring workflows |
| FG-005 | [scratch-base-trixie](FG-005-scratch-base-trixie.md) | shipped | Shared signed baseline (13.14 MB) for every Forge scratch image; strict intersection of python/nginx/postgres closures; refactors all three derivatives to compose via COPY --from=scratch_base |
| FG-008 | [baseline-standard](FG-008-baseline-standard.md) | shipped | scratch-base-trixie 0.1 → 0.2: adds nonroot (65532) + network data (/etc/services + /etc/protocols + /etc/hosts) + /etc/localtime + /var/tmp; publishes docs/baseline-contract.md |
| FG-009 | [python-scratch-hardening](FG-009-python-scratch-hardening.md) | shipped | python-scratch hardening per Beaconry feedback: fixes HTTPS (re-declare SSL_CERT_FILE in every scratch derivative), adds USER 65532 + ENTRYPOINT=python3 + PYTHONDONTWRITEBYTECODE + PYTHONFAULTHANDLER; closes the ENV-doesn't-propagate trap |
| FG-010 | [image-contracts](FG-010-image-contracts.md) | shipped | Image-to-image contracts: PROMISES.yaml per image + EXPECTATIONS.yaml per scratch derivative + `make verify-contracts` gate + `contracts-semver-check.py` pre-commit hook; catches FG-009-class silent regressions at PR time |
| FG-011 | [librt-manylinux-compat](FG-011-librt-manylinux-compat.md) | shipped | Add librt.so.1 ABI stub (14.5 KB, empty since glibc 2.34) to python-scratch so manylinux2014 / manylinux_2_17 wheels (numpy, scipy, pandas, pillow, cryptography) dlopen successfully; Beaconry-flagged |
| FG-012 | [external-sourced-images](FG-012-external-sourced-images.md) | shipped | Externally-sourced images via `source:` block in image.yaml (git + ref + dockerfile + context); first consumer is `beaconry-scout` pinned to bboortz/beaconry@665370e; mechanism supports hub + future external images |
