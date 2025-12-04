# DPDK Benchmark Suite

High-performance network packet processing benchmark using DPDK, Pktgen, and Intel PCM.

## Quick Start

### 1. Clone and Setup

```bash
git clone <this-repo>
cd dpdk-bench
git submodule update --init --recursive
```

### 2. Run Interactive Setup

```bash
./entry.sh
```

### 3. Follow the Menu

```
╔════════════════════════════════════════════════════════════╗
║  DPDK Benchmark Suite - Interactive Menu              ║
╚════════════════════════════════════════════════════════════╝
  Cluster: PKTGEN=node14 | L3FWD=node6  (edit cluster.config to change)

  1) Show and Update System Configuration  ← Run first to detect NIC
  2) Initial Machine Setup                 ← Install dependencies & setup
  3) Build                                 ← Build all components
  4) Run Simple Pktgen Test
  5) Run Full Benchmark
  6) DDIO Control
```

**Recommended order for new machines:**
1. Option **1** - Detect and save system/NIC configuration
2. Option **2** - Install all dependencies and configure hugepages/MSR
3. Option **3-1** - Full build (DPDK, Pktgen, PCM, ddio-modify)
4. Option **4** or **5** - Run tests

## Configuration Files

| File | Description |
|------|-------------|
| `cluster.config` | Multi-node setup (PKTGEN_NODE, L3FWD_NODE) |
| `config/system.config` | Auto-detected NIC info (PCI, MAC, IP) |

## Project Structure

```
dpdk-bench/
├── entry.sh              # Interactive menu (start here!)
├── cluster.config        # Which nodes run PKTGEN/L3FWD
├── config/
│   └── system.config     # Auto-detected NIC configuration
├── dpdk/                 # DPDK submodule (autokernel branch)
├── Pktgen-DPDK/          # Pktgen submodule (autokernel branch)
├── pcm/                  # Intel PCM for performance counters
├── ddio-modify/          # DDIO control tool
└── scripts/
    └── benchmark/        # Test runner (run_test.py, test_config.py)
```

## Troubleshooting

### Build fails
- Run option **2** (Initial Machine Setup) first to install dependencies

### NIC not detected
- Run option **1** to update system.config with correct NIC info

### DDIO control fails
- Ensure option **3-1** (Full Build) was run to build ddio-modify for this machine

### PCM errors
- Option **2** sets up MSR module automatically
- Verify: `lsmod | grep msr` and `ls /dev/cpu/0/msr`

## References

- [DPDK Documentation](https://doc.dpdk.org/)
- [Pktgen-DPDK Guide](https://pktgen-dpdk.readthedocs.io/)
- [Intel PCM](https://github.com/intel/pcm)
- [DPDK Performance Report](https://fast.dpdk.org/doc/perf/DPDK_20_11_Mellanox_NIC_performance_report.pdf)
