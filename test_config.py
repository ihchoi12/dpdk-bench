import os
import pandas as pd
import numpy as np

################## PATHS #####################
HOME = os.path.expanduser("~")
LOCAL = HOME.replace("/homes", "/local")
DPDK_BENCH_HOME = f'{HOME}/Autokernel/dpdk-bench'
DPDK_PATH = f'{DPDK_BENCH_HOME}/dpdk'
PKTGEN_PATH = f'{DPDK_BENCH_HOME}/Pktgen-DPDK'
RESULTS_PATH = f'{DPDK_BENCH_HOME}/results'
SCRIPTS_PATH = f'{DPDK_BENCH_HOME}/scripts'

################## CLUSTER CONFIG #####################
# ============================================================
# CLUSTER NODE CONFIGURATION
# Modify this section when changing nodes or cluster setup
# ============================================================

# Node5 Configuration (Current PKTGEN node)
NODE5_HOSTNAME = 'node5'
NODE5_IP = '10.0.1.5'
NODE5_MAC = '08:c0:eb:xx:xx:xx'  # Update with actual MAC if needed
NODE5_PCI_ADDRESS = '0000:b3:00.0'  # Mellanox ConnectX-5
NODE5_NIC_DEVARGS = ''  # Mellanox-specific device args

# Node8 Configuration (Current L3FWD node)
NODE8_HOSTNAME = 'node8'
NODE8_IP = '10.0.1.8'
NODE8_MAC = '08:c0:eb:b6:e8:05'
NODE8_PCI_ADDRESS = '0000:31:00.1'  # Update with actual PCI address
NODE8_NIC_DEVARGS = 'txqs_min_inline=0'  # Mellanox-specific device args

# Active node assignments
PKTGEN_NODE = NODE5_HOSTNAME
PKTGEN_PCI_ADDRESS = NODE5_PCI_ADDRESS
PKTGEN_NIC_DEVARGS = NODE5_NIC_DEVARGS

L3FWD_NODE = NODE8_HOSTNAME
L3FWD_PCI_ADDRESS = NODE8_PCI_ADDRESS
L3FWD_NIC_DEVARGS = NODE8_NIC_DEVARGS
L3FWD_ETH_DEST = NODE5_MAC  # L3FWD forwards to PKTGEN node

# Legacy node info (for backward compatibility)
ALL_NODES = [PKTGEN_NODE, L3FWD_NODE]
NODE7_IP = '10.0.1.7'
NODE7_MAC = '08:c0:eb:b6:cd:5d'


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
PKTGEN_DURATION = 80  # Duration in seconds for pktgen transmission
PKTGEN_PACKET_SIZE = 64  # Packet size in bytes
PERF_START_DELAY = 10  # Delay in seconds before starting perf stat
PERF_DURATION = 15  # Duration in seconds for perf stat monitoring
PCM_START_DELAY = 5  # Delay in seconds after perf ends before starting pcm-pcie
PCM_DURATION = 15  # Duration in seconds for pcm-pcie monitoring
NEOHOST_START_DELAY = 5  # Delay in seconds after pcm-pcie ends before starting neohost
NEOHOST_DURATION = 20  # Duration in seconds for neohost monitoring

# L3FWD Descriptor configuration
L3FWD_TX_DESC_VALUES = [1024] #[128, 512, 1024, 1024*2, 1024*4, 1024*8, 1024*16, 1024*32]  # L3FWD TX descriptor sizes
L3FWD_RX_DESC_VALUES = [1024]  # L3FWD RX descriptor sizes

# PKTGEN TX Descriptor configuration  
PKTGEN_TX_DESC_VALUES = [1024]  # PKTGEN TX descriptor sizes - simplified for testing

# LCORE test configuration  
# L3FWD LCORE configuration - can use any number of cores
L3FWD_LCORE_COUNTS = [2]  # L3FWD core counts to test
L3FWD_LCORE_VALUES = L3FWD_LCORE_COUNTS

# PKTGEN LCORE configuration - number of TX cores (RX is always core 1, TX cores start from core 2)
PKTGEN_LCORE_COUNTS = [4]  # Number of TX cores to test
PKTGEN_LCORE_VALUES = PKTGEN_LCORE_COUNTS

################## BUILD CONFIG #####################
LIBOS = 'dpdk'  # DPDK-based applications
# FEATURES = [
#     'high-performance',
#     'low-latency',
# ]


################## ENV VARS #####################
### DPDK ###
ENV = f'LD_LIBRARY_PATH={DPDK_PATH}/build/lib:{DPDK_PATH}/build/lib/x86_64-linux-gnu'
### DATA COLLECTION ###
DATA_PATH = f'{DPDK_BENCH_HOME}/results'

# Remove unused imports and configs

# commands
# python3 -u run_test.py 2>&1 | tee -a /homes/inho/Autokernel/dpdk-bench/results/experiment_history.txt
# python3 run_test.py build