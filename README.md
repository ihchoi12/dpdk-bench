# DPDK bench using Pktgen-DPDK



## How to Run 

1) Clone this repository.

2) Install dependencie and perform some machine setup.

```
sudo apt update && sudo apt install -y \
  meson ninja-build build-essential pkg-config git \
  libnuma-dev libpcap-dev python3-pyelftools liblua5.3-dev \
  libibverbs-dev librdmacm-dev rdma-core ibverbs-providers libmlx5-1 \
  libelf-dev libbsd-dev zlib1g-dev cmake && \
sudo ./setup_machines
```

3) Set up submodules (e.g., DPDK, SPDK, and rdma-core).

```
make submodules
```

4) Run benchmarks

```bash
# Run pktgen
make run-pktgen

# Run pktgen with lua script (automated)
make run-pktgen-with-lua-script

# Run multi-core TX rate benchmark (1-15 cores)
make benchmark-multi-core-tx-rate

# Run benchmarks with different port mapping modes
make benchmark-combined      # [1-N].0 - All cores handle RX/TX
make benchmark-split         # [1-N/2:N/2+1-N].0 - Split RX/TX (even cores only)

# Compare port mapping modes and generate performance graph
make compare-port-mappings   # Run both modes and show summary table
make generate-performance-graph  # Create PNG bar chart comparison

# Run l3fwd (layer 3 forwarding)
make run-l3fwd

# Run l3fwd on node8 for exactly 5 seconds and auto-terminate (remote execution)
make run-l3fwd-timed

# Run l3fwd on node8 for custom duration (set L3FWD_DURATION environment variable)
L3FWD_DURATION=10 make run-l3fwd-timed  # Run for 10 seconds on node8

# Run l3fwd on different node (set L3FWD_NODE environment variable)
L3FWD_NODE=node9 make run-l3fwd-timed   # Run on node9 instead of node8
```

**Multi-core TX Rate Benchmark:**
- Tests TX rate performance across 1-15 CPU cores with retry logic
- Results saved to `results/YYMMDD-HHMMSS-multi-core-tx-[mode].txt`
- Format: `setup|TX_rate_in_Mpps`
- Automatic handling of intermittent SEGFAULT errors (up to 3 retries)
- Performance graph generation in PNG format

**Port Mapping Modes:**
- **combined**: `[1-N].0` - All cores handle both RX and TX processing
- **split**: `[1-N/2:N/2+1-N].0` - Dedicated RX and TX cores (even cores only)

**Performance Results (Example):**
- Combined mode peak: ~144 Mpps at 8 cores
- Split mode peak: ~132 Mpps at 14 cores  
- Split efficiency: ~92% of combined mode at peak
- **round_robin**: Load balancing `[1].0, [1,2].0, [1,2,3].0, ...`

5) Configuration (optional)

Edit `pktgen.config` to customize parameters like CPU cores, memory channels, and PCI addresses:

```bash
# Example configuration
PKTGEN_LCORES=-l 0-14          # CPU cores for pktgen
PKTGEN_PCI_ADDR=0000:31:00.1   # Network interface
L3FWD_LCORES=-l 0-2            # CPU cores for l3fwd
```


References:
- https://developer.arm.com/documentation/109701/1-0/Example-for-Multi-core-scenario
- https://fast.dpdk.org/doc/perf/DPDK_20_11_Mellanox_NIC_performance_report.pdf