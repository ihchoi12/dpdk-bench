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

PHONY: l3fwd l3fwd-clean run-l3fwd run-l3fwd-timed benchmark-l3fwd-multi-core

l3fwd:
	@bash build/init_submodules.sh l3fwd

l3fwd-clean:
	@rm -f dpdk/build/examples/dpdk-l3fwd

run-l3fwd:
	@./scripts/run-l3fwd.sh

run-l3fwd-timed:
	@./scripts/run-l3fwd-timed.sh

benchmark-l3fwd-multi-core:
	@./scripts/benchmark-l3fwd-multi-core.sh


.PHONY: pktgen pktgen-clean run-pktgen

pktgen:
	@bash build/init_submodules.sh pktgen

pktgen-clean:
	@bash build/init_submodules.sh pktgen-clean

run-pktgen:
	@./scripts/run-pktgen.sh

run-pktgen-with-lua-script:
	@./scripts/run-pktgen-with-lua-script.sh

benchmark-multi-core-tx-rate:
	@./scripts/benchmark-multi-core-tx-rate.sh

benchmark-combined:
	@./scripts/benchmark-multi-core-tx-rate.sh combined

benchmark-split:
	@./scripts/benchmark-multi-core-tx-rate.sh split

compare-port-mappings:
	@./scripts/compare-port-mappings.sh

generate-performance-graph:
	@python3 scripts/generate_performance_graph.py


.PHONY: dpdk-patch-all
dpdk-patch-all:
	@bash -euo pipefail -c '\
	  test -d dpdk || { echo "dpdk submodule missing"; exit 1; }; \
	  cd dpdk; \
	  git add -N $$(git ls-files -o --exclude-standard) >/dev/null 2>&1 || true; \
	  git diff > ../build/dpdk.patch; \
	  echo "Wrote build/dpdk.patch" \
	'

.PHONY: pktgen-patch-all
pktgen-patch-all:
	@bash -euo pipefail -c '\
	  test -d Pktgen-DPDK || { echo "pktgen submodule missing"; exit 1; }; \
	  cd Pktgen-DPDK; \
	  git add -N $$(git ls-files -o --exclude-standard) >/dev/null 2>&1 || true; \
	  git diff > ../build/pktgen.patch; \
	  echo "Wrote build/pktgen.patch" \
	'

.PHONY: patch-all
patch-all: dpdk-patch-all pktgen-patch-all
