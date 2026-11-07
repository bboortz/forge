# Forge — top-level Makefile. See memory/workflow.md for the gate matrix.
#
# Primary variables (override via `make <target> VAR=value`):
#   IMAGE_DIR  ?= python-slim-trixie    (directory under images/)
#   REGISTRY   ?= forge-local           (CI overrides to ghcr.io/bboortz)
#
# Repo + tag are resolved from images/<IMAGE_DIR>/image.yaml so callers only
# ever pass IMAGE_DIR. test-images delegates to scripts/test-images.sh which
# does its own yaml resolution.

IMAGE_DIR ?= python-slim-trixie
REGISTRY  ?= forge-local
OUT_DIR   ?= build

# Resolve repo + tag from the image's yaml (only when the dir exists; empty
# otherwise so `make help` etc. stay usable). `repo:` is optional — defaults
# to the image dir name per FG-004. Quoted tag values (e.g. `tag: "3.13"`)
# are stripped by the awk to yield a clean `3.13`.
_IMAGE_YAML := images/$(IMAGE_DIR)/image.yaml
_REPO_EXPLICIT := $(if $(wildcard $(_IMAGE_YAML)),$(shell awk '/^repo:/ {gsub(/["\x27]/,"",$$2); print $$2; exit}' $(_IMAGE_YAML)))
_REPO := $(or $(_REPO_EXPLICIT),$(IMAGE_DIR))
_TAG  := $(if $(wildcard $(_IMAGE_YAML)),$(shell awk '/^tag:/ {gsub(/["\x27]/,"",$$2); print $$2; exit}' $(_IMAGE_YAML)))
IMAGE := $(REGISTRY)/$(_REPO):$(_TAG)
IMAGE_SLUG := $(_REPO)-$(_TAG)

SBOM  := $(OUT_DIR)/$(IMAGE_SLUG).sbom.json
GRYPE := $(OUT_DIR)/$(IMAGE_SLUG).grype.json

COSIGN_DIR := .cosign
COSIGN_KEY := $(COSIGN_DIR)/cosign.key
COSIGN_PUB := $(COSIGN_DIR)/cosign.pub

LOCAL_REGISTRY_PORT ?= 5555
LOCAL_REGISTRY_NAME := forge-local-registry
LOCAL_IMAGE         := localhost:$(LOCAL_REGISTRY_PORT)/$(_REPO):$(_TAG)

ACCEPTANCE_TESTS := $(wildcard tests/acceptance/test_FG_*.sh)

.PHONY: help tools install-hooks lint build scan sign-local verify \
        test-images test-acceptance test-fast check check-strict \
        check-smart check-smart-strict \
        scan-regression scan-baseline-update \
        verify-sid-pins verify-traceability verify-contracts verify-image-dirs clean-local-images \
        _local-registry _local-registry-stop

help:
	@echo "Forge targets:"
	@echo "  tools                install cosign/grype/syft to ~/.local/bin if missing"
	@echo "  install-hooks        register pre-commit + pre-push git hooks locally"
	@echo "  lint                 hadolint / shellcheck / yamllint / actionlint"
	@echo "  verify-sid-pins      enforce CVE + removal condition + date per pin"
	@echo "  verify-traceability  enforce story ↔ plan ↔ test ↔ CAP links"
	@echo "  verify-contracts     enforce image PROMISES ↔ EXPECTATIONS graph (FG-010)"
	@echo "  verify-image-dirs    enforce source + local Dockerfile mutual exclusion (FG-012)"
	@echo "  build                scripts/build-image.sh \$$IMAGE_DIR"
	@echo "  scan                 syft SBOM + grype scan → $(OUT_DIR)/"
	@echo "  sign-local           push $(IMAGE) to localhost:$(LOCAL_REGISTRY_PORT) and cosign-sign"
	@echo "  verify               cosign verify (local key)"
	@echo "  test-images          scripts/test-images.sh [\$$IMAGE_DIR]"
	@echo "  test-acceptance      bash tests/acceptance/test_FG_*.sh"
	@echo "  test-fast            lint + verify-sid-pins + verify-traceability + verify-contracts"
	@echo "  check                test-fast + test-acceptance + test-images"
	@echo "  check-strict         clean-local-images + check (nightly / release gate)"
	@echo "  check-smart          FG-017: scope-aware gate (test-fast + affected images only)"
	@echo "  check-smart-strict   check-smart with per-image wipe (pre-push gate)"
	@echo "  scan-regression      FG-019: new-CRITICAL diff for \$$IMAGE_DIR vs baseline"
	@echo "  scan-baseline-update FG-019: regenerate scan-baseline.json for \$$IMAGE_DIR"
	@echo "  clean-local-images   docker rmi every forge-local/* image"
	@echo ""
	@echo "Variables: IMAGE_DIR=$(IMAGE_DIR) REGISTRY=$(REGISTRY)"
	@echo "Resolved:  IMAGE=$(IMAGE)"

tools:
	@mkdir -p $$HOME/.local/bin
	@command -v syft   >/dev/null || curl -sSfL https://raw.githubusercontent.com/anchore/syft/main/install.sh  | sh -s -- -b $$HOME/.local/bin
	@command -v grype  >/dev/null || curl -sSfL https://raw.githubusercontent.com/anchore/grype/main/install.sh | sh -s -- -b $$HOME/.local/bin
	@command -v cosign >/dev/null || { curl -sSfL -o $$HOME/.local/bin/cosign https://github.com/sigstore/cosign/releases/download/v2.4.3/cosign-linux-amd64 && chmod +x $$HOME/.local/bin/cosign; }
	@command -v pre-commit >/dev/null || { echo "  pre-commit missing — install with: pipx install pre-commit"; false; }
	@for t in hadolint shellcheck yamllint actionlint jq; do \
	  command -v $$t >/dev/null || echo "  $$t missing (install via your package manager)"; \
	done

install-hooks:
	@command -v pre-commit >/dev/null || { echo "pre-commit missing — install with: pipx install pre-commit"; exit 1; }
	pre-commit install
	pre-commit install --hook-type pre-push

lint:
	@# FG-017 C: lint inputs resolved via `git ls-files` so pre-push sees
	@# exactly what CI sees after push. Protects against the "untracked
	@# working-tree file masks a CI failure" class of bug (homelab lesson).
	@echo "→ hadolint"
	@git ls-files 'images/*/Dockerfile' | xargs -r hadolint
	@echo "→ shellcheck"
	@git ls-files 'tests/acceptance/*.sh' 'images/*/tests/*.sh' 'scripts/*.sh' | xargs -r shellcheck
	@echo "→ yamllint"
	@git ls-files '.github/*.yaml' '.github/**/*.yaml' '.github/*.yml' '.github/**/*.yml' 'images/*/image.yaml' 'images/*/PROMISES.yaml' 'images/*/EXPECTATIONS.yaml' \
	  | xargs -r yamllint -d "{extends: default, rules: {line-length: disable, document-start: disable, truthy: {check-keys: false}}}"
	@if command -v actionlint >/dev/null; then echo "→ actionlint"; git ls-files '.github/workflows/*.yml' | xargs -r actionlint; else echo "  actionlint missing — skipping"; fi
	@echo "→ exec-bit check"
	@# FG-017 C: every git-tracked .sh must be +x so shellcheck doesn't silently skip it.
	@failed=0; for f in $$(git ls-files '*.sh'); do \
	  if [ ! -x "$$f" ]; then echo "  ✗ $$f missing exec bit (chmod +x it)" >&2; failed=1; fi; \
	done; [ "$$failed" -eq 0 ]

verify-sid-pins:
	@bash scripts/verify-sid-pins.sh

verify-traceability:
	@bash scripts/verify-traceability.sh

verify-contracts:
	@python3 scripts/verify-contracts.py

verify-image-dirs:
	@bash scripts/verify-image-dirs.sh

# FG-019: scan-regression gate. Diffs grype CRITICAL findings for IMAGE_DIR
# vs the committed images/$(IMAGE_DIR)/scan-baseline.json, subtracting any
# waivers listed in PROMISES.yaml's absence.os-cves entry. Also invoked
# per-image by scripts/smart-check.sh's scoped loop.
scan-regression:
	@python3 scripts/scan-regression.py "$(IMAGE_DIR)"

# FG-019: regenerate the baseline from the current build's grype scan.
# Devs run this when intentionally accepting a baseline change.
scan-baseline-update: build
	@python3 scripts/scan-baseline-update.py "$(IMAGE_DIR)"

build:
	@bash scripts/build-image.sh "$(IMAGE_DIR)"

scan: build
	@mkdir -p $(OUT_DIR)
	@echo "→ syft $(IMAGE) → $(SBOM)"
	@syft "$(IMAGE)" -o cyclonedx-json="$(SBOM)"
	@echo "→ grype $(IMAGE) → $(GRYPE)"
	@grype "$(IMAGE)" -o json > "$(GRYPE)" || true

_local-registry:
	@docker container inspect $(LOCAL_REGISTRY_NAME) >/dev/null 2>&1 || \
	  docker run -d --rm --name $(LOCAL_REGISTRY_NAME) -p $(LOCAL_REGISTRY_PORT):5000 registry:2 >/dev/null

_local-registry-stop:
	@docker rm -f $(LOCAL_REGISTRY_NAME) >/dev/null 2>&1 || true

$(COSIGN_KEY):
	@mkdir -p $(COSIGN_DIR)
	@echo "→ generating local cosign key pair under $(COSIGN_DIR)/"
	@cd $(COSIGN_DIR) && COSIGN_PASSWORD="" cosign generate-key-pair

sign-local: build _local-registry $(COSIGN_KEY)
	@docker tag $(IMAGE) $(LOCAL_IMAGE)
	@docker push $(LOCAL_IMAGE) >/dev/null
	@echo "→ cosign sign $(LOCAL_IMAGE)"
	@COSIGN_PASSWORD="" cosign sign --yes --key $(COSIGN_KEY) --tlog-upload=false --allow-insecure-registry $(LOCAL_IMAGE) >/dev/null

verify: $(COSIGN_PUB) _local-registry
	@echo "→ cosign verify $(LOCAL_IMAGE)"
	@COSIGN_PASSWORD="" cosign verify --key $(COSIGN_PUB) --insecure-ignore-tlog --allow-insecure-registry $(LOCAL_IMAGE) >/dev/null

test-acceptance:
	@for t in $(ACCEPTANCE_TESTS); do \
	  echo "→ $$t"; \
	  _FORGE_IN_CHECK=1 bash $$t || exit 1; \
	done

test-images:
	@bash scripts/test-images.sh

test-fast: lint verify-sid-pins verify-traceability verify-contracts verify-image-dirs

check: test-fast test-acceptance test-images

# check-strict wipes forge-local/* before running make check so stale image
# references in tests can't hide behind a workstation-cached image. Used by
# nightly cron + release workflow. Pre-push uses check-smart-strict (FG-017).
clean-local-images:
	@bash scripts/clean-local-images.sh

check-strict: clean-local-images check

# FG-017: scope-aware gate. Runs test-fast (full-repo lint) + builds + smokes
# + acceptance only for images affected by the current diff vs origin/dev.
# Bails out to check-strict on structural changes (scripts/, scratch-base,
# >4 images). See scripts/smart-check.sh.
check-smart:
	@bash scripts/smart-check.sh

# check-smart with per-affected-image docker wipe. Used by pre-push hook;
# nightly cron still runs check-strict from cold as the safety net.
check-smart-strict:
	@bash scripts/smart-check.sh
