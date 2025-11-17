# NeoHost SDK

## Setup

```bash
./setup_neohost.sh
```

## Usage

**Wrapper script (recommended):**
```bash
./run_neohost.sh --dev-uid=0000:b3:00.0 --get-analysis --run-loop
```

**Full command:**
```bash
sudo /homes/inho/Autokernel/dpdk-bench/neohost/miniconda3/envs/py27/bin/python \
    /homes/inho/Autokernel/dpdk-bench/neohost/sdk/opt/neohost/sdk/get_device_performance_counters.py \
    --dev-uid=0000:b3:00.0 \
    --get-analysis \
    --run-loop
```
