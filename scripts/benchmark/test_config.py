import os
import subprocess

################## HELPER FUNCTIONS #####################

def _load_bash_config(config_file):
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

def _detect_perf_events():
    """Auto-detect available LLC-related perf events from system"""
    try:
        result = subprocess.run(['sudo', 'perf', 'list'], capture_output=True, text=True, timeout=10)
        available = result.stdout + result.stderr
    except:
        return [], []

    llc_event_candidates = [
        'LLC-loads', 'LLC-load-misses', 'LLC-stores', 'LLC-store-misses',
        'unc_cha_llc_lookup.data_read', 'unc_cha_llc_lookup.write', 'unc_cha_llc_lookup.any',
    ]
    metric_candidates = [
        'llc_miss_local_memory_bandwidth_read', 'llc_miss_local_memory_bandwidth_write',
    ]
    return [e for e in llc_event_candidates if e in available], [m for m in metric_candidates if m in available]

def _calculate_profiling_time(warmup, perf_dur, pcm_dur, neohost_dur, interval, enable_perf, enable_pcm, enable_neohost):
    """Calculate total time needed for enabled profilers"""
    total = warmup
    if enable_perf:
        total += perf_dur
    if enable_pcm:
        total += interval + pcm_dur
    if enable_neohost:
        neohost_python = f'{DPDK_BENCH_HOME}/neohost/miniconda3/envs/py27/bin/python'
        neohost_sdk = f'{DPDK_BENCH_HOME}/neohost/sdk/opt/neohost/sdk/get_device_performance_counters.py'
        if os.path.exists(neohost_python) and os.path.exists(neohost_sdk):
            total += interval + neohost_dur
    return total + interval

################## PATHS #####################
DPDK_BENCH_HOME = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
DPDK_PATH = f'{DPDK_BENCH_HOME}/dpdk'
PKTGEN_PATH = f'{DPDK_BENCH_HOME}/Pktgen-DPDK'
RESULTS_PATH = f'{DPDK_BENCH_HOME}/results'
DATA_PATH = RESULTS_PATH
ENV = f'LD_LIBRARY_PATH={DPDK_PATH}/build/lib:{DPDK_PATH}/build/lib/x86_64-linux-gnu'

################## LOAD CONFIG FILES #####################
CLUSTER_CONFIG = _load_bash_config(f'{DPDK_BENCH_HOME}/cluster.config')
SYSTEM_CONFIG = _load_bash_config(f'{DPDK_BENCH_HOME}/config/system.config')

################## CLUSTER CONFIG #####################
PKTGEN_NODE = CLUSTER_CONFIG.get('PKTGEN_NODE', 'node7')
L3FWD_NODE = CLUSTER_CONFIG.get('L3FWD_NODE', 'node8')

################## NIC CONFIG #####################
PKTGEN_MAC = SYSTEM_CONFIG.get('PKTGEN_NIC_MAC', '')
PKTGEN_PCI_ADDRESS = SYSTEM_CONFIG.get('PKTGEN_NIC_PCI', '')
PKTGEN_NIC_DEVARGS = 'txqs_min_inline=8'

L3FWD_PCI_ADDRESS = SYSTEM_CONFIG.get('L3FWD_NIC_PCI', '')
L3FWD_NIC_DEVARGS = 'txqs_min_inline=0,txq_mpw_en=1,txq_inline_mpw=256'
L3FWD_ETH_DEST = PKTGEN_MAC

################## PROFILER CONFIG #####################
ENABLE_PERF = True
ENABLE_PCM = True
ENABLE_NEOHOST = True

WARMUP_DELAY = 10
TOOL_INTERVAL = 5
PERF_DURATION = 15
PCM_DURATION = 15
NEOHOST_DURATION = 20

PERF_EVENTS, PERF_METRICS = _detect_perf_events()
PERF_UNITS = {
    'LLC-loads': 'count', 'LLC-load-misses': 'count',
    'LLC-stores': 'count', 'LLC-store-misses': 'count',
    'unc_cha_llc_lookup.data_read': 'count', 'unc_cha_llc_lookup.write': 'count',
    'unc_cha_llc_lookup.any': 'count',
    'llc_miss_local_memory_bandwidth_read': 'MB/s', 'llc_miss_local_memory_bandwidth_write': 'MB/s',
}

PKTGEN_DURATION = _calculate_profiling_time(
    WARMUP_DELAY, PERF_DURATION, PCM_DURATION, NEOHOST_DURATION,
    TOOL_INTERVAL, ENABLE_PERF, ENABLE_PCM, ENABLE_NEOHOST
)

################## TEST PARAMETERS #####################
PKTGEN_PACKET_SIZE = 64

L3FWD_TX_DESC_VALUES = [1024]
L3FWD_RX_DESC_VALUES = [1024]
PKTGEN_TX_DESC_VALUES = [1024]

L3FWD_LCORE_VALUES = [2]
PKTGEN_TX_CORE_VALUES = [1, 2, 4, 8]

################## CONFIG GENERATORS #####################

def get_l3fwd_config(lcore_count):
    """Generate L3FWD configuration for given lcore count"""
    lcores = f"-l 0-{lcore_count}"
    config_parts = [f"(0,{i-1},{i})" for i in range(1, lcore_count + 1)]
    return {
        "binary_path": f"{DPDK_PATH}/build/examples/dpdk-l3fwd",
        "node": L3FWD_NODE,
        "lcores": lcores,
        "memory_channels": "-n 4",
        "pci_address": f"{L3FWD_PCI_ADDRESS},{L3FWD_NIC_DEVARGS}",
        "port_mask": "-p 0x1",
        "config": ",".join(config_parts),
        "eth_dest": L3FWD_ETH_DEST
    }

def get_pktgen_config(tx_core_count):
    """Generate PKTGEN configuration for given TX core count

    tx_core_count=2 → cores: 0(main), 1(RX), 2-3(TX)
    """
    total_lcore = 1 + tx_core_count
    port_map = f"[1:{2}].0" if tx_core_count == 1 else f"[1:2-{total_lcore}].0"
    return {
        "binary_path": f"{PKTGEN_PATH}/build/app/pktgen",
        "working_dir": PKTGEN_PATH,
        "node": PKTGEN_NODE,
        "lcores": f"-l 0-{total_lcore}",
        "memory_channels": "-n 4",
        "pci_address": f"{PKTGEN_PCI_ADDRESS},{PKTGEN_NIC_DEVARGS}",
        "proc_type": "--proc-type auto",
        "file_prefix": "pktgen1",
        "port_map": port_map,
        "app_args": "-P -T",
        "script_file": "scripts/simple-tx-test.lua"
    }
