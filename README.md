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

**Building specific components:**
```bash
# Build only l3fwd (without rebuilding DPDK)
make l3fwd

# Clean and rebuild l3fwd
make l3fwd-clean && make l3fwd

# Build only pktgen
make pktgen
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

# Run l3fwd multi-core benchmark (1-16 cores) on node8
make benchmark-l3fwd-multi-core

# Run integrated l3fwd vs pktgen RX/TX rate benchmark  
make benchmark-l3fwd-vs-pktgen

# Custom l3fwd vs pktgen testing with environment variables
L3FWD_START_CORES=1 L3FWD_END_CORES=4 PKTGEN_DURATION=5 ./scripts/benchmark-l3fwd-vs-pktgen.sh

# Custom l3fwd multi-core testing with environment variables
L3FWD_DURATION=10 L3FWD_START_CORES=1 L3FWD_END_CORES=8 ./scripts/benchmark-l3fwd-multi-core.sh

# Quick l3fwd test with specific core count
L3FWD_DURATION=5 L3FWD_START_CORES=4 L3FWD_END_CORES=4 ./scripts/benchmark-l3fwd-multi-core.sh

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

**L3FWD Multi-core Benchmark:**
- Tests Layer 3 forwarding performance across 1-16 CPU cores
- Results saved to `results/YYMMDD-HHMMSS-l3fwd-multi-core.txt`
- Format: `cores|status` (completed/failed)
- Automatic multi-queue configuration: `(0,0,0),(0,1,1),...,(0,N,N)`
- Remote execution on configurable target node (default: node8)
- Retry logic with 3 attempts per core count
- Environment variables: `L3FWD_DURATION`, `L3FWD_START_CORES`, `L3FWD_END_CORES`, `L3FWD_NODE`

**L3FWD vs Pktgen RX/TX Rate Benchmark:**
- Tests L3FWD forwarding performance with pktgen as traffic generator
- Results saved to `results/YYMMDD-HHMMSS-l3fwd-vs-pktgen.txt`
- Format: `pktgen_setup|l3fwd_setup|RX_rate|TX_rate`
- Pktgen uses 4-core combined mode for stability
- L3FWD runs on configurable target node (default: node8)
- Environment variables: `L3FWD_START_CORES`, `L3FWD_END_CORES`, `PKTGEN_DURATION`, `L3FWD_NODE`

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
- https://github.com/intel/pcm




ToDo:
- [Both pktgen & l3fwd]: check code block below
  - if 10ms interval measurement makes sense?
  - is it better to use memory controller utilization? 
```
  // Convert to reasonable values (10ms measurement period)
        double time_sec = 0.01; // 10ms
        counters->dram_read_bytes = bytes_read;
        counters->dram_write_bytes = bytes_written;
        counters->dram_read_bandwidth_mbps = (double)bytes_read / (1024.0 * 1024.0) / time_sec;
        counters->dram_write_bandwidth_mbps = (double)bytes_written / (1024.0 * 1024.0) / time_sec;
```


- check other stats and try to simplify types of stats
```
// Memory controller bandwidth (IMC)
        counters->imc_reads_gbps = (double)mc_reads / (1024.0 * 1024.0 * 1024.0) / time_sec;
        counters->imc_writes_gbps = (double)mc_writes / (1024.0 * 1024.0 * 1024.0) / time_sec;
        
        // QPI/UPI data transfer and utilization
        counters->qpi_upi_data_bytes = 0; // PCM might not support this directly
        counters->qpi_upi_utilization = 0.0;
        counters->uncore_freq_ghz = 0; // Could try to get uncore frequency if available
```




# Parameters
- TX/RX_DESC_DEFAULT: the size of descriptor ring
  - Smaller: 
    - [+] lower memory usage, higher cache efficiency
    - [-] more packet drops (ring full)
  - Bigger:
    - [+] less packet drops (better burst handling)
    - [-] more memory usage, bigger latency (queueing delay)
- Hardware RX Drops:  NIC RX pkt, but cannot DMA, so drops it
  - pkt flow: network -> physical port -> NIC HW (RX queue with 8192 entries) -> SW RX ring -> application
    - rx_phy_discard_packets: drops at physical port
    - rx_missed_errors: drops at NIC RX queue  
  - type 1) RX Missed: RX ring (descriptor: pointer to mbuf entry) is full  
    - Reasons:
      - slow CPU or application processing
      - small RX ring
      - insufficient memory BW (=> bottleneck SW pkt processing => RX ring full)
  - type 2) RX No MBuf: mbuf (actual pkt data buffer) is full








Q. Why rx_missed_errors != (Hardware RX Packets) - (pktgen RX total)?