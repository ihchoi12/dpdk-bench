import os

def load_bash_config(config_file):
    """Parse bash-style config file (KEY=value) and return dict"""
    config = {}
    if not os.path.exists(config_file):
        return config
    with open(config_file, 'r') as f:
        for line in f:
            line = line.strip()
            if not line or line.startswith('#'):
                continue
            if '=' in line:
                key, value = line.split('=', 1)
                config[key.strip()] = value.strip()
    return config

################## PATHS #####################
DPDK_BENCH_HOME = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
DPDK_PATH = f'{DPDK_BENCH_HOME}/dpdk'
PKTGEN_PATH = f'{DPDK_BENCH_HOME}/Pktgen-DPDK'
RESULTS_PATH = f'{DPDK_BENCH_HOME}/results'
DATA_PATH = RESULTS_PATH

# Load configuration files
CLUSTER_CONFIG = load_bash_config(f'{DPDK_BENCH_HOME}/cluster.config')
SYSTEM_CONFIG = load_bash_config(f'{DPDK_BENCH_HOME}/config/system.config')
TEST_CONFIG = load_bash_config(f'{DPDK_BENCH_HOME}/config/test.config')

################## CLUSTER CONFIG #####################
PKTGEN_NODE = CLUSTER_CONFIG.get('PKTGEN_NODE', 'node7')
L3FWD_NODE = CLUSTER_CONFIG.get('L3FWD_NODE', 'node8')

# NIC Configuration (from system.config + test.config)
PKTGEN_MAC = SYSTEM_CONFIG.get('PKTGEN_NIC_MAC', '')
PKTGEN_PCI_ADDRESS = SYSTEM_CONFIG.get('PKTGEN_NIC_PCI', '')
PKTGEN_NIC_DEVARGS = TEST_CONFIG.get('PKTGEN_NIC_DEVARGS', '')

L3FWD_PCI_ADDRESS = SYSTEM_CONFIG.get('L3FWD_NIC_PCI', '')
L3FWD_NIC_DEVARGS = TEST_CONFIG.get('L3FWD_NIC_DEVARGS', '')
L3FWD_ETH_DEST = PKTGEN_MAC

################## DPDK CONFIG #####################

def get_l3fwd_config(lcore_count):
    """Generate L3FWD configuration for given lcore count"""
    # L3FWD uses cores 1 to lcore_count (core 0 is main)
    lcores = f"-l 0-{lcore_count}"

    # Generate config string: (port,queue,lcore) for each working core
    config_parts = []
    for i in range(1, lcore_count + 1):
        queue_id = i - 1  # Queue starts from 0
        config_parts.append(f"(0,{queue_id},{i})")
    config = ",".join(config_parts)

    return {
        "binary_path": f"{DPDK_PATH}/build/examples/dpdk-l3fwd",
        "node": L3FWD_NODE,
        "lcores": lcores,
        "memory_channels": "-n 4",
        "pci_address": f"{L3FWD_PCI_ADDRESS},{L3FWD_NIC_DEVARGS}",
        "port_mask": "-p 0x1",
        "config": config,
        "eth_dest": L3FWD_ETH_DEST
    }

def get_pktgen_config(tx_core_count):
    """Generate PKTGEN configuration for given TX core count

    Args:
        tx_core_count: Number of TX cores (RX core is always core 1, TX cores start from core 2)

    Example:
        tx_core_count=2 → cores: 0(main), 1(RX), 2-3(TX)
        tx_core_count=3 → cores: 0(main), 1(RX), 2-4(TX)
    """
    # Total cores needed: 1(main) + 1(RX) + tx_core_count(TX)
    # lcores: 0 to (1 + tx_core_count)
    total_lcore = 1 + tx_core_count
    lcores = f"-l 0-{total_lcore}"

    # RX: always core 1 only, TX: cores 2 to (1 + tx_core_count)
    rx_core = 1
    tx_start = 2
    tx_end = total_lcore

    # Generate port_map: [RX_core:TX_start-TX_end].port
    if tx_core_count == 1:
        # Special case: only 1 TX core (core 2)
        port_map = f"[{rx_core}:{tx_start}].0"
    else:
        # Multiple TX cores
        port_map = f"[{rx_core}:{tx_start}-{tx_end}].0"

    return {
        "binary_path": f"{PKTGEN_PATH}/build/app/pktgen",
        "working_dir": f"{PKTGEN_PATH}",
        "node": PKTGEN_NODE,
        "lcores": lcores,
        "memory_channels": "-n 4",
        "pci_address": f"{PKTGEN_PCI_ADDRESS},{PKTGEN_NIC_DEVARGS}",
        "proc_type": "--proc-type auto",
        "file_prefix": "pktgen1",
        "port_map": port_map,
        "app_args": "-P -T",
        "script_file": "scripts/simple-tx-test.lua"
    }

# Default configurations (for backward compatibility)
L3FWD_CONFIG = get_l3fwd_config(4)  # Default to 4 lcores
PKTGEN_CONFIG = get_pktgen_config(14)  # Default to 14 TX cores

################## TEST CONFIG #####################
PKTGEN_PACKET_SIZE = 64  # Packet size in bytes

# Profiler enable/disable flags
ENABLE_PERF = True      # Enable perf stat monitoring
ENABLE_PCM = True       # Enable Intel PCM monitoring
ENABLE_NEOHOST = False   # Enable NeoHost monitoring (requires compatible NIC firmware)

# Perf event configuration
# Events: raw performance counters (use with -e flag)
PERF_EVENTS = [
    'LLC-load-misses',                        # LLC load miss count
    'LLC-store-misses',                       # LLC store miss count
    'unc_cha_llc_lookup.data_read',           # LLC data read lookups
    'unc_cha_llc_lookup.writes_and_other',    # LLC write lookups
    'unc_cha_llc_lookup.data_read_miss',      # LLC data read miss count
    'unc_cha_llc_lookup.rfo_miss',            # LLC write miss count
]

# Metrics: derived metrics (use with -M flag)
PERF_METRICS = [
    'llc_miss_local_memory_bandwidth_read',   # LLC miss read bandwidth
    'llc_miss_local_memory_bandwidth_write',  # LLC miss write bandwidth
]

# Units for each event/metric (for CSV headers)
PERF_UNITS = {
    'LLC-load-misses': 'count',
    'LLC-store-misses': 'count',
    'unc_cha_llc_lookup.data_read': 'count',
    'unc_cha_llc_lookup.writes_and_other': 'count',
    'unc_cha_llc_lookup.data_read_miss': 'count',
    'unc_cha_llc_lookup.rfo_miss': 'count',
    'llc_miss_local_memory_bandwidth_read': 'MB/s',
    'llc_miss_local_memory_bandwidth_write': 'MB/s',
}

# Profiler timing configuration
WARMUP_DELAY = 10       # Delay before starting first profiler (warmup period)
TOOL_INTERVAL = 5       # Interval between profilers and final buffer
PERF_DURATION = 15      # Duration in seconds for perf stat monitoring
PCM_DURATION = 15       # Duration in seconds for pcm-pcie monitoring
NEOHOST_DURATION = 20   # Duration in seconds for neohost monitoring

# Calculate total profiling time based on enabled profilers
def _calculate_profiling_time():
    """Calculate total time needed for enabled profilers"""
    total = WARMUP_DELAY  # Initial warmup delay

    if ENABLE_PERF:
        total += PERF_DURATION

    if ENABLE_PCM:
        total += TOOL_INTERVAL + PCM_DURATION

    if ENABLE_NEOHOST:
        # Check if neohost is actually available
        neohost_python = f'{DPDK_BENCH_HOME}/neohost/miniconda3/envs/py27/bin/python'
        neohost_sdk = f'{DPDK_BENCH_HOME}/neohost/sdk/opt/neohost/sdk/get_device_performance_counters.py'
        if os.path.exists(neohost_python) and os.path.exists(neohost_sdk):
            total += TOOL_INTERVAL + NEOHOST_DURATION

    # Add final buffer
    total += TOOL_INTERVAL
    return total

PKTGEN_DURATION = _calculate_profiling_time()  # Auto-calculated based on enabled profilers

# Descriptor configuration
L3FWD_TX_DESC_VALUES = [1024]
L3FWD_RX_DESC_VALUES = [1024]
PKTGEN_TX_DESC_VALUES = [1024]

# LCORE configuration
L3FWD_LCORE_VALUES = [2]
PKTGEN_LCORE_VALUES = [1, 2, 4, 8]  # TX cores (RX always core 1, TX starts from core 2)

################## ENV VARS #####################
ENV = f'LD_LIBRARY_PATH={DPDK_PATH}/build/lib:{DPDK_PATH}/build/lib/x86_64-linux-gnu'