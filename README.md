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

# Run l3fwd (layer 3 forwarding)
make run-l3fwd
```

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