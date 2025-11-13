# Scripts

## Claude CLI Installation

Install Claude CLI on a new Ubuntu node:

```bash
./scripts/install_claude_cli.sh
```

**What it does:**
- Installs Node.js v20 (if not present)
- Installs required packages (curl, build-essential)
- Installs Claude CLI globally via npm
- Guides through API key setup

**After installation:**
```bash
# Authenticate
claude auth login

# Start using Claude
claude
```

---

## Other Scripts

### Benchmark Scripts
- `benchmark-*.sh` - Various DPDK performance benchmarks
- `run_test.py` - Python-based test orchestrator

### NeoHost Scripts

**Device performance profiling:**
```bash
sudo /homes/friedj/neohost/miniconda3/envs/py27/bin/python \
  /homes/friedj/neohost/sdk/opt/neohost/sdk/get_device_performance_counters.py \
  --dev-uid=0000:b3:00.0 \
  --get-analysis \
  --run-loop
```

- `neohost/get_device_performance_counters.py` - Local copy of NeoHost profiler
