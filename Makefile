# Makefile
SHELL := /bin/bash

ROOT_PATH := .
BUILD_DIR := $(ROOT_PATH)/build

.PHONY: all submodules submodules-debug clean
.DEFAULT_GOAL := all

all: submodules

# ========================================================================
# Build targets
# ========================================================================

submodules:
	@bash $(BUILD_DIR)/init_submodules.sh build

submodules-debug:
	@echo ">> Building with TX/RX debug enabled..."
	@RTE_LIBRTE_ETHDEV_DEBUG=1 bash $(BUILD_DIR)/init_submodules.sh build

clean:
	@bash $(BUILD_DIR)/init_submodules.sh clean

# ========================================================================
# Rebuild targets (for incremental development)
# ========================================================================

.PHONY: l3fwd-rebuild pktgen-rebuild

l3fwd-rebuild:
	@echo ">> Rebuilding L3FWD..."
	@cd dpdk && ninja -C build examples/dpdk-l3fwd

pktgen-rebuild:
	@echo ">> Rebuilding Pktgen..."
	@cd Pktgen-DPDK && ninja -C build

# ========================================================================
# Run targets
# ========================================================================

.PHONY: run-pktgen-with-lua-script

run-pktgen-with-lua-script:
	@./scripts/run-pktgen-with-lua-script.sh
