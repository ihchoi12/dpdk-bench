# Makefile (repo root)
SHELL := /bin/bash

ROOT_PATH        := .
BUILD_DIR        ?= $(ROOT_PATH)/build
DPDK_DIR ?= dpdk

.PHONY: submodules submodules-clean l3fwd
.DEFAULT_GOAL := submodules

submodules:
	@bash $(BUILD_DIR)/init_submodules.sh build

submodules-clean:
	@bash $(BUILD_DIR)/init_submodules.sh clean

# Convenience target to only (re)build l3fwd after dpdk is set up
l3fwd:
	@bash -euo pipefail -c '\
	  test -d dpdk/build || { echo "DPDK is not built. Run: make submodules"; exit 1; } ;\
	  ninja -C dpdk/build examples/dpdk-l3fwd \
	'

dpdk-version:
	@echo ">> checking submodule dir:"
	@test -d "$(DPDK_DIR)" || { echo "ERROR: DPDK_DIR not found: $(DPDK_DIR)"; exit 1; }
	@echo ">> pinned gitlink:"
	@git ls-tree HEAD "$(DPDK_DIR)"
	@echo ">> submodule status:"
	@git submodule status "$(DPDK_DIR)" || true
	@echo ">> current checkout SHA:"
	@git -C "$(DPDK_DIR)" rev-parse HEAD || true
	@echo ">> exact tag (if any):"
	-@git -C "$(DPDK_DIR)" describe --tags --exact-match || true


.PHONY: run-l3fwd
run-l3fwd:
	@./scripts/run-l3fwd.sh

.PHONY: dpdk-patch-all
dpdk-patch-all:
	@bash -euo pipefail -c '\
	  test -d dpdk || { echo "dpdk submodule missing"; exit 1; }; \
	  cd dpdk; \
	  git add -N $$(git ls-files -o --exclude-standard) >/dev/null 2>&1 || true; \
	  git diff > ../build/dpdk.patch; \
	  echo "Wrote build/dpdk.patch" \
	'