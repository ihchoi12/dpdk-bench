# Makefile
SHELL := /bin/bash

ROOT_PATH := .
SCRIPTS_DIR := $(ROOT_PATH)/scripts

.PHONY: all submodules submodules-debug clean
.DEFAULT_GOAL := all

all: submodules

# ========================================================================
# Build targets
# ========================================================================

submodules:
	@bash $(SCRIPTS_DIR)/init_submodules.sh build

submodules-debug:
	@echo ">> Building with TX/RX debug enabled..."
	@RTE_LIBRTE_ETHDEV_DEBUG=1 bash $(SCRIPTS_DIR)/init_submodules.sh build

submodules-ak:
	@echo ">> Building with AK queue depth tracking enabled..."
	@AK_ENABLE_QUEUE_DEPTH_TRACKING=1 bash $(SCRIPTS_DIR)/init_submodules.sh build

clean:
	@bash $(SCRIPTS_DIR)/init_submodules.sh clean

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

.PHONY: run-pktgen-with-lua-script monitor-ddio-perf

run-pktgen-with-lua-script:
	@./scripts/run-pktgen-with-lua-script.sh

monitor-ddio-perf:
	@echo ">> Starting DDIO monitoring with perf..."
	@sudo ./scripts/monitor-ddio-perf.sh
