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

4) Run l3fwd

```
./scripts/run-l3fwd.sh
```
