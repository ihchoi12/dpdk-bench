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
    """Auto-detect available I/O LLC hit/miss perf events from system"""
    try:
        result = subprocess.run(['sudo', 'perf', 'list'], capture_output=True, text=True, timeout=10)
        available = result.stdout + result.stderr
    except:
        return []

    # Only track NIC TX (PCIe RdCur) LLC hit/miss events
    io_event_candidates = [
        'unc_i_coherent_ops.pcirdcur',       # Total PCIe RdCur requests (NIC TX)
        'unc_cha_tor_inserts.io_miss_rdcur', # RdCur LLC misses
    ]
    return [e for e in io_event_candidates if e in available]

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

def get_l3fwd_config(lcore_count):
    """Generate L3FWD configuration for given lcore count"""
    lcores = f"-l 0-{lcore_count}"
    config_parts = [f"(0,{i-1},{i})" for i in range(1, lcore_count + 1)]
    # Build PCI address with optional devargs
    pci_addr = L3FWD_PCI_ADDRESS
    if L3FWD_NIC_DEVARGS:
        pci_addr = f"{L3FWD_PCI_ADDRESS},{L3FWD_NIC_DEVARGS}"
    return {
        "binary_path": f"{DPDK_PATH}/build/examples/dpdk-l3fwd",
        "node": L3FWD_NODE,
        "lcores": lcores,
        "memory_channels": "-n 4",
        "pci_address": pci_addr,
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
    # Build PCI address with optional devargs
    pci_addr = PKTGEN_PCI_ADDRESS
    if PKTGEN_NIC_DEVARGS:
        pci_addr = f"{PKTGEN_PCI_ADDRESS},{PKTGEN_NIC_DEVARGS}"
    return {
        "binary_path": f"{PKTGEN_PATH}/build/app/pktgen",
        "working_dir": PKTGEN_PATH,
        "node": PKTGEN_NODE,
        "lcores": f"-l 0-{total_lcore}",
        "memory_channels": "-n 4",
        "pci_address": pci_addr,
        "proc_type": "--proc-type auto",
        "file_prefix": "pktgen1",
        "port_map": port_map,
        "app_args": "-P -T",
        "script_file": f"{DPDK_BENCH_HOME}/config/simple-test/simple-test.lua"
    }

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

################## LOAD TEST CONFIG #####################
TEST_CONFIG = _load_bash_config(f'{DPDK_BENCH_HOME}/config/simple-test/simple-test.config')

################## NIC CONFIG #####################
PKTGEN_MAC = SYSTEM_CONFIG.get('PKTGEN_NIC_MAC', '')
PKTGEN_PCI_ADDRESS = SYSTEM_CONFIG.get('PKTGEN_NIC_PCI', '')
PKTGEN_NIC_DEVARGS = TEST_CONFIG.get('PKTGEN_NIC_DEVARGS', '')

L3FWD_MAC = SYSTEM_CONFIG.get('L3FWD_NIC_MAC', '')
L3FWD_PCI_ADDRESS = SYSTEM_CONFIG.get('L3FWD_NIC_PCI', '')
L3FWD_NIC_DEVARGS = TEST_CONFIG.get('L3FWD_NIC_DEVARGS', '')
L3FWD_ETH_DEST = PKTGEN_MAC

def validate_config():
    """Validate required configuration before running tests"""
    errors = []
    if not PKTGEN_MAC:
        errors.append("PKTGEN_NIC_MAC not set in config/system.config")
    if not PKTGEN_PCI_ADDRESS:
        errors.append("PKTGEN_NIC_PCI not set in config/system.config")
    if not L3FWD_MAC:
        errors.append("L3FWD_NIC_MAC not set in config/system.config")
    if not L3FWD_PCI_ADDRESS:
        errors.append("L3FWD_NIC_PCI not set in config/system.config")

    if errors:
        print("ERROR: Missing required configuration:")
        for e in errors:
            print(f"  - {e}")
        print("\nRun 'entry.sh' option 1 to configure NIC settings")
        return False
    return True

################## PROFILER CONFIG #####################
ENABLE_PERF = False  # Disabled: using pcm-pcie -e for DDIO miss rate instead
ENABLE_PCM = True
ENABLE_NEOHOST = True

WARMUP_DELAY = 10
TOOL_INTERVAL = 5
PERF_DURATION = 15
PCM_DURATION = 15
NEOHOST_DURATION = 20

PERF_EVENTS = _detect_perf_events()
PERF_UNITS = {
    'unc_i_coherent_ops.pcirdcur': 'count',       # Total PCIe RdCur requests
    'unc_cha_tor_inserts.io_miss_rdcur': 'count', # RdCur LLC misses
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
PKTGEN_TX_CORE_VALUES = [1]
