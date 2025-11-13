# DPDK Benchmark Suite

High-performance network packet processing benchmark using DPDK, Pktgen, and Intel PCM.

## Architecture

This project uses custom forks of DPDK and Pktgen with modifications for performance monitoring and debugging:

- **DPDK fork**: https://github.com/ihchoi12/dpdk.git (branch: `autokernel`)
- **Pktgen fork**: https://github.com/ihchoi12/Pktgen-DPDK.git (branch: `autokernel`)
- **Common PCM wrapper**: Shared performance monitoring code in `common/pcm/`

All customizations are committed directly to the `autokernel` branch in each fork.

## System Information

Check CPU architecture and NIC bandwidth:

```bash
./scripts/show_system_info.sh
```

## Quick Start

### 1. Install Dependencies

```bash
sudo apt update && sudo apt install -y \
  meson ninja-build build-essential pkg-config git cmake \
  libnuma-dev libpcap-dev python3-pyelftools liblua5.3-dev \
  libibverbs-dev librdmacm-dev rdma-core ibverbs-providers libmlx5-1 \
  libelf-dev libbsd-dev zlib1g-dev
```

### 2. Machine Setup

Configure hugepages and enable MSR module for PCM monitoring:

```bash
sudo ./scripts/setup_machines.sh
```

**Verify PCM setup:**
```bash
lsmod | grep msr           # Should show msr module loaded
ls /dev/cpu/0/msr          # Should exist
```

### 3. Build All Components

```bash
make submodules
```

This builds:
- Intel PCM library
- DPDK with L3FWD example
- Pktgen-DPDK

**Debug build (with TX/RX logging):**
```bash
make submodules-debug
```

### 4. Run Pktgen

```bash
make run-pktgen-with-lua-script
```

## Development Workflow

### Initial Build

```bash
git clone <this-repo>
cd dpdk-bench
make submodules
```

### Incremental Rebuilds

After modifying source files in submodules:

```bash
# Rebuild only L3FWD
make l3fwd-rebuild

# Rebuild only Pktgen
make pktgen-rebuild
```

### Modifying DPDK or Pktgen

Changes are committed directly to fork branches:

```bash
# Example: Modifying DPDK
cd dpdk
git checkout autokernel      # Ensure on autokernel branch
# ... make your changes ...
git add <files>
git commit -m "Your change description"
git push fork autokernel

# Example: Modifying Pktgen
cd Pktgen-DPDK
git checkout autokernel
# ... make your changes ...
git add <files>
git commit -m "Your change description"
git push fork autokernel
```

**Important:** Always work on the `autokernel` branch, not `main`.

## Configuration

Edit `pktgen.config` to customize:

```bash
# CPU cores
PKTGEN_LCORES=-l 0-14
L3FWD_LCORES=-l 0-2

# Network interfaces
PKTGEN_PCI_ADDR=0000:31:00.1
L3FWD_PCI_ADDR=0000:31:00.1

# Memory
PKTGEN_MEMORY_CHANNELS=4
```

## Performance Monitoring (Intel PCM)

Intel PCM (Performance Counter Monitor) is integrated for hardware-level performance monitoring. PCM tracks CPU cache hits/misses, memory bandwidth, PCIe bandwidth, and other low-level metrics.

### Disabling PCM

To disable PCM monitoring and eliminate all performance counter overhead, set the `DISABLE_PCM` environment variable:

```bash
# Disable PCM for a single run
DISABLE_PCM=1 make run-pktgen-with-lua-script

# Disable PCM globally in your shell session
export DISABLE_PCM=1
make run-pktgen-with-lua-script
```

**When PCM is disabled:**
- No performance counter reads occur (zero overhead)
- All PCM initialization and measurement functions return immediately
- PCM library logs may still appear during startup (these are harmless)

**Use cases for disabling PCM:**
- Maximum packet processing performance (no measurement overhead)
- Running on systems without MSR access
- Comparing performance with and without monitoring

## Hardware Setup

### Intel X710 NICs (10GbE)

Intel X710 uses the i40e PMD (included in DPDK by default).

1. **Identify your NIC:**
   ```bash
   # Find PCI address and interface name
   lspci | grep Ethernet
   ./dpdk/usertools/dpdk-devbind.py --status
   ```

2. **Bind NIC to DPDK:**
   ```bash
   # Take interface down (replace enp24s0f1np1 with your interface)
   sudo ip link set enp24s0f1np1 down

   # Load DPDK-compatible driver (choose one)
   sudo modprobe vfio-pci          # Recommended (IOMMU support)
   # OR
   sudo modprobe uio_pci_generic   # Alternative (if IOMMU unavailable)

   # Verify driver loaded
   lsmod | grep -E "vfio|uio"

   # Bind to DPDK driver (replace 0000:18:00.1 with your PCI address)
   sudo ./dpdk/usertools/dpdk-devbind.py --bind=vfio-pci 0000:18:00.1
   ```

3. **Verify binding:**
   ```bash
   ./dpdk/usertools/dpdk-devbind.py --status
   ```

   Should show:
   ```
   Network devices using DPDK-compatible driver
   ============================================
   0000:18:00.1 'Ethernet Controller X710 for 10GbE SFP+ 1572' drv=vfio-pci unused=i40e
   ```

4. **Update `pktgen.config`:**
   - Set `PKTGEN_PCI_ADDR` and `L3FWD_PCI_ADDR` to your NIC's PCI address
   - Use NUMA node 0 cores if NIC is on NUMA 0 (check with `./scripts/show_system_info.sh`)

5. **To restore kernel driver:**
   ```bash
   sudo ./dpdk/usertools/dpdk-devbind.py --bind=i40e 0000:18:00.1
   sudo ip link set enp24s0f1np1 up
   ```

### Mellanox ConnectX-5 NICs

Works out of the box with MLX5 PMD (included in DPDK).

### AMD Solarflare NICs (SFC9120)

1. **Identify NIC:**
   ```bash
   lspci | grep -i ethernet
   sudo ./dpdk/usertools/dpdk-devbind.py --status
   ```

2. **Enable SFC driver:**

   Edit `build/init_submodules.sh` line 18, remove `net/sfc` from `DISABLE_DRIVERS`:
   ```bash
   # Before: ...net/qede,net/sfc,net/softnic...
   # After:  ...net/qede,net/softnic...
   ```

3. **Bind NIC to DPDK:**
   ```bash
   sudo ip link set <interface> down
   sudo modprobe uio_pci_generic
   sudo ./dpdk/usertools/dpdk-devbind.py --bind=uio_pci_generic <pci_address>
   ```

4. **Rebuild:**
   ```bash
   make clean
   make submodules
   ```

## Performance Monitoring

### Intel PCM

This suite integrates Intel PCM for hardware performance counters:

- **L2/L3 cache hits/misses**
- **DRAM bandwidth** (read/write MB/s)
- **PCIe bandwidth** (read/write MB/s)
- **Instructions per cycle (IPC)**

Metrics are automatically collected during L3FWD runs and logged with packet statistics.

### NeoHost Profiling Tool

NeoHost provides device-level performance counter analysis for network interfaces:

```bash
# Run NeoHost profiling (replace device UID as needed)
sudo /homes/friedj/neohost/miniconda3/envs/py27/bin/python \
  /homes/friedj/neohost/sdk/opt/neohost/sdk/get_device_performance_counters.py \
  --dev-uid=0000:31:00.0 \
  --get-analysis \
  --run-loop

**Note:** Switch `--dev-uid` parameter based on which NIC port you are using (0000:31:00.0 or 0000:31:00.1).

## Troubleshooting

### Build fails with "libdpdk not found"

Ensure PKG_CONFIG_PATH is set:
```bash
export PKG_CONFIG_PATH="/path/to/dpdk/build/lib/pkgconfig:${PKG_CONFIG_PATH}"
```

### PCM fails with "Access to Intel PCM denied"

```bash
# Verify MSR module
sudo modprobe msr
lsmod | grep msr

# Check permissions
ls -l /dev/cpu/0/msr
```

### Pktgen shows 0 TX rate

Check:
1. NIC is bound to DPDK driver
2. PCI address in `pktgen.config` is correct
3. Hugepages are configured (`grep Huge /proc/meminfo`)

## Project Structure

```
dpdk-bench/
├── dpdk/                   # DPDK submodule (fork)
├── Pktgen-DPDK/           # Pktgen submodule (fork)
├── pcm/                   # Intel PCM submodule
├── common/
│   └── pcm/               # Shared PCM wrapper (C/C++)
├── scripts/               # Run and benchmark scripts
├── build/
│   └── init_submodules.sh # Build orchestration
├── Makefile               # Main build targets
├── pktgen.config          # Runtime configuration
└── README.md
```

## Key DPDK Parameters

### TX/RX Descriptor Ring Size

Configured in application code (not runtime):
- **Smaller rings** (512-1024): Lower latency, higher cache efficiency, may drop packets under load
- **Larger rings** (2048-4096): Better burst handling, higher memory usage

### Hardware RX Drops

Monitor with `ethtool -S <interface>`:
- `rx_missed_errors`: NIC RX queue full (SW processing too slow)
- `rx_no_mbuf_errors`: Mempool exhausted

Tune by:
1. Increasing RX ring size
2. Adding more cores
3. Reducing packet processing complexity

## References

- [DPDK Documentation](https://doc.dpdk.org/)
- [Pktgen-DPDK Guide](https://pktgen-dpdk.readthedocs.io/)
- [Intel PCM](https://github.com/intel/pcm)
- [DPDK Performance Report](https://fast.dpdk.org/doc/perf/DPDK_20_11_Mellanox_NIC_performance_report.pdf)



# Notes
State Space (input):
  - PCIe bandwidth
  - LLC misses
  - Cache hit rate
  - Packet rate
  - CPU utilization (per core)
  - Memory bandwidth
  - Queue depth
  - Interrupt rate
  - Flow count
  - Packet size distribution
  → 50-100 dimensional

  Action Space (output):
  - TX descriptor size
  - RX descriptor size
  - Batch size
  - Number of cores
  - Core allocation
  - Prefetch distance
  → Combinatorial explosion


   System Architecture:
  ┌─────────────────────────────────────┐
  │ Data Plane (DPDK)                   │
  │  → Fast decisions: DT (ns-level)    │
  └─────────────────────────────────────┘
             ↑ update        ↓ metrics
  ┌─────────────────────────────────────┐
  │ Control Plane (Background)          │
  │  → RL training: learn from data     │
  │  → Distillation: extract new rules  │
  │  → Update DT periodically           │
  └─────────────────────────────────────┘
  Key Insight:
  - DT는 "current best knowledge"의 snapshot
  - RL은 계속 학습하며 improve
  - Distillation은 주기적으로 update
  - Convergence guarantee 제공

  Contribution:
  1. Novel online learning architecture
  2. Continuous improvement without overhead
  3. Formal guarantee on staleness
  4. Systems mechanism for safe update

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