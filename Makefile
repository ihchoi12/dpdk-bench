# Makefile (repo root)
SHELL := /bin/bash

ROOT_PATH        := .
BUILD_DIR        ?= $(ROOT_PATH)/build
DPDK_DIR ?= dpdk

.PHONY: submodules submodules-debug submodules-clean l3fwd
.DEFAULT_GOAL := submodules

submodules:
	@bash $(BUILD_DIR)/init_submodules.sh build

submodules-debug:
	@echo ">> Building submodules with TX/RX debug enabled..."
	@RTE_LIBRTE_ETHDEV_DEBUG=1 bash $(BUILD_DIR)/init_submodules.sh build

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

PHONY: l3fwd l3fwd-rebuild l3fwd-clean run-l3fwd run-l3fwd-timed benchmark-l3fwd-multi-core build-pcm

build-pcm:
	@echo ">> Building PCM static library..."
	@cd pcm && mkdir -p build && cd build && cmake .. && make -j$(shell nproc)
	@echo ">> PCM build completed"

common-pcm: build-pcm
	@echo ">> Building common PCM wrapper library..."
	@cd common/pcm && make clean && make install
	@echo ">> Common PCM library built and installed to lib/"

l3fwd: common-pcm
	@bash build/init_submodules.sh l3fwd

l3fwd-rebuild:
	cd dpdk && ninja -C build examples/dpdk-l3fwd

l3fwd-clean:
	@rm -f dpdk/build/examples/dpdk-l3fwd

run-l3fwd:
	@./scripts/run-l3fwd.sh

run-l3fwd-timed:
	@./scripts/run-l3fwd-timed.sh

benchmark-l3fwd-multi-core:
	@./scripts/benchmark-l3fwd-multi-core.sh

benchmark-l3fwd-vs-pktgen:
	@./scripts/benchmark-l3fwd-vs-pktgen.sh


.PHONY: pktgen pktgen-rebuild pktgen-clean run-pktgen

pktgen:
	@bash build/init_submodules.sh pktgen

pktgen-rebuild:
	cd Pktgen-DPDK && ninja -C build

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


# ========================================================================
# DEPRECATED: Patch-based workflow
# ========================================================================
# These targets are deprecated. We now use fork-based workflow:
# - Changes are committed directly to the autokernel branch in forks
# - No need for patch files - use git commit and git push instead
# ========================================================================

.PHONY: dpdk-patch-all
dpdk-patch-all:
	@echo "WARNING: dpdk-patch-all is DEPRECATED"
	@echo "Using fork-based workflow now - commit changes directly:"
	@echo "  cd dpdk"
	@echo "  git add <files>"
	@echo "  git commit -m 'your message'"
	@echo "  git push fork autokernel"

.PHONY: pktgen-patch-all
pktgen-patch-all:
	@echo "WARNING: pktgen-patch-all is DEPRECATED"
	@echo "Using fork-based workflow now - commit changes directly:"
	@echo "  cd Pktgen-DPDK"
	@echo "  git add <files>"
	@echo "  git commit -m 'your message'"
	@echo "  git push fork autokernel"

.PHONY: patch-all
patch-all:
	@echo "WARNING: patch-all is DEPRECATED"
	@echo "Using fork-based workflow now - commit changes to both repos"
	@echo "See dpdk-patch-all and pktgen-patch-all for details"
