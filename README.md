# DPDK Benchmark Suite

High-performance network packet processing benchmark using DPDK, Pktgen, and Intel PCM.

## Architecture

This project uses custom forks of DPDK and Pktgen with modifications for performance monitoring and debugging:

- **DPDK fork**: https://github.com/ihchoi12/dpdk.git (branch: `autokernel`)
- **Pktgen fork**: https://github.com/ihchoi12/Pktgen-DPDK.git (branch: `autokernel`)
- **Common PCM wrapper**: Shared performance monitoring code in `common/pcm/`

All customizations are committed directly to the `autokernel` branch in each fork.

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

## Hardware Setup

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

This suite integrates Intel PCM for hardware performance counters:

- **L2/L3 cache hits/misses**
- **DRAM bandwidth** (read/write MB/s)
- **PCIe bandwidth** (read/write MB/s)
- **Instructions per cycle (IPC)**

Metrics are automatically collected during L3FWD runs and logged with packet statistics.

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
