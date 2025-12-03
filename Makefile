# Makefile
SHELL := /bin/bash

ROOT_PATH := .
SCRIPTS_DIR := $(ROOT_PATH)/scripts

.PHONY: all build build-all build-debug clean clean-all
.DEFAULT_GOAL := all

all: build

# ========================================================================
# Build targets
# ========================================================================

# Full build: PCM + DPDK + Pktgen (for new machines or profiling tool updates)
build-all:
	@bash $(SCRIPTS_DIR)/build/init_submodules.sh build-all

# Full build with debug: PCM + DPDK + Pktgen with TX/RX debug logging
build-all-debug:
	@echo ">> Full build with TX/RX debug enabled..."
	@RTE_LIBRTE_ETHDEV_DEBUG=1 bash $(SCRIPTS_DIR)/build/init_submodules.sh build-all

# DPDK + Pktgen clean rebuild (skips PCM if already built)
build:
	@bash $(SCRIPTS_DIR)/build/init_submodules.sh build

# DPDK + Pktgen with debug logging
build-debug:
	@echo ">> Building with TX/RX debug enabled..."
	@RTE_LIBRTE_ETHDEV_DEBUG=1 bash $(SCRIPTS_DIR)/build/init_submodules.sh build

# Legacy aliases
submodules: build
submodules-debug: build-debug

# Clean DPDK + Pktgen only (preserves PCM)
clean:
	@bash $(SCRIPTS_DIR)/build/init_submodules.sh clean

# Clean everything including PCM
clean-all:
	@bash $(SCRIPTS_DIR)/build/init_submodules.sh clean-all

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
# System Configuration
# ========================================================================

.PHONY: get-system-info

get-system-info:
	@echo ">> Detecting and updating system configuration..."
	@./scripts/utils/get_system_info.sh

# ========================================================================
# Run targets
# ========================================================================

.PHONY: run-simple-pktgen-test run-full-benchmark monitor-ddio-perf

run-simple-pktgen-test:
	@mkdir -p results
	@echo ">> Running simple pktgen test (logging to results/simple-pktgen-test.log)..."
	@./scripts/benchmark/run-simple-pktgen-test.sh 2>&1 | tee results/simple-pktgen-test.log

run-full-benchmark:
	@mkdir -p results
	@echo ">> Running full benchmark (see test_config.py for parameters)..."
	@cd scripts/benchmark && python3 run_test.py

monitor-ddio-perf:
	@echo ">> Starting DDIO monitoring with perf..."
	@sudo ./scripts/utils/monitor-ddio-perf.sh
