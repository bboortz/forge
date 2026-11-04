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
