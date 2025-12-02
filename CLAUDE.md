# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Git Commit Policy

**IMPORTANT**: When creating git commits in this repository:
- **Author**: Only `ihchoi12` should appear as the commit author
- **Co-Author**: Do NOT include Claude as Co-Authored-By
- **Commit message format**: Simple, clear description without AI attribution
- **Examples**:
  ```
  # ✓ CORRECT
  git commit -m "Add PCM disable functionality via DISABLE_PCM env var"

  # ✗ INCORRECT - Do not include:
  git commit -m "Add feature

  Co-Authored-By: Claude <noreply@anthropic.com>"
  ```

This ensures all commits appear as authored solely by ihchoi12.

## Overview

This is a DPDK (Data Plane Development Kit) benchmarking suite that tests network packet processing performance using two key applications:
- **L3FWD**: Layer 3 forwarding application (runs on node8)
- **Pktgen-DPDK**: Packet generator/receiver (runs on node7)

The benchmark suite measures packet throughput (Mpps), RX/TX rates, hardware performance counters (via Intel PCM), and various DPDK tuning parameters across a two-node cluster connected via Mellanox MLX5 NICs.

## Architecture

### Multi-Node Cluster Setup
- **node7**: Packet generator (Pktgen-DPDK)
- **node8**: L3FWD receiver/forwarder (default)
- Communication: Direct 10GbE connection between nodes
- Remote execution: Uses `pyrem` library for SSH-based multi-node orchestration

### Key Components

1. **DPDK Submodule** (`dpdk/`): Core DPDK library with custom modifications
   - Modified MLX5 driver with debug logging
   - Custom logging via `ak_debug_log.h` for TX completion queue tracking
   - L3FWD application built as example
   - Managed on `autokernel` branch

2. **Pktgen-DPDK Submodule** (`Pktgen-DPDK/`): Packet generator
   - Custom modifications for benchmarking
   - Lua scripting support for automated test sequences
   - Test scripts in `scripts/` directory
   - Managed on `autokernel` branch

3. **Intel PCM Submodule** (`pcm/`): Performance counter monitoring
   - Integrated into L3FWD for hardware performance metrics
   - Tracks: L2/L3 cache hits, DRAM bandwidth, PCIe bandwidth

4. **Test Orchestration** (`run_test.py`, `test_config.py`):
   - Python-based test runner using `pyrem` for remote execution
   - Configurable test parameters: core counts, descriptor sizes, packet sizes
   - Automated result parsing and CSV generation

### Configuration System

- **`pktgen.config`**: Central configuration file for DPDK parameters
  - PCI addresses, core mappings, memory channels
  - Port mappings for RX/TX core allocation
- **`test_config.py`**: Python test configuration
  - Cluster node assignments (NODE7_IP, NODE8_IP, etc.)
  - Test ranges (core counts, descriptor sizes)
  - Helper functions: `get_l3fwd_config()`, `get_pktgen_config()`

## Build System

### Initial Setup
```bash
# Install dependencies and setup machines
sudo apt update && sudo apt install -y \
  meson ninja-build build-essential pkg-config git \
  libnuma-dev libpcap-dev python3-pyelftools liblua5.3-dev \
  libibverbs-dev librdmacm-dev rdma-core ibverbs-providers libmlx5-1 \
  libelf-dev libbsd-dev zlib1g-dev cmake
sudo ./setup_machines

# Initialize and build all submodules (DPDK, Pktgen, PCM)
make submodules
```

### Build Targets
- `make submodules`: Full build of DPDK + Pktgen + examples
- `make submodules-debug`: Build with TX/RX debug logging enabled (sets `RTE_LIBRTE_ETHDEV_DEBUG=1`)
- `make l3fwd`: Rebuild only L3FWD (faster iteration)
- `make pktgen`: Rebuild only Pktgen
- `make build-pcm`: Build Intel PCM library

### Build Script (`scripts/build/init_submodules.sh`)
- Handles submodule initialization and compilation
- Manages meson/ninja build configuration
- Sets up PKG_CONFIG_PATH and LD_LIBRARY_PATH
- Submodule changes are managed directly via git on `autokernel` branch

## Running Benchmarks

### Basic Operations
```bash
# Run pktgen (interactive mode)
make run-pktgen

# Run pktgen with automated Lua script
make run-pktgen-with-lua-script

# Run L3FWD on node8
make run-l3fwd

# Run L3FWD for timed duration (auto-terminates)
make run-l3fwd-timed
```

### Automated Benchmarks
Use `run_test.py` for comprehensive automated benchmarking:

```bash
# Run full benchmark suite with multiple configurations
python3 run_test.py

# Configuration in test_config.py:
# - Core counts: L3FWD_LCORE_VALUES, PKTGEN_LCORE_VALUES
# - Descriptor sizes: L3FWD_TX_DESC_VALUES, L3FWD_RX_DESC_VALUES
# - Packet sizes: PKTGEN_PACKET_SIZE
# - Port mappings: get_pktgen_config() generates RX/TX core mappings
```

### Simple Lua-based Tests
```bash
# Quick functional test with Lua script
make run-pktgen-with-lua-script

# Manual test with specific parameters
PKTGEN_DURATION=10 PKTGEN_PACKET_SIZE=64 make run-pktgen-with-lua-script
```

## Test Parameters

### Tunable Parameters (in `test_config.py`)
- **TX/RX Descriptor Ring Sizes**: `L3FWD_TX_DESC_VALUES`, `L3FWD_RX_DESC_VALUES`, `PKTGEN_TX_DESC_VALUES`
  - Smaller: Lower memory, higher cache efficiency, more packet drops
  - Larger: Better burst handling, higher memory usage, increased latency
- **Core Counts**: `L3FWD_LCORE_VALUES`, `PKTGEN_LCORE_VALUES`
- **Packet Size**: `PKTGEN_PACKET_SIZE` (typically 64 bytes for max pps)

### Hardware Performance Metrics
The benchmark suite collects:
- **Packet Stats**: RX/TX rates (Mpps), packet loss, hardware RX missed errors
- **CPU Cache**: L2/L3 cache hit rates, L3 misses
- **Memory**: DRAM read/write bandwidth (MB/s)
- **PCIe**: PCIe read/write bandwidth (MB/s)

## Results and Analysis

### Output Files
- Results saved to `results/` directory with timestamp
- Format: `YYMMDD-HHMMSS-<test-type>.txt`
- Python runner generates: `results/dpdk_benchmark_results.txt` (CSV format)

### Result Format (CSV)
Headers include: experiment_id, pkt_size, descriptor values, core counts, RX/TX rates, failure counts, hardware counters (L3 misses, DRAM BW, PCIe BW)

### Parsing and Visualization
- `run_test.py`: Main test orchestrator with result parsing (`parse_dpdk_results()`)
- `scripts/generate_performance_graph.py`: Generate PNG bar charts
- `make generate-performance-graph`: Create performance comparison graphs

## Important Implementation Details

### Custom DPDK Patches
- **MLX5 TX Debug Logging**: Tracks completion queue handling, doorbell operations
  - Added in `drivers/net/mlx5/mlx5_tx.c` and `mlx5_tx.h`
  - Uses `AK_DEBUG_LOG_LINE()` macro from `ak_debug_log.h`
- **Purpose**: Debug TX descriptor exhaustion and completion queue behavior

### Remote Execution Pattern
Scripts use SSH to run L3FWD on node8 while controlling Pktgen on node7:
```python
# In run_test.py
node8 = pyrem.host.RemoteHost('node8')
task = node8.run(cmd, quiet=False)
pyrem.task.Parallel([task], aggregate=True).start(wait=True)
```

### Process Lifecycle Management
- `kill_procs()`: Cleanup function to terminate DPDK processes
- Cleanup on EXIT/INT/TERM signals
- Clear DPDK shared memory: `/var/run/dpdk/rte/config`

### ARP Table Setup
- Required before each test: `setup_arp_tables()`
- Loads static ARP entries from `scripts/arp_table`
- Ensures packet forwarding works between nodes

## Common Development Workflows

### Modifying DPDK Code
```bash
# 1. Make changes in dpdk/ subdirectory
vim dpdk/drivers/net/mlx5/mlx5_tx.c

# 2. Rebuild L3FWD only (fast iteration)
make l3fwd-rebuild

# 3. If build fails, do full L3FWD rebuild
make l3fwd-clean && make l3fwd

# 4. Commit changes to submodule
cd dpdk
git add -u
git commit -m "Description of changes"
git push origin autokernel
cd ..
```

### Modifying Pktgen Code
```bash
# 1. Make changes in Pktgen-DPDK/
vim Pktgen-DPDK/app/pktgen-main.c

# 2. Rebuild pktgen
make pktgen-rebuild

# 3. Commit changes to submodule
cd Pktgen-DPDK
git add -u
git commit -m "Description of changes"
git push origin autokernel
cd ..
```

### Adding New Test Scenarios
1. Modify `test_config.py` to add new parameter ranges
2. Update `run_test.py` `run_eval()` loop structure if needed
3. Ensure result parsing handles new metrics in `parse_dpdk_results()`

### Debugging TX/RX Issues
```bash
# Build with debug logging
make submodules-debug

# Run test and check logs
make run-l3fwd-timed
tail -f results/*.l3fwd  # View debug output
```

## Configuration Files Location

- `/homes/inho/Autokernel/dpdk-bench/` - Repository root
- Node-specific paths are absolute in configuration (required for remote execution)
- DPDK binaries: `dpdk/build/examples/dpdk-l3fwd`
- Pktgen binary: `Pktgen-DPDK/build/app/pktgen`

## DPDK-Specific Considerations

### Memory and Hugepages
- DPDK requires hugepages configured on both nodes
- Setup handled by `./setup_machines` script

### NIC Configuration
- Mellanox ConnectX-5 (MLX5) NICs on both nodes
- PCI address: `0000:31:00.1` (configured in `pktgen.config`)
- Device parameters: `txqs_min_inline=0,txq_mpw_en=1,txq_inline_mpw=256`

### Core Allocation
- Core 0: Typically reserved for main/control thread
- L3FWD: Uses cores 0 to N (core 0 as main, 1-N as workers)
- Pktgen: Core 0 as main, split remaining for RX/TX

### Known Issues and Retry Logic
- SEGFAULT errors can occur intermittently (hardware/driver related)
- Benchmark scripts include retry logic (up to 3 attempts per configuration)
- Always cleanup DPDK resources between test runs

## Research Goal: Adaptive DPDK Tuning with ML

### Core Idea
Build an adaptive system that dynamically tunes DPDK parameters to optimize performance under changing conditions (workloads, hardware contention, network patterns).

### Two-Tier Architecture

**Data Plane (Fast Path):**
- Decision tree (DT) or symbolic expression (SE) for μs-scale decisions
- Extracted via knowledge distillation from pre-trained RL model
- Handles known/confident cases with minimal overhead

**Control Plane (Slow Path):**
- Background RL training on observed system metrics
- Continuous learning from runtime data
- Periodic distillation to update data plane DT/SE

### Key Challenges Addressed

1. **μs-scale Latency Requirement**: Direct ML inference (ms-level) too slow for DPDK critical path
2. **Complex Parameter Space**: Simple heuristics insufficient; counter-intuitive patterns exist (e.g., "high LLC miss → smaller descriptor better" for cache thrashing prevention)
3. **Dynamic Environments**: New workloads/hardware require continuous adaptation; pre-defined rules cannot cover all cases

### Workflow

1. System monitors hardware metrics (PCIe BW, LLC miss, packet rate, etc.)
2. **Known conditions**: Fast path uses distilled DT/SE for immediate tuning
3. **Unknown conditions**: Detected via confidence/novelty detection → apply safe default → log to control plane for learning
4. Control plane periodically re-trains RL model and updates DT/SE via distillation

### Critical Design Decisions

**Novelty Detection:**
- Confidence threshold on DT predictions or distance metric in state space
- Conservative approach: low confidence → fallback to safe default

**Safe Default:**
- Pre-characterized conservative configuration (e.g., static best-average config)
- Ensures performance never drops below baseline during exploration

**Update Protocol:**
- Atomic swap of DT/SE to avoid inconsistency
- Validation period before deploying new distilled model

**Baseline Comparison:**
- Must empirically show "nearest neighbor in lookup table" causes performance degradation
- Demonstrate non-linear decision boundaries require learned models

### Experimental Validation Needed

1. Characterization study: measure performance variation across 50+ workload/config combinations
2. Simple baseline comparison: static config, rule-based, lookup table, linear model
3. Quantify ML benefit: improvement over best simple baseline (target: >30%)
4. Show counter-intuitive patterns discovered by ML
5. Convergence analysis: time to adapt to new conditions, sample complexity

### Target Venue
- **Primary**: NSDI (networking systems focus)
- **Secondary**: OSDI (if broader OS insights emerge)
